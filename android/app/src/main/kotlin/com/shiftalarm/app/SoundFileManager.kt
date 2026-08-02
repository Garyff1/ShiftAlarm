package com.shiftalarm.app

import android.content.Context
import android.database.Cursor
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID

object SoundFileManager {
    const val MAX_BYTES = 50L * 1024L * 1024L
    private const val TEMP_MAX_AGE = 24L * 60L * 60L * 1000L

    private val mimeToFormat = mapOf(
        "audio/mpeg" to "mp3",
        "audio/mp3" to "mp3",
        "audio/wav" to "wav",
        "audio/x-wav" to "wav",
        "audio/raw" to "wav",
        "audio/mp4" to "m4a",
        "audio/x-m4a" to "m4a",
        "audio/mp4a-latm" to "m4a",
        "audio/aac" to "aac",
        "audio/aac-adts" to "aac",
        "audio/ogg" to "ogg",
        "audio/vorbis" to "ogg",
        "audio/opus" to "ogg",
        "application/ogg" to "ogg",
    )

    data class Inspection(
        val mimeType: String,
        val format: String,
        val fileSize: Long,
        val durationMilliseconds: Long,
        val checksum: String,
    ) {
        fun toMap() = mapOf(
            "mimeType" to mimeType,
            "format" to format,
            "fileSize" to fileSize,
            "durationMilliseconds" to durationMilliseconds,
            "checksum" to checksum,
        )
    }

    fun importToTemp(context: Context, uri: Uri): Map<String, Any?> {
        cleanupTemps(context)
        val metadata = queryMetadata(context, uri)
        val tempRoot = tempDir(context).apply { mkdirs() }
        val provisional = File(tempRoot, "import_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.tmp")
        try {
            var total = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(provisional).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > MAX_BYTES) throw IllegalArgumentException("file_too_large")
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            } ?: throw IllegalArgumentException("file_unreadable")
            if (total == 0L) throw IllegalArgumentException("file_empty")
            val inspection = inspect(provisional)
            val finalTemp = File(tempRoot, provisional.nameWithoutExtension + "." + inspection.format)
            if (!provisional.renameTo(finalTemp)) {
                provisional.copyTo(finalTemp, overwrite = false)
                provisional.delete()
            }
            return buildMap {
                putAll(inspection.toMap())
                put("tempPath", finalTemp.absolutePath)
                put("sourceName", metadata.first)
                put("displayName", metadata.first.substringBeforeLast('.').take(120).ifBlank { "自定义铃声" })
                put("sourceUri", uri.toString())
                put("providerMimeType", metadata.second)
            }
        } catch (error: Throwable) {
            provisional.delete()
            throw error
        }
    }

    fun commitImport(context: Context, tempPath: String): String {
        val source = checkedChild(tempDir(context), tempPath)
        if (!source.isFile || source.length() == 0L) throw IllegalArgumentException("temp_missing")
        val inspection = inspect(source)
        val root = soundDir(context).apply { mkdirs() }
        val target = File(
            root,
            "sound_${System.currentTimeMillis()}_${UUID.randomUUID().toString().replace("-", "").take(6)}.${inspection.format}",
        )
        if (!source.renameTo(target)) {
            source.copyTo(target, overwrite = false)
            source.delete()
        }
        return target.absolutePath
    }

    fun discardImport(context: Context, tempPath: String): Boolean =
        runCatching { checkedChild(tempDir(context), tempPath).delete() }.getOrDefault(false)

    fun deleteInternal(context: Context, path: String): Boolean =
        runCatching { checkedChild(soundDir(context), path).delete() }.getOrDefault(false)

    fun verifyInternal(context: Context, path: String, expectedChecksum: String?): Map<String, Any?> =
        runCatching {
            val file = checkedChild(soundDir(context), path)
            val inspection = inspect(file)
            if (!expectedChecksum.isNullOrBlank() && inspection.checksum != expectedChecksum) {
                throw IllegalArgumentException("checksum_mismatch")
            }
            buildMap<String, Any?> {
                put("isAvailable", true)
                putAll(inspection.toMap())
                put("failureReason", null)
            }
        }.getOrElse { error ->
            mapOf(
                "isAvailable" to false,
                "failureReason" to errorCode(error),
            )
        }

    fun cleanupTemps(context: Context): Int {
        val cutoff = System.currentTimeMillis() - TEMP_MAX_AGE
        return tempDir(context).listFiles().orEmpty().count { file ->
            file.lastModified() < cutoff && file.delete()
        }
    }

    /** Removes only unreferenced managed files. The temp directory is handled separately. */
    fun cleanupOrphans(context: Context, retainedPaths: Collection<String>): Int {
        val root = soundDir(context).canonicalFile
        val retained = retainedPaths.mapNotNull { path ->
            runCatching { checkedChild(root, path).canonicalPath }.getOrNull()
        }.toSet()
        return root.listFiles().orEmpty().count { file ->
            file.isFile && file.canonicalPath !in retained && file.delete()
        }
    }

    fun inspect(file: File): Inspection {
        if (!file.isFile) throw IllegalArgumentException("file_missing")
        val size = file.length()
        if (size == 0L) throw IllegalArgumentException("file_empty")
        if (size > MAX_BYTES) throw IllegalArgumentException("file_too_large")
        val mime = actualAudioMime(file)
        val format = mimeToFormat[mime] ?: throw IllegalArgumentException("format_unsupported")
        var duration = 0L
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val hasAudio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
            if (hasAudio == "no") throw IllegalArgumentException("not_audio")
        } finally {
            retriever.release()
        }
        val player = MediaPlayer()
        try {
            player.setDataSource(file.absolutePath)
            player.prepare()
            if (duration <= 0L) duration = player.duration.toLong().coerceAtLeast(0L)
        } catch (error: Throwable) {
            throw IllegalArgumentException("decode_failed", error)
        } finally {
            player.release()
        }
        return Inspection(mime, format, size, duration, sha256(file))
    }

    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun errorCode(error: Throwable): String =
        (error as? IllegalArgumentException)?.message ?: "read_failed"

    fun soundDir(context: Context) = File(context.filesDir, "alarm_sounds")
    private fun tempDir(context: Context) = File(soundDir(context), "temp")

    private fun checkedChild(root: File, path: String): File {
        val rootPath = root.canonicalFile.toPath()
        val file = File(path).canonicalFile
        if (!file.toPath().startsWith(rootPath)) throw SecurityException("path_outside_sound_dir")
        return file
    }

    private fun actualAudioMime(file: File): String {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            for (index in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.lowercase()
                if (mime?.startsWith("audio/") == true && mimeToFormat.containsKey(mime)) return mime
            }
        } catch (error: Throwable) {
            throw IllegalArgumentException("decode_failed", error)
        } finally {
            extractor.release()
        }
        throw IllegalArgumentException("not_audio")
    }

    private fun queryMetadata(context: Context, uri: Uri): Pair<String, String> {
        var name = "自定义铃声"
        var mime = context.contentResolver.getType(uri) ?: "audio/*"
        val cursor: Cursor? = context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) name = it.getString(nameIndex)?.take(180) ?: name
                val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !it.isNull(sizeIndex) && it.getLong(sizeIndex) > MAX_BYTES) {
                    throw IllegalArgumentException("file_too_large")
                }
            }
        }
        if (!mime.startsWith("audio/") && mime != "application/ogg") mime = "audio/*"
        return name to mime
    }
}
