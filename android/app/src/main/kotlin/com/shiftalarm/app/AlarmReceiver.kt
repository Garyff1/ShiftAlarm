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
        NativeAlarmStore.appendLifecycleEvent(context, payload, "receiver_received")
        NativeAlarmStore.appendEvent(context, payload, "ringing")
        val serviceIntent = payload.putInto(Intent(context, AlarmRingingService::class.java)).apply {
            action = AlarmRingingService.ACTION_START
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }.onFailure { error ->
            NativeAlarmStore.appendLifecycleEvent(
                context,
                payload,
                "service_failed",
                "foreground_service_failure",
                mapOf("errorType" to error.javaClass.simpleName),
            )
            NativeAlarmStore.appendEvent(
                context,
                payload,
                "failed",
                reason = "foreground_service_failure",
            )
        }
    }
}
