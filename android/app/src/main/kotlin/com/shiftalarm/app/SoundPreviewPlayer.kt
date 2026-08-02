package com.shiftalarm.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build

class SoundPreviewPlayer(private val context: Context) {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private var player: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private var currentPath: String? = null
    private var usingSystem = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> player?.let {
                it.setVolume(1f, 1f)
                if (!it.isPlaying) runCatching { it.start() }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> player?.setVolume(0.25f, 0.25f)
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> pause()
            AudioManager.AUDIOFOCUS_LOSS -> stop()
        }
    }

    fun play(path: String?, system: Boolean): Map<String, Any?> {
        stop()
        if (!requestFocus()) throw IllegalStateException("audio_focus_denied")
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        val mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(attributes)
            if (system) {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                setDataSource(context, uri)
            } else {
                require(!path.isNullOrBlank()) { "sound_path_missing" }
                setDataSource(path)
            }
            isLooping = false
            setOnCompletionListener { stop() }
            prepare()
            start()
        }
        player = mediaPlayer
        currentPath = path
        usingSystem = system
        return state()
    }

    fun pause() {
        player?.takeIf { it.isPlaying }?.pause()
    }

    fun resume(): Map<String, Any?> {
        player?.let { if (!it.isPlaying) it.start() }
        return state()
    }

    fun stop() {
        runCatching { player?.stop() }
        player?.release()
        player = null
        currentPath = null
        usingSystem = false
        abandonFocus()
    }

    fun state(): Map<String, Any?> {
        val current = player
        return mapOf(
            "isPlaying" to (current?.isPlaying == true),
            "positionMilliseconds" to (current?.currentPosition ?: 0),
            "durationMilliseconds" to (current?.duration ?: 0),
            "path" to currentPath,
            "isSystem" to usingSystem,
        )
    }

    private fun requestFocus(): Boolean {
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setOnAudioFocusChangeListener(focusListener)
                .setWillPauseWhenDucked(false)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
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
}
