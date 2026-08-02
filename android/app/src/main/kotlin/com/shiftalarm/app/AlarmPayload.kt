package com.shiftalarm.app

import android.content.Intent
import org.json.JSONObject
import java.util.Calendar

data class AlarmPayload(
    val id: String,
    val scheduleId: String,
    val nativeAlarmId: Int,
    val triggerAt: Long,
    val triggerYear: Int,
    val triggerMonth: Int,
    val triggerDay: Int,
    val triggerHour: Int,
    val triggerMinute: Int,
    val reminderName: String,
    val shiftCode: String,
    val shiftName: String,
    val arrivalAt: Long?,
    val isTemporary: Boolean,
    val isCore: Boolean,
    val isTest: Boolean,
    val vibration: Boolean,
    val snoozeEnabled: Boolean,
    val snoozeMinutes: Int,
    val maxSnoozeCount: Int,
    val snoozeCount: Int,
    val maxRingingMinutes: Int,
    val soundId: String = "system",
    val soundPath: String? = null,
    val directBootSoundPath: String? = null,
    val soundChecksum: String? = null,
    val fadeIn: Boolean = true,
) {
    fun putInto(intent: Intent): Intent = intent.apply {
        putExtra(EXTRA_JSON, toJson().toString())
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("scheduleId", scheduleId)
        put("nativeAlarmId", nativeAlarmId)
        put("triggerAt", triggerAt)
        put("triggerYear", triggerYear)
        put("triggerMonth", triggerMonth)
        put("triggerDay", triggerDay)
        put("triggerHour", triggerHour)
        put("triggerMinute", triggerMinute)
        put("reminderName", reminderName)
        put("shiftCode", shiftCode)
        put("shiftName", shiftName)
        put("arrivalAt", arrivalAt ?: JSONObject.NULL)
        put("isTemporary", isTemporary)
        put("isCore", isCore)
        put("isTest", isTest)
        put("vibration", vibration)
        put("snoozeEnabled", snoozeEnabled)
        put("snoozeMinutes", snoozeMinutes)
        put("maxSnoozeCount", maxSnoozeCount)
        put("snoozeCount", snoozeCount)
        put("maxRingingMinutes", maxRingingMinutes)
        put("soundId", soundId)
        put("soundPath", soundPath ?: JSONObject.NULL)
        put("directBootSoundPath", directBootSoundPath ?: JSONObject.NULL)
        put("soundChecksum", soundChecksum ?: JSONObject.NULL)
        put("fadeIn", fadeIn)
    }

    fun withTrigger(trigger: Long, newSnoozeCount: Int = snoozeCount): AlarmPayload {
        val calendar = Calendar.getInstance().apply { timeInMillis = trigger }
        return copy(
            triggerAt = trigger,
            triggerYear = calendar.get(Calendar.YEAR),
            triggerMonth = calendar.get(Calendar.MONTH) + 1,
            triggerDay = calendar.get(Calendar.DAY_OF_MONTH),
            triggerHour = calendar.get(Calendar.HOUR_OF_DAY),
            triggerMinute = calendar.get(Calendar.MINUTE),
            snoozeCount = newSnoozeCount,
        )
    }

    fun withCurrentTimeZone(): AlarmPayload {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.YEAR, triggerYear)
            set(Calendar.MONTH, triggerMonth - 1)
            set(Calendar.DAY_OF_MONTH, triggerDay)
            set(Calendar.HOUR_OF_DAY, triggerHour)
            set(Calendar.MINUTE, triggerMinute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return copy(triggerAt = calendar.timeInMillis)
    }

    companion object {
        const val EXTRA_JSON = "alarm_payload_json"

        fun fromIntent(intent: Intent?): AlarmPayload? =
            intent?.getStringExtra(EXTRA_JSON)?.let { runCatching { fromJson(JSONObject(it)) }.getOrNull() }

        fun fromMap(map: Map<*, *>): AlarmPayload = fromJson(JSONObject(map))

        fun fromJson(json: JSONObject): AlarmPayload = AlarmPayload(
            id = json.optString("id"),
            scheduleId = json.optString("scheduleId"),
            nativeAlarmId = json.optInt("nativeAlarmId"),
            triggerAt = json.optLong("triggerAt"),
            triggerYear = json.optInt("triggerYear"),
            triggerMonth = json.optInt("triggerMonth"),
            triggerDay = json.optInt("triggerDay"),
            triggerHour = json.optInt("triggerHour"),
            triggerMinute = json.optInt("triggerMinute"),
            reminderName = json.optString("reminderName", "排班提醒"),
            shiftCode = json.optString("shiftCode"),
            shiftName = json.optString("shiftName"),
            arrivalAt = if (json.isNull("arrivalAt")) null else json.optLong("arrivalAt"),
            isTemporary = json.optBoolean("isTemporary"),
            isCore = json.optBoolean("isCore"),
            isTest = json.optBoolean("isTest"),
            vibration = json.optBoolean("vibration", true),
            snoozeEnabled = json.optBoolean("snoozeEnabled", true),
            snoozeMinutes = json.optInt("snoozeMinutes", 10),
            maxSnoozeCount = json.optInt("maxSnoozeCount", 3),
            snoozeCount = json.optInt("snoozeCount"),
            maxRingingMinutes = json.optInt("maxRingingMinutes", 15),
            soundId = json.optString("soundId", "system"),
            soundPath = if (json.isNull("soundPath")) null else json.optString("soundPath"),
            directBootSoundPath = if (json.isNull("directBootSoundPath")) null else json.optString("directBootSoundPath"),
            soundChecksum = if (json.isNull("soundChecksum")) null else json.optString("soundChecksum"),
            fadeIn = json.optBoolean("fadeIn", true),
        )
    }
}
