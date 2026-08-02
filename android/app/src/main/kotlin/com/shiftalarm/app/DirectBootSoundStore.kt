package com.shiftalarm.app

import android.content.Context
import java.io.File

object DirectBootSoundStore {
    private fun root(context: Context) = File(
        context.createDeviceProtectedStorageContext().filesDir,
        "alarm_sounds",
    )

    fun preparePayload(context: Context, payload: AlarmPayload): AlarmPayload {
        if (payload.soundId == "system" || payload.soundPath.isNullOrBlank()) {
            return payload.copy(directBootSoundPath = null)
        }
        val existing = payload.directBootSoundPath?.let(::File)
        if (existing != null && isVerifiedSoundFile(existing, payload.soundChecksum)) return payload
        val source = File(payload.soundPath)
        if (!isVerifiedSoundFile(source, payload.soundChecksum)) {
            return payload.copy(directBootSoundPath = null)
        }
        val directory = root(context).apply { mkdirs() }
        val suffix = source.extension.lowercase().ifBlank { "audio" }
        val key = payload.soundChecksum?.take(32) ?: payload.soundId.replace(Regex("[^A-Za-z0-9_-]"), "_")
        val target = File(directory, "sound_${key}.$suffix")
        if (target.length() != source.length() || !isVerifiedSoundFile(target, payload.soundChecksum)) {
            val temp = File(directory, target.name + ".tmp")
            source.copyTo(temp, overwrite = true)
            if (target.exists()) target.delete()
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
        }
        return payload.copy(directBootSoundPath = target.absolutePath)
    }

    internal fun isVerifiedSoundFile(file: File, checksum: String?): Boolean {
        if (!file.isFile || file.length() == 0L) return false
        if (checksum.isNullOrBlank()) return true
        return runCatching { SoundFileManager.sha256(file) }.getOrNull() == checksum
    }

    fun prepareSnapshots(context: Context, payloads: List<AlarmPayload>): List<AlarmPayload> {
        val prepared = payloads.map { preparePayload(context, it) }
        val retained = prepared.mapNotNull { it.directBootSoundPath }.map { File(it).canonicalPath }.toSet()
        root(context).listFiles().orEmpty().forEach { file ->
            if (file.isFile && file.canonicalPath !in retained && !file.name.endsWith(".tmp")) file.delete()
        }
        return prepared
    }

    fun playablePath(payload: AlarmPayload): String? =
        listOfNotNull(payload.soundPath, payload.directBootSoundPath)
            .firstOrNull { path -> File(path).isFile && File(path).length() > 0L }
}
