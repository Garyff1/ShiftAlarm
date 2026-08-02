package com.shiftalarm.app

import org.junit.Assert.assertEquals
import org.junit.Test

class AlarmAudioPlayerTest {
    @Test
    fun fadeStartsAtEightPercent() {
        assertEquals(0.08f, AlarmAudioPlayer.fadeVolume(0L), 0.0001f)
    }

    @Test
    fun fadeReachesExpectedMidpointAtFifteenSeconds() {
        assertEquals(0.54f, AlarmAudioPlayer.fadeVolume(15_000L), 0.0001f)
    }

    @Test
    fun fadeReachesFullVolumeAtThirtySeconds() {
        assertEquals(1.0f, AlarmAudioPlayer.fadeVolume(30_000L), 0.0001f)
    }

    @Test
    fun fadeClampsBeforeStartAndAfterDuration() {
        assertEquals(0.08f, AlarmAudioPlayer.fadeVolume(-5_000L), 0.0001f)
        assertEquals(1.0f, AlarmAudioPlayer.fadeVolume(90_000L), 0.0001f)
    }
}
