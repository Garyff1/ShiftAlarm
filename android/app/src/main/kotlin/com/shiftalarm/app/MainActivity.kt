package com.shiftalarm.app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var soundPickerResult: MethodChannel.Result? = null
    private val soundExecutor = Executors.newSingleThreadExecutor()
    private val previewPlayer by lazy { SoundPreviewPlayer(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmNotifications.createChannels(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionState" -> result.success(permissionState())
                "scheduleAlarm" -> {
                    val payload = AlarmPayload.fromMap(call.arguments as Map<*, *>)
                    val scheduled = NativeAlarmScheduler.schedule(this, payload)
                    result.success(mapOf("success" to scheduled.isSuccess, "error" to scheduled.exceptionOrNull()?.message))
                }
                "cancelAlarm" -> {
                    val id = call.argument<Int>("nativeAlarmId") ?: 0
                    NativeAlarmScheduler.cancel(this, id)
                    result.success(null)
                }
                "replaceSnapshots" -> {
                    val payloads = (call.arguments as? List<*>)
                        ?.filterIsInstance<Map<*, *>>()
                        ?.map(AlarmPayload::fromMap)
                        .orEmpty()
                    NativeAlarmStore.replaceSnapshots(this, payloads)
                    result.success(null)
                }
                "consumeEvents" -> result.success(NativeAlarmStore.consumeEvents(this))
                "consumeSoundEvents" -> result.success(NativeAlarmStore.consumeSoundEvents(this))
                "pickSound" -> openSoundPicker(result)
                "commitSoundImport" -> runSoundTask(result) {
                    mapOf("internalPath" to SoundFileManager.commitImport(this, call.argument<String>("tempPath") ?: ""))
                }
                "discardSoundImport" -> result.success(
                    SoundFileManager.discardImport(this, call.argument<String>("tempPath") ?: ""),
                )
                "verifySound" -> runSoundTask(result) {
                    SoundFileManager.verifyInternal(
                        this,
                        call.argument<String>("path") ?: "",
                        call.argument<String>("checksum"),
                    )
                }
                "deleteSoundFile" -> result.success(
                    SoundFileManager.deleteInternal(this, call.argument<String>("path") ?: ""),
                )
                "cleanupSoundTemps" -> result.success(SoundFileManager.cleanupTemps(this))
                "cleanupOrphanSounds" -> result.success(
                    SoundFileManager.cleanupOrphans(
                        this,
                        call.argument<List<String>>("retainedPaths").orEmpty(),
                    ),
                )
                "playSoundPreview" -> runCatching {
                    previewPlayer.play(
                        call.argument<String>("path"),
                        call.argument<Boolean>("system") == true,
                    )
                }.fold(result::success) { result.error("preview_failed", SoundFileManager.errorCode(it), null) }
                "pauseSoundPreview" -> {
                    previewPlayer.pause()
                    result.success(previewPlayer.state())
                }
                "resumeSoundPreview" -> runCatching { previewPlayer.resume() }
                    .fold(result::success) { result.error("preview_failed", SoundFileManager.errorCode(it), null) }
                "stopSoundPreview" -> {
                    previewPlayer.stop()
                    result.success(null)
                }
                "getSoundPreviewState" -> result.success(previewPlayer.state())
                "openExactAlarmSettings" -> {
                    openSettingsIntent(
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")),
                    )
                    result.success(null)
                }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "openNotificationSettings" -> {
                    openSettingsIntent(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                    result.success(null)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        openSettingsIntent(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "openAlarmVolumeSettings" -> {
                    openSettingsIntent(Intent(Settings.ACTION_SOUND_SETTINGS))
                    result.success(null)
                }
                "openBatterySettings" -> {
                    openSettingsIntent(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                "scheduleTestAlarm" -> {
                    val seconds = call.argument<Int>("delaySeconds")?.coerceAtLeast(1) ?: 60
                    val trigger = System.currentTimeMillis() + seconds * 1000L
                    val calendar = Calendar.getInstance().apply { timeInMillis = trigger }
                    val payload = AlarmPayload(
                        id = "test_alarm",
                        scheduleId = "",
                        nativeAlarmId = NativeAlarmScheduler.TEST_ALARM_ID,
                        triggerAt = trigger,
                        triggerYear = calendar.get(Calendar.YEAR),
                        triggerMonth = calendar.get(Calendar.MONTH) + 1,
                        triggerDay = calendar.get(Calendar.DAY_OF_MONTH),
                        triggerHour = calendar.get(Calendar.HOUR_OF_DAY),
                        triggerMinute = calendar.get(Calendar.MINUTE),
                        reminderName = "一分钟测试闹钟",
                        shiftCode = "TEST",
                        shiftName = "系统闹钟自检",
                        arrivalAt = null,
                        isTemporary = false,
                        isCore = true,
                        isTest = true,
                        vibration = true,
                        snoozeEnabled = true,
                        snoozeMinutes = 1,
                        maxSnoozeCount = 3,
                        snoozeCount = 0,
                        maxRingingMinutes = 15,
                        soundId = call.argument<String>("soundId") ?: "system",
                        soundPath = call.argument<String>("soundPath"),
                        directBootSoundPath = null,
                        soundChecksum = call.argument<String>("soundChecksum"),
                        fadeIn = call.argument<Boolean>("fadeIn") ?: true,
                    )
                    val scheduled = NativeAlarmScheduler.schedule(this, payload)
                    if (scheduled.isSuccess) NativeAlarmStore.upsertSnapshot(this, payload)
                    result.success(mapOf("success" to scheduled.isSuccess, "error" to scheduled.exceptionOrNull()?.message))
                }
                "cancelTestAlarm" -> {
                    NativeAlarmScheduler.cancel(this, NativeAlarmScheduler.TEST_ALARM_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun permissionState(): Map<String, Any> {
        val notificationManager = getSystemService(NotificationManager::class.java)
        val audioManager = getSystemService(AudioManager::class.java)
        val powerManager = getSystemService(PowerManager::class.java)
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED &&
                notificationManager.areNotificationsEnabled()
        } else {
            notificationManager.areNotificationsEnabled()
        }
        val fullScreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            notificationManager.canUseFullScreenIntent()
        } else true
        return mapOf(
            "exactAlarm" to NativeAlarmScheduler.canScheduleExact(this),
            "notifications" to notifications,
            "fullScreenIntent" to fullScreen,
            "ignoringBatteryOptimizations" to powerManager.isIgnoringBatteryOptimizations(packageName),
            "alarmVolume" to audioManager.getStreamVolume(AudioManager.STREAM_ALARM),
            "maxAlarmVolume" to audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM),
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error("request_in_progress", "通知权限申请正在进行", null)
            return
        }
        notificationPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    private fun openSoundPicker(result: MethodChannel.Result) {
        if (soundPickerResult != null) {
            result.error("picker_in_progress", "系统文件选择器已经打开", null)
            return
        }
        soundPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        runCatching { startActivityForResult(intent, SOUND_PICK_REQUEST) }
            .onFailure {
                soundPickerResult = null
                result.error("picker_unavailable", it.message, null)
            }
    }

    @Deprecated("Storage Access Framework result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SOUND_PICK_REQUEST) return
        val result = soundPickerResult ?: return
        soundPickerResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        runCatching {
            val takeFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, takeFlags)
        }
        soundExecutor.execute {
            runCatching { SoundFileManager.importToTemp(this, uri) }
                .fold(
                    onSuccess = { value -> runOnUiThread { result.success(value) } },
                    onFailure = { error -> runOnUiThread {
                        result.error("sound_import_failed", SoundFileManager.errorCode(error), null)
                    } },
                )
        }
    }

    private fun runSoundTask(result: MethodChannel.Result, task: () -> Any?) {
        soundExecutor.execute {
            runCatching(task).fold(
                onSuccess = { value -> runOnUiThread { result.success(value) } },
                onFailure = { error -> runOnUiThread {
                    result.error("sound_file_failed", SoundFileManager.errorCode(error), null)
                } },
            )
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_REQUEST) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            notificationPermissionResult?.success(granted)
            notificationPermissionResult = null
        }
    }

    private fun openSettingsIntent(intent: Intent) {
        runCatching { startActivity(intent) }
            .recoverCatching { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))) }
    }

    override fun onPause() {
        previewPlayer.stop()
        super.onPause()
    }

    override fun onDestroy() {
        previewPlayer.stop()
        soundExecutor.shutdownNow()
        soundPickerResult?.success(null)
        soundPickerResult = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.shiftalarm.app/alarm"
        private const val NOTIFICATION_REQUEST = 3103
        private const val SOUND_PICK_REQUEST = 3104
    }
}
