package com.shiftalarm.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object NativeAlarmStore {
    private const val PREFS = "shift_alarm_direct_boot"
    private const val SNAPSHOTS = "snapshots"
    private const val EVENTS = "events"
    private const val TRIGGER_CLAIMS = "trigger_claims"
    private const val SOUND_EVENTS = "sound_events"

    private fun preferences(context: Context) =
        context.createDeviceProtectedStorageContext()
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized
    fun replaceSnapshots(context: Context, payloads: List<AlarmPayload>) {
        val array = JSONArray()
        DirectBootSoundStore.prepareSnapshots(context, payloads).forEach { array.put(it.toJson()) }
        preferences(context).edit().putString(SNAPSHOTS, array.toString()).commit()
    }

    @Synchronized
    fun readSnapshots(context: Context): List<AlarmPayload> {
        val raw = preferences(context).getString(SNAPSHOTS, "[]") ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    runCatching { AlarmPayload.fromJson(array.getJSONObject(index)) }
                        .getOrNull()?.let(::add)
                }
            }
        }.getOrDefault(emptyList())
    }

    @Synchronized
    fun upsertSnapshot(context: Context, payload: AlarmPayload) {
        val values = readSnapshots(context).associateBy { it.nativeAlarmId }.toMutableMap()
        values[payload.nativeAlarmId] = DirectBootSoundStore.preparePayload(context, payload)
        replaceSnapshots(context, values.values.toList())
    }

    @Synchronized
    fun removeSnapshot(context: Context, nativeAlarmId: Int) {
        replaceSnapshots(context, readSnapshots(context).filter { it.nativeAlarmId != nativeAlarmId })
    }

    @Synchronized
    fun claimTrigger(context: Context, payload: AlarmPayload): Boolean {
        val prefs = preferences(context)
        val key = "${payload.nativeAlarmId}:${payload.triggerAt}"
        val claims = prefs.getStringSet(TRIGGER_CLAIMS, emptySet()).orEmpty().toMutableSet()
        if (!claims.add(key)) return false
        if (claims.size > 128) {
            val retained = claims.sorted().takeLast(128)
            claims.clear()
            claims.addAll(retained)
        }
        return prefs.edit().putStringSet(TRIGGER_CLAIMS, claims).commit()
    }

    @Synchronized
    fun appendEvent(
        context: Context,
        payload: AlarmPayload,
        status: String,
        triggerAt: Long? = null,
        reason: String? = null,
    ) {
        val prefs = preferences(context)
        val array = runCatching { JSONArray(prefs.getString(EVENTS, "[]")) }.getOrDefault(JSONArray())
        array.put(JSONObject().apply {
            put("id", payload.id)
            put("nativeAlarmId", payload.nativeAlarmId)
            put("status", status)
            put("at", System.currentTimeMillis())
            put("isTest", payload.isTest)
            put("snoozeCount", payload.snoozeCount)
            if (triggerAt != null) put("triggerAt", triggerAt)
            if (reason != null) put("reason", reason)
        })
        prefs.edit().putString(EVENTS, array.toString()).commit()
    }

    @Synchronized
    fun consumeEvents(context: Context): List<Map<String, Any?>> {
        val prefs = preferences(context)
        val raw = prefs.getString(EVENTS, "[]") ?: "[]"
        prefs.edit().putString(EVENTS, "[]").commit()
        return runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val json = array.getJSONObject(index)
                    add(buildMap {
                        json.keys().forEach { key ->
                            put(key, if (json.isNull(key)) null else json.get(key))
                        }
                    })
                }
            }
        }.getOrDefault(emptyList())
    }

    @Synchronized
    fun appendSoundEvent(
        context: Context,
        payload: AlarmPayload,
        reason: String,
    ) {
        val prefs = preferences(context)
        val array = runCatching { JSONArray(prefs.getString(SOUND_EVENTS, "[]")) }.getOrDefault(JSONArray())
        array.put(JSONObject().apply {
            put("soundId", payload.soundId)
            put("alarmId", payload.id)
            put("nativeAlarmId", payload.nativeAlarmId)
            put("reason", reason)
            put("at", System.currentTimeMillis())
        })
        prefs.edit().putString(SOUND_EVENTS, array.toString()).commit()
    }

    @Synchronized
    fun consumeSoundEvents(context: Context): List<Map<String, Any?>> {
        val prefs = preferences(context)
        val raw = prefs.getString(SOUND_EVENTS, "[]") ?: "[]"
        prefs.edit().putString(SOUND_EVENTS, "[]").commit()
        return runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val json = array.getJSONObject(index)
                    add(buildMap {
                        json.keys().forEach { key ->
                            put(key, if (json.isNull(key)) null else json.get(key))
                        }
                    })
                }
            }
        }.getOrDefault(emptyList())
    }
}
