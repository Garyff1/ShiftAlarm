package com.shiftalarm.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes

object AlarmNotifications {
    const val RINGING_CHANNEL = "ringing_alarms"
    const val STATUS_CHANNEL = "schedule_status"
    const val RINGING_NOTIFICATION_ID = 31030

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val alarmAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val ringing = NotificationChannel(
            RINGING_CHANNEL,
            "正在响铃",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "锁屏闹钟、停止和贪睡操作"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setSound(null, alarmAttributes)
            enableVibration(false)
            setBypassDnd(true)
        }
        val status = NotificationChannel(
            STATUS_CHANNEL,
            "排班与权限提醒",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "排班同步、权限和闹钟状态"
        }
        manager.createNotificationChannels(listOf(ringing, status))
    }
}
