package com.shiftalarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val payload = AlarmPayload.fromIntent(intent) ?: return
        val action = when (intent.action) {
            ACTION_STOP -> AlarmRingingService.ACTION_STOP
            ACTION_SNOOZE -> AlarmRingingService.ACTION_SNOOZE
            else -> return
        }
        val serviceIntent = payload.putInto(Intent(context, AlarmRingingService::class.java)).apply {
            this.action = action
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }

    companion object {
        const val ACTION_STOP = "com.shiftalarm.app.action.STOP_ALARM"
        const val ACTION_SNOOZE = "com.shiftalarm.app.action.SNOOZE_ALARM"
    }
}
