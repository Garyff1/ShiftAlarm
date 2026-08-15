package com.shiftalarm.app

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootAndTimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val recalculate = action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED ||
            action == Intent.ACTION_DATE_CHANGED
        val restored = NativeAlarmScheduler.restoreSnapshots(context, recalculate)
        val synthetic = AlarmPayload(
            id = "system_recovery",
            scheduleId = "",
            nativeAlarmId = -1,
            triggerAt = 0,
            triggerYear = 0,
            triggerMonth = 0,
            triggerDay = 0,
            triggerHour = 0,
            triggerMinute = 0,
            reminderName = "系统恢复",
            shiftCode = "",
            shiftName = "",
            arrivalAt = null,
            isTemporary = false,
            isCore = false,
            isTest = true,
            vibration = false,
            snoozeEnabled = false,
            snoozeMinutes = 0,
            maxSnoozeCount = 0,
            snoozeCount = 0,
            maxRingingMinutes = 15,
            soundId = "system",
            soundPath = null,
            directBootSoundPath = null,
            soundChecksum = null,
            fadeIn = false,
        )
        NativeAlarmStore.appendEvent(
            context,
            synthetic,
            "recovered",
            reason = "$action:$restored",
        )
        val stage = when (action) {
            Intent.ACTION_TIMEZONE_CHANGED -> "timezone_recalculated"
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_DATE_CHANGED -> "time_recalculated"
            else -> "direct_boot_restored"
        }
        val failure = if (restored == 0 && NativeAlarmStore.readSnapshots(context).isNotEmpty()) {
            "direct_boot_restore_failure"
        } else {
            null
        }
        NativeAlarmStore.appendSystemLifecycleEvent(
            context,
            stage,
            failure,
            mapOf(
                "action" to action.substringAfterLast('.'),
                "restoredCount" to restored,
                "exactAlarmPermission" to NativeAlarmScheduler.canScheduleExact(context),
            ),
        )
    }
}
