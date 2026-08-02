package com.shiftalarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val payload = AlarmPayload.fromIntent(intent) ?: return
        if (!AlarmIdentity.matchesAlarmAction(context.packageName, payload.nativeAlarmId, intent.action)) return
        if (!NativeAlarmStore.claimTrigger(context, payload)) return
        NativeAlarmStore.appendEvent(context, payload, "ringing")
        val serviceIntent = payload.putInto(Intent(context, AlarmRingingService::class.java)).apply {
            action = AlarmRingingService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
