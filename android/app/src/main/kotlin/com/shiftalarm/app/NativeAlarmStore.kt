package com.shiftalarm.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object NativeAlarmStore {
    private const val PREFS = "shift_alarm_direct_boot"
    private const val SNAPSHOTS = "snapshots"
    private const val EVENTS = "events"
    private const val LIFECYCLE_EVENTS = "lifecycle_events"
    private const val TRIGGER_CLAIMS = "trigger_claims"
    private const val SOUND_EVENTS = "sound_events"
    private const val MAX_LIFECYCLE_EVENTS = 1000
    private const val LIFECYCLE_RETENTION_MILLIS = 30L * 24L * 60L * 60L * 1000L

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
    fun appendLifecycleEvent(
        context: Context,
        payload: AlarmPayload,
        stage: String,
        failureCategory: String? = null,
        details: Map<String, Any?> = emptyMap(),
    ) = appendLifecycleEvent(
        context = context,
        alarmId = payload.id,
        scheduleId = payload.scheduleId.ifBlank { null },
        nativeAlarmId = payload.nativeAlarmId,
        plannedTriggerAt = payload.triggerAt.takeIf { it > 0L },
        isTest = payload.isTest,
        stage = stage,
        failureCategory = failureCategory,
        details = details,
    )

    @Synchronized
    fun appendSystemLifecycleEvent(
        context: Context,
        stage: String,
        failureCategory: String? = null,
        details: Map<String, Any?> = emptyMap(),
    ) = appendLifecycleEvent(
        context = context,
        alarmId = "system",
        scheduleId = null,
        nativeAlarmId = null,
        plannedTriggerAt = null,
        isTest = false,
        stage = stage,
        failureCategory = failureCategory,
        details = details,
    )

    private fun appendLifecycleEvent(
        context: Context,
        alarmId: String,
        scheduleId: String?,
        nativeAlarmId: Int?,
        plannedTriggerAt: Long?,
        isTest: Boolean,
        stage: String,
        failureCategory: String?,
        details: Map<String, Any?>,
    ) {
        val now = System.currentTimeMillis()
        val prefs = preferences(context)
        val existing = runCatching {
            JSONArray(prefs.getString(LIFECYCLE_EVENTS, "[]"))
        }.getOrDefault(JSONArray())
        val retained = mutableListOf<JSONObject>()
        val cutoff = now - LIFECYCLE_RETENTION_MILLIS
        for (index in 0 until existing.length()) {
            val item = existing.optJSONObject(index) ?: continue
            if (item.optLong("occurredAt") >= cutoff) retained += item
        }
        retained += JSONObject().apply {
            put("id", "native_${now}_${System.nanoTime()}_${nativeAlarmId ?: -1}")
            put("alarmId", alarmId)
            put("scheduleId", scheduleId ?: JSONObject.NULL)
            put("nativeAlarmId", nativeAlarmId ?: JSONObject.NULL)
            put("stage", stage)
            put("occurredAt", now)
            put("plannedTriggerAt", plannedTriggerAt ?: JSONObject.NULL)
            put("failureCategory", failureCategory ?: JSONObject.NULL)
            put("source", "android")
            put("isTest", isTest)
            put("details", JSONObject().apply {
                details.forEach { (key, value) ->
                    if (!key.contains("path", ignoreCase = true)) {
                        put(key, value ?: JSONObject.NULL)
                    }
                }
            })
        }
        val output = JSONArray()
        retained.takeLast(MAX_LIFECYCLE_EVENTS).forEach(output::put)
        prefs.edit().putString(LIFECYCLE_EVENTS, output.toString()).commit()
    }

    @Synchronized
    fun consumeLifecycleEvents(context: Context): List<Map<String, Any?>> {
        val prefs = preferences(context)
        val raw = prefs.getString(LIFECYCLE_EVENTS, "[]") ?: "[]"
        prefs.edit().putString(LIFECYCLE_EVENTS, "[]").commit()
        return runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val json = array.getJSONObject(index)
                    add(jsonObjectToMap(json))
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> = buildMap {
        json.keys().forEach { key ->
            val value = if (json.isNull(key)) null else json.get(key)
            put(
                key,
                if (value is JSONObject) {
                    buildMap<String, Any?> {
                        value.keys().forEach { nestedKey ->
                            put(
                                nestedKey,
                                if (value.isNull(nestedKey)) null else value.get(nestedKey),
                            )
                        }
                    }
                } else {
                    value
                },
            )
        }
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
