package com.shiftalarm.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlarmRulesTest {
    @Test
    fun alarmActionIsStableAndUniquePerNativeId() {
        assertEquals("com.shiftalarm.app.ALARM.10000", AlarmIdentity.alarmAction("com.shiftalarm.app", 10000))
        assertFalse(
            AlarmIdentity.alarmAction("com.shiftalarm.app", 10000) ==
                AlarmIdentity.alarmAction("com.shiftalarm.app", 10001),
        )
    }

    @Test
    fun alarmActionValidationRejectsWrongIdOrPackage() {
        assertTrue(
            AlarmIdentity.matchesAlarmAction(
                "com.shiftalarm.app",
                10000,
                "com.shiftalarm.app.ALARM.10000",
            ),
        )
        assertFalse(
            AlarmIdentity.matchesAlarmAction(
                "com.shiftalarm.app",
                10000,
                "com.shiftalarm.app.ALARM.10001",
            ),
        )
        assertFalse(AlarmIdentity.matchesAlarmAction("com.shiftalarm.app", 0, "com.shiftalarm.app.ALARM.0"))
    }

    @Test
    fun notificationActionsHaveDistinctRequestCodes() {
        assertEquals(100001, AlarmIdentity.actionRequestCode(10000, 1))
        assertEquals(100002, AlarmIdentity.actionRequestCode(10000, 2))
        assertFalse(
            AlarmIdentity.actionRequestCode(10000, 1) ==
                AlarmIdentity.actionRequestCode(10001, 1),
        )
    }

    @Test
    fun snoozeAllowedBeforeLimit() {
        assertTrue(AlarmPolicy.canSnooze(enabled = true, snoozeCount = 2, maxSnoozeCount = 3))
    }

    @Test
    fun snoozeRejectedAtLimitOrWhenDisabled() {
        assertFalse(AlarmPolicy.canSnooze(enabled = true, snoozeCount = 3, maxSnoozeCount = 3))
        assertFalse(AlarmPolicy.canSnooze(enabled = false, snoozeCount = 0, maxSnoozeCount = 3))
        assertFalse(AlarmPolicy.canSnooze(enabled = true, snoozeCount = -1, maxSnoozeCount = 3))
    }

    @Test
    fun snoozeDelayHasOneMinuteSafetyFloor() {
        assertEquals(60_000L, AlarmPolicy.snoozeDelayMillis(0))
        assertEquals(420_000L, AlarmPolicy.snoozeDelayMillis(7))
    }

    @Test
    fun snoozeTriggerUsesProvidedClock() {
        assertEquals(1_420_000L, AlarmPolicy.snoozeTriggerAt(1_000_000L, 7))
    }

    @Test
    fun ringingTimeoutHasOneMinuteFloorAndSupportsFifteenMinutes() {
        assertEquals(60_000L, AlarmPolicy.ringingTimeoutMillis(0))
        assertEquals(900_000L, AlarmPolicy.ringingTimeoutMillis(15))
    }

    @Test
    fun recoveryKeepsOnlyStrictlyFutureTriggers() {
        assertEquals(
            listOf(1_001L, 2_000L),
            AlarmPolicy.filterFutureTriggerTimes(listOf(999L, 1_000L, 1_001L, 2_000L), 1_000L),
        )
    }
}
