package com.shiftalarm.app

import android.app.Activity
import android.app.AlertDialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextClock
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AlarmRingingActivity : Activity() {
    private var payload: AlarmPayload? = null
    private val finishReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = finishAndRemoveTask()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        payload = AlarmPayload.fromIntent(intent)
        val value = payload ?: run { finish(); return }
        setContentView(content(value))
        val filter = IntentFilter(AlarmRingingService.ACTION_FINISHED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(finishReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(finishReceiver, filter)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        AlarmPayload.fromIntent(intent)?.let {
            payload = it
            setContentView(content(it))
        }
    }

    private fun content(payload: AlarmPayload): LinearLayout {
        fun text(value: String, size: Float, color: Int = Color.WHITE) = TextView(this).apply {
            this.text = value
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(Color.rgb(14, 17, 24))
        }
        root.addView(TextClock(this).apply {
            format24Hour = "HH:mm"
            format12Hour = "hh:mm"
            textSize = 64f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }, params(match = true, height = 130))
        root.addView(text(payload.reminderName, 30f), params(match = true, height = 90))
        root.addView(
            text("今天是 ${payload.shiftCode} ${payload.shiftName}${if (payload.isTemporary) " · 临时调班" else ""}", 21f, Color.LTGRAY),
            params(match = true, height = 70),
        )
        if (payload.arrivalAt != null) {
            val arrival = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(payload.arrivalAt))
            val minutes = ((payload.arrivalAt - System.currentTimeMillis()) / 60_000L).coerceAtLeast(0)
            root.addView(text("$arrival 到岗 · 还有 $minutes 分钟", 19f, Color.LTGRAY), params(true, 70))
        }
        if (AlarmPolicy.canSnooze(payload.snoozeEnabled, payload.snoozeCount, payload.maxSnoozeCount)) {
            root.addView(Button(this).apply {
                text = "贪睡 ${payload.snoozeMinutes} 分钟（${payload.snoozeCount}/${payload.maxSnoozeCount}）"
                setOnClickListener { confirmOrSnooze(payload) }
            }, params(true, 130))
        }
        root.addView(Button(this).apply {
            text = "长按停止"
            setOnLongClickListener {
                sendAction(AlarmRingingService.ACTION_STOP, payload)
                finishAndRemoveTask()
                true
            }
        }, params(true, 150))
        return root
    }

    private fun confirmOrSnooze(payload: AlarmPayload) {
        val next = AlarmPolicy.snoozeTriggerAt(System.currentTimeMillis(), payload.snoozeMinutes)
        if (payload.arrivalAt != null && next > payload.arrivalAt) {
            AlertDialog.Builder(this)
                .setTitle("贪睡后将晚于到岗时间")
                .setMessage("是否仍要继续贪睡？")
                .setNegativeButton("停止闹钟") { _, _ ->
                    sendAction(AlarmRingingService.ACTION_STOP, payload)
                    finishAndRemoveTask()
                }
                .setPositiveButton("继续贪睡") { _, _ -> snooze(payload) }
                .show()
        } else {
            snooze(payload)
        }
    }

    private fun snooze(payload: AlarmPayload) {
        sendAction(AlarmRingingService.ACTION_SNOOZE, payload)
        finishAndRemoveTask()
    }

    private fun sendAction(action: String, payload: AlarmPayload) {
        val intent = payload.putInto(Intent(this, AlarmRingingService::class.java)).apply { this.action = action }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }

    private fun params(match: Boolean, height: Int) = LinearLayout.LayoutParams(
        if (match) ViewGroup.LayoutParams.MATCH_PARENT else ViewGroup.LayoutParams.WRAP_CONTENT,
        height,
    ).apply { setMargins(0, 12, 0, 12) }

    override fun onDestroy() {
        runCatching { unregisterReceiver(finishReceiver) }
        super.onDestroy()
    }
}
