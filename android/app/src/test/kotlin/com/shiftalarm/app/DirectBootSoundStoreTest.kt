package com.shiftalarm.app

import java.nio.file.Files
import kotlin.io.path.writeBytes
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectBootSoundStoreTest {
    @Test
    fun `empty file is rejected`() {
        val file = Files.createTempFile("shift-alarm-empty", ".mp3").toFile()
        try {
            assertFalse(DirectBootSoundStore.isVerifiedSoundFile(file, null))
        } finally {
            file.delete()
        }
    }

    @Test
    fun `non-empty file without checksum is accepted`() {
        val path = Files.createTempFile("shift-alarm-audio", ".mp3")
        path.writeBytes(byteArrayOf(1, 2, 3))
        try {
            assertTrue(DirectBootSoundStore.isVerifiedSoundFile(path.toFile(), null))
        } finally {
            path.toFile().delete()
        }
    }

    @Test
    fun `matching checksum is accepted`() {
        val path = Files.createTempFile("shift-alarm-audio", ".mp3")
        path.writeBytes("verified audio".toByteArray())
        try {
            val file = path.toFile()
            assertTrue(
                DirectBootSoundStore.isVerifiedSoundFile(
                    file,
                    SoundFileManager.sha256(file),
                ),
            )
        } finally {
            path.toFile().delete()
        }
    }

    @Test
    fun `mismatching checksum is rejected`() {
        val path = Files.createTempFile("shift-alarm-audio", ".mp3")
        path.writeBytes("tampered audio".toByteArray())
        try {
            assertFalse(
                DirectBootSoundStore.isVerifiedSoundFile(
                    path.toFile(),
                    "7e4c3ded0822095ab831763e9271aa0f48052caea5b5953e92640de3e9341e7e",
                ),
            )
        } finally {
            path.toFile().delete()
        }
    }
}
