package com.shiftalarm.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlarmPayloadTest {
    private fun payload() = AlarmPayload(
        id = "alarm-1",
        scheduleId = "schedule-1",
        nativeAlarmId = 10000,
        triggerAt = 1_800_000_000_000L,
        triggerYear = 2027,
        triggerMonth = 1,
        triggerDay = 15,
        triggerHour = 6,
        triggerMinute = 30,
        reminderName = "起床",
        shiftCode = "A1",
        shiftName = "早班",
        arrivalAt = 1_800_005_400_000L,
        isTemporary = true,
        isCore = true,
        isTest = false,
        vibration = true,
        snoozeEnabled = true,
        snoozeMinutes = 10,
        maxSnoozeCount = 3,
        snoozeCount = 1,
        maxRingingMinutes = 15,
    )

    @Test
    fun jsonRoundTripPreservesReceiverPayload() {
        val original = payload()
        assertEquals(original, AlarmPayload.fromJson(original.toJson()))
    }

    @Test
    fun parserUsesSafeDefaultsForOptionalAlarmControls() {
        val parsed = AlarmPayload.fromJson(
            JSONObject()
                .put("id", "minimal")
                .put("nativeAlarmId", 9)
                .put("triggerAt", 123L),
        )
        assertTrue(parsed.vibration)
        assertTrue(parsed.snoozeEnabled)
        assertEquals(10, parsed.snoozeMinutes)
        assertEquals(3, parsed.maxSnoozeCount)
        assertEquals(15, parsed.maxRingingMinutes)
        assertNull(parsed.arrivalAt)
    }

    @Test
    fun withTriggerIncrementsSnoozeWithoutChangingStableIdentity() {
        val changed = payload().withTrigger(1_900_000_000_000L, 2)
        assertEquals("alarm-1", changed.id)
        assertEquals(10000, changed.nativeAlarmId)
        assertEquals(1_900_000_000_000L, changed.triggerAt)
        assertEquals(2, changed.snoozeCount)
        assertFalse(changed.isTest)
    }

    @Test
    fun customSoundFieldsSurviveJsonRoundTrip() {
        val custom = payload().copy(
            soundId = "sound-1",
            soundPath = "/files/sound-1.mp3",
            directBootSoundPath = "/device/sound-1.mp3",
            soundChecksum = "abc123",
            fadeIn = false,
        )
        val restored = AlarmPayload.fromJson(custom.toJson())
        assertEquals("sound-1", restored.soundId)
        assertEquals("/files/sound-1.mp3", restored.soundPath)
        assertEquals("/device/sound-1.mp3", restored.directBootSoundPath)
        assertEquals("abc123", restored.soundChecksum)
        assertFalse(restored.fadeIn)
    }

    @Test
    fun oldPayloadDefaultsToSystemSoundAndFadeIn() {
        val parsed = AlarmPayload.fromJson(
            JSONObject()
                .put("id", "legacy")
                .put("nativeAlarmId", 7)
                .put("triggerAt", 123L),
        )
        assertEquals("system", parsed.soundId)
        assertNull(parsed.soundPath)
        assertNull(parsed.soundChecksum)
        assertTrue(parsed.fadeIn)
    }

    @Test
    fun snoozeKeepsOriginalCustomSoundSnapshot() {
        val original = payload().copy(
            soundId = "sound-1",
            soundPath = "/files/sound-1.mp3",
            directBootSoundPath = "/device/sound-1.mp3",
            soundChecksum = "abc123",
        )
        val snoozed = original.withTrigger(1_900_000_000_000L, 2)
        assertEquals(original.soundId, snoozed.soundId)
        assertEquals(original.soundPath, snoozed.soundPath)
        assertEquals(original.directBootSoundPath, snoozed.directBootSoundPath)
        assertEquals(original.soundChecksum, snoozed.soundChecksum)
    }
}
