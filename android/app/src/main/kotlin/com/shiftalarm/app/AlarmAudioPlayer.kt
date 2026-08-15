package com.shiftalarm.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File

class AlarmAudioPlayer(
    private val context: Context,
    private val onCustomFallback: (String) -> Unit,
    private val onLifecycle: (String, String?, Map<String, Any?>) -> Unit,
) {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var tone: ToneGenerator? = null
    private var focusRequest: AudioFocusRequest? = null
    private var fadeStartedAt = 0L
    private var fadeEnabled = false
    private var pausedForFocus = false
    private var focusStatus = "not_requested"

    private val fadeStep = object : Runnable {
        override fun run() {
            val current = player ?: return
            val elapsed = System.currentTimeMillis() - fadeStartedAt
            val volume = (0.08f + 0.92f * (elapsed / FADE_DURATION.toFloat())).coerceIn(0.08f, 1f)
            current.setVolume(volume, volume)
            if (volume < 1f) handler.postDelayed(this, FADE_STEP)
        }
    }
    private val repeatTone = object : Runnable {
        override fun run() {
            tone?.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 58_000)
            if (tone != null) handler.postDelayed(this, 58_000)
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                player?.let {
                    if (pausedForFocus && !it.isPlaying) runCatching { it.start() }
                    if (!fadeEnabled) it.setVolume(1f, 1f)
                }
                pausedForFocus = false
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> player?.setVolume(0.3f, 0.3f)
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS -> {
                player?.takeIf { it.isPlaying }?.let {
                    runCatching { it.pause() }
                    pausedForFocus = true
                }
            }
        }
    }

    fun start(payload: AlarmPayload): Boolean {
        release()
        focusStatus = requestFocus()
        fadeEnabled = payload.fadeIn
        val customRequested = payload.soundId != "system"
        if (customRequested) {
            val reason = runCatching {
                val path = selectCustomPath(payload) ?: throw IllegalArgumentException("custom_sound_missing")
                startPlayer(
                    path = path,
                    system = false,
                    fadeIn = payload.fadeIn,
                    soundType = "custom",
                    fallback = false,
                )
                Log.i(TAG, "custom_started id=${payload.soundId} path=$path directBoot=${path == payload.directBootSoundPath}")
            }.exceptionOrNull()?.let(SoundFileManager::errorCode)
            if (reason == null) return true
            Log.w(TAG, "custom_fallback id=${payload.soundId} reason=$reason")
            onCustomFallback(reason)
            onLifecycle(
                "diagnostic_failure",
                "custom_sound_unavailable",
                mapOf("reason" to reason, "fallback" to "system"),
            )
        }
        val systemFailure = runCatching {
            startPlayer(
                path = null,
                system = true,
                fadeIn = payload.fadeIn,
                soundType = "system",
                fallback = customRequested,
            )
            Log.i(TAG, "system_started requested=${payload.soundId}")
        }.exceptionOrNull()
        if (systemFailure == null) return true
        val systemReason = SoundFileManager.errorCode(systemFailure)
        Log.w(TAG, "system_fallback_to_tone reason=$systemReason")
        val toneFailure = runCatching { startToneFallback() }.exceptionOrNull()
        if (toneFailure == null) {
            onLifecycle(
                "audio_started",
                null,
                mapOf(
                    "soundType" to "tone",
                    "fallback" to true,
                    "audioFocus" to focusStatus,
                ),
            )
            return true
        }
        onLifecycle(
            "playback_failed",
            "audio_playback_failure",
            mapOf(
                "systemReason" to systemReason,
                "toneErrorType" to toneFailure.javaClass.simpleName,
                "audioFocus" to focusStatus,
            ),
        )
        return false
    }

    private fun selectCustomPath(payload: AlarmPayload): String? {
        for (path in listOfNotNull(payload.soundPath, payload.directBootSoundPath)) {
            val file = File(path)
            if (!file.isFile || file.length() == 0L) continue
            if (!payload.soundChecksum.isNullOrBlank() &&
                runCatching { SoundFileManager.sha256(file) }.getOrNull() != payload.soundChecksum
            ) continue
            return path
        }
        return null
    }

    private fun startPlayer(
        path: String?,
        system: Boolean,
        fadeIn: Boolean,
        soundType: String,
        fallback: Boolean,
    ) {
        val mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            if (system) {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: throw IllegalStateException("system_sound_missing")
                setDataSource(context, uri)
            } else {
                require(!path.isNullOrBlank()) { "custom_sound_missing" }
                setDataSource(path)
            }
            isLooping = true
            prepare()
            onLifecycle(
                "audio_prepared",
                null,
                mapOf(
                    "soundType" to soundType,
                    "fallback" to fallback,
                    "audioFocus" to focusStatus,
                ),
            )
            val initial = if (fadeIn) 0.08f else 1f
            setVolume(initial, initial)
            start()
            onLifecycle(
                "audio_started",
                null,
                mapOf(
                    "soundType" to soundType,
                    "fallback" to fallback,
                    "audioFocus" to focusStatus,
                ),
            )
        }
        player = mediaPlayer
        if (fadeIn) {
            fadeStartedAt = System.currentTimeMillis()
            handler.post(fadeStep)
        }
    }

    private fun startToneFallback() {
        tone = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        check(tone?.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 58_000) == true) {
            "tone_start_failed"
        }
        handler.postDelayed(repeatTone, 58_000)
    }

    fun isPlaying(): Boolean = player?.isPlaying == true || tone != null

    fun release() {
        handler.removeCallbacks(fadeStep)
        handler.removeCallbacks(repeatTone)
        runCatching { player?.stop() }
        player?.release()
        player = null
        tone?.stopTone()
        tone?.release()
        tone = null
        pausedForFocus = false
        abandonFocus()
    }

    private fun requestFocus(): String {
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
        return when (result) {
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> "granted"
            AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> "delayed"
            else -> "failed"
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let(audioManager::abandonAudioFocusRequest)
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    companion object {
        private const val TAG = "ShiftAlarmAudio"
        const val FADE_DURATION = 30_000L
        const val FADE_STEP = 500L
        fun fadeVolume(elapsedMilliseconds: Long): Float =
            (0.08f + 0.92f * (elapsedMilliseconds / FADE_DURATION.toFloat())).coerceIn(0.08f, 1f)
    }
}
