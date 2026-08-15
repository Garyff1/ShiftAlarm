package com.shiftalarm.app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class AlarmRingingService : Service() {
    private var payload: AlarmPayload? = null
    private var audioPlayer: AlarmAudioPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finishAlarm("triggered", "timed_out", keepMissedNotification = true) }

    override fun onCreate() {
        super.onCreate()
        AlarmNotifications.createChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val incoming = AlarmPayload.fromIntent(intent) ?: return START_NOT_STICKY
        runCatching {
            when (intent?.action) {
                ACTION_STOP -> finishAlarm("dismissed", "user_stopped")
                ACTION_SNOOZE -> snooze(incoming)
                else -> startRinging(incoming)
            }
        }.onFailure { error ->
            NativeAlarmStore.appendLifecycleEvent(
                this,
                incoming,
                "service_failed",
                if (error is SecurityException) {
                    "notification_failure"
                } else {
                    "foreground_service_failure"
                },
                mapOf("errorType" to error.javaClass.simpleName),
            )
            NativeAlarmStore.appendEvent(
                this,
                incoming,
                "failed",
                reason = "ring_service_failure",
            )
            releaseAndStop(removeNotification = true)
        }
        return START_NOT_STICKY
    }

    private fun startRinging(incoming: AlarmPayload) {
        if (payload?.nativeAlarmId == incoming.nativeAlarmId && audioPlayer?.isPlaying() == true) return
        releaseResources()
        payload = incoming
        val notification = buildNotification(incoming)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                AlarmNotifications.RINGING_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(AlarmNotifications.RINGING_NOTIFICATION_ID, notification)
        }
        NativeAlarmStore.appendLifecycleEvent(
            this,
            incoming,
            "ring_service_started",
            details = mapOf(
                "notificationVisible" to true,
                "fullScreenRequested" to (incoming.isCore || incoming.isTest),
            ),
        )
        acquireWakeLock(incoming)
        val audioStarted = playSound(incoming)
        if (!audioStarted) {
            NativeAlarmStore.appendEvent(
                this,
                incoming,
                "failed",
                reason = "audio_playback_failure",
            )
        }
        if (incoming.vibration) startVibration()
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, AlarmPolicy.ringingTimeoutMillis(incoming.maxRingingMinutes))
    }

    private fun buildNotification(payload: AlarmPayload): Notification {
        val activityIntent = payload.putInto(Intent(this, AlarmRingingActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val activityPending = PendingIntent.getActivity(
            this,
            payload.nativeAlarmId,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopPending = actionPendingIntent(payload, AlarmActionReceiver.ACTION_STOP, 1)
        val builder = Notification.Builder(this, AlarmNotifications.RINGING_CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(payload.reminderName)
            .setContentText("${payload.shiftCode} ${payload.shiftName}".trim())
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(activityPending)
            .setFullScreenIntent(activityPending, payload.isCore || payload.isTest)
            .addAction(Notification.Action.Builder(null, "停止", stopPending).build())
        if (AlarmPolicy.canSnooze(payload.snoozeEnabled, payload.snoozeCount, payload.maxSnoozeCount)) {
            builder.addAction(
                Notification.Action.Builder(
                    null,
                    "贪睡 ${payload.snoozeMinutes} 分钟",
                    actionPendingIntent(payload, AlarmActionReceiver.ACTION_SNOOZE, 2),
                ).build(),
            )
        }
        return builder.build()
    }

    private fun actionPendingIntent(payload: AlarmPayload, action: String, offset: Int): PendingIntent {
        val intent = payload.putInto(Intent(this, AlarmActionReceiver::class.java)).apply { this.action = action }
        return PendingIntent.getBroadcast(
            this,
            AlarmIdentity.actionRequestCode(payload.nativeAlarmId, offset),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun acquireWakeLock(payload: AlarmPayload) {
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:ringing:${payload.nativeAlarmId}")
            .apply { acquire(AlarmPolicy.ringingTimeoutMillis(payload.maxRingingMinutes) + 10_000L) }
    }

    private fun playSound(payload: AlarmPayload): Boolean {
        audioPlayer = AlarmAudioPlayer(
            context = this,
            onCustomFallback = { reason ->
                NativeAlarmStore.appendSoundEvent(this, payload, reason)
            },
            onLifecycle = { stage, failureCategory, details ->
                NativeAlarmStore.appendLifecycleEvent(
                    this,
                    payload,
                    stage,
                    failureCategory,
                    details,
                )
            },
        )
        return audioPlayer?.start(payload) == true
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 500, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun snooze(source: AlarmPayload) {
        val current = payload ?: source
        if (!AlarmPolicy.canSnooze(current.snoozeEnabled, current.snoozeCount, current.maxSnoozeCount)) {
            finishAlarm("dismissed", "snooze_limit")
            return
        }
        val trigger = AlarmPolicy.snoozeTriggerAt(System.currentTimeMillis(), current.snoozeMinutes)
        val snoozed = current.withTrigger(trigger, current.snoozeCount + 1)
        val result = NativeAlarmScheduler.schedule(this, snoozed)
        if (result.isSuccess) {
            NativeAlarmStore.upsertSnapshot(this, snoozed)
            NativeAlarmStore.appendLifecycleEvent(
                this,
                snoozed,
                "snoozed",
                details = mapOf("snoozeCount" to snoozed.snoozeCount),
            )
            NativeAlarmStore.appendEvent(this, snoozed, "snoozed", triggerAt = trigger)
            releaseAndStop(removeNotification = true)
        } else {
            finishAlarm("failed", result.exceptionOrNull()?.message ?: "snooze_failed")
        }
    }

    private fun finishAlarm(status: String, reason: String, keepMissedNotification: Boolean = false) {
        val current = payload
        if (current != null) {
            val lifecycleStage = when {
                status == "dismissed" -> "dismissed"
                reason == "timed_out" -> "timeout"
                reason.contains("playback", ignoreCase = true) -> "playback_failed"
                else -> "service_failed"
            }
            val failureCategory = when (lifecycleStage) {
                "playback_failed" -> "audio_playback_failure"
                "service_failed" -> "foreground_service_failure"
                else -> null
            }
            NativeAlarmStore.appendLifecycleEvent(
                this,
                current,
                lifecycleStage,
                failureCategory,
                mapOf("reason" to reason),
            )
            NativeAlarmStore.appendEvent(this, current, status, reason = reason)
            NativeAlarmStore.removeSnapshot(this, current.nativeAlarmId)
            if (keepMissedNotification) postMissedNotification(current)
        }
        releaseAndStop(removeNotification = !keepMissedNotification)
    }

    private fun postMissedNotification(payload: AlarmPayload) {
        val notification = Notification.Builder(this, AlarmNotifications.STATUS_CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("闹钟未响应")
            .setContentText("${payload.reminderName} · ${payload.shiftCode}")
            .setAutoCancel(true)
            .build()
        getSystemService(NotificationManager::class.java)
            .notify(AlarmNotifications.RINGING_NOTIFICATION_ID + 1, notification)
    }

    private fun releaseAndStop(removeNotification: Boolean) {
        releaseResources()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(if (removeNotification) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(removeNotification)
        }
        sendBroadcast(Intent(ACTION_FINISHED).setPackage(packageName))
        stopSelf()
    }

    private fun releaseResources() {
        handler.removeCallbacks(timeout)
        audioPlayer?.release()
        audioPlayer = null
        vibrator?.cancel()
        vibrator = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    override fun onDestroy() {
        releaseResources()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.shiftalarm.app.service.START"
        const val ACTION_STOP = "com.shiftalarm.app.service.STOP"
        const val ACTION_SNOOZE = "com.shiftalarm.app.service.SNOOZE"
        const val ACTION_FINISHED = "com.shiftalarm.app.ALARM_FINISHED"
    }
}
