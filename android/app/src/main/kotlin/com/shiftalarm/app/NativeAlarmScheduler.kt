package com.shiftalarm.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object NativeAlarmScheduler {
    const val TEST_ALARM_ID = 9001

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    }

    fun schedule(context: Context, payload: AlarmPayload): Result<Unit> = runCatching {
        val ready = DirectBootSoundStore.preparePayload(context, payload)
        require(ready.triggerAt > System.currentTimeMillis()) { "trigger_in_past" }
        check(canScheduleExact(context)) { "exact_alarm_permission_denied" }
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val operation = alarmPendingIntent(context, ready)
        if (ready.isCore) {
            val showIntent = PendingIntent.getActivity(
                context,
                ready.nativeAlarmId,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(ready.triggerAt, showIntent),
                operation,
            )
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                ready.triggerAt,
                operation,
            )
        }
    }

    fun cancel(context: Context, nativeAlarmId: Int) {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = AlarmIdentity.alarmAction(context.packageName, nativeAlarmId)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            nativeAlarmId,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pending != null) {
            context.getSystemService(AlarmManager::class.java).cancel(pending)
            pending.cancel()
        }
        NativeAlarmStore.removeSnapshot(context, nativeAlarmId)
    }

    fun restoreSnapshots(context: Context, recalculateLocalTime: Boolean): Int {
        if (!canScheduleExact(context)) return 0
        var restored = 0
        val future = mutableListOf<AlarmPayload>()
        NativeAlarmStore.readSnapshots(context).forEach { saved ->
            val payload = if (recalculateLocalTime) saved.withCurrentTimeZone() else saved
            if (AlarmPolicy.isFuture(payload.triggerAt, System.currentTimeMillis()) && schedule(context, payload).isSuccess) {
                restored++
                future += payload
            }
        }
        NativeAlarmStore.replaceSnapshots(context, future)
        return restored
    }

    private fun alarmPendingIntent(context: Context, payload: AlarmPayload): PendingIntent {
        val intent = payload.putInto(Intent(context, AlarmReceiver::class.java)).apply {
            action = AlarmIdentity.alarmAction(context.packageName, payload.nativeAlarmId)
        }
        return PendingIntent.getBroadcast(
            context,
            payload.nativeAlarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
