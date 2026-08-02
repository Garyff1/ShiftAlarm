package com.shiftalarm.app

object AlarmIdentity {
    fun alarmAction(packageName: String, nativeAlarmId: Int): String =
        "$packageName.ALARM.$nativeAlarmId"

    fun actionRequestCode(nativeAlarmId: Int, offset: Int): Int =
        Math.addExact(Math.multiplyExact(nativeAlarmId, 10), offset)

    fun matchesAlarmAction(packageName: String, nativeAlarmId: Int, action: String?): Boolean =
        nativeAlarmId > 0 && action == alarmAction(packageName, nativeAlarmId)
}

object AlarmPolicy {
    fun canSnooze(enabled: Boolean, snoozeCount: Int, maxSnoozeCount: Int): Boolean =
        enabled && snoozeCount >= 0 && snoozeCount < maxSnoozeCount

    fun snoozeDelayMillis(snoozeMinutes: Int): Long =
        snoozeMinutes.coerceAtLeast(1) * 60_000L

    fun snoozeTriggerAt(nowMillis: Long, snoozeMinutes: Int): Long =
        Math.addExact(nowMillis, snoozeDelayMillis(snoozeMinutes))

    fun ringingTimeoutMillis(maxRingingMinutes: Int): Long =
        maxRingingMinutes.coerceAtLeast(1) * 60_000L

    fun isFuture(triggerAt: Long, nowMillis: Long): Boolean = triggerAt > nowMillis

    fun filterFutureTriggerTimes(triggerTimes: Iterable<Long>, nowMillis: Long): List<Long> =
        triggerTimes.filter { isFuture(it, nowMillis) }
}
