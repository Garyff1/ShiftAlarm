# ShiftAlarm V1.0 第四阶段开发与验收报告

验收日期：2026-08-02
阶段结论：**正式通过**

完整主链路已经通过：导入 MP3 → 复制到应用内部目录 → 分配到班次与单条提醒 → 登记系统闹钟 → 结束应用进程 → 锁屏播放自定义铃声 → 贪睡后继续同一铃声 → 停止并释放资源 → 删除外部原文件后仍正常播放 → 重启未解锁时从 Direct Boot 副本播放。

## Codex 完成后汇报（28 项）

1. **项目路径**
   仓库根目录。Windows 本地若遇到非 ASCII 路径工具链问题，可在等价的 ASCII 临时路径中构建。

2. **应用和数据库版本**
   应用 `1.0.0+4`（设备显示 `versionName=1.0.0`、`versionCode=4`），SQLite Schema `v4`，包名 `com.shiftalarm.app`，`targetSdk=36`、`minSdk=24`。

3. **新增依赖**
   未增加第三方 Dart 或 Android 播放依赖。文件选择、媒体探测、预览和正式响铃均使用 Android 平台 API，降低本阶段对既有闹钟链路的侵入。

4. **文件选择实现**
   通过 Android `ACTION_OPEN_DOCUMENT` 打开系统 DocumentsUI，并限制为音频类型。用户选中的内容先复制到临时文件，后续正式播放不依赖外部 URI。实现符合 Android 的[共享文档访问建议](https://developer.android.com/training/data-storage/shared/documents-files)。

5. **内部文件目录**
   主文件位于应用凭据保护存储的 `files/alarm_sounds/`；临时目录为其下 `temp/`；Direct Boot 副本位于设备保护存储的 `files/alarm_sounds/`。磁盘名采用 `sound_<时间戳>_<随机值>.<扩展名>`，不直接使用用户文件名。

6. **支持格式**
   MP3、WAV、M4A、AAC、OGG。不是只按扩展名判断，同时使用 `MediaExtractor`、`MediaMetadataRetriever` 和 `MediaPlayer` 做媒体轨道、元数据及实际解码校验。

7. **文件大小限制**
   单文件最大 50 MB；空文件、超限文件、非音频、损坏音频、不可读文件和不支持编码会被拒绝。长音频允许导入，正式响铃仍受 15 分钟最大响铃时间控制。

8. **音频校验方式**
   导入时计算 SHA-256，记录文件大小、格式、MIME、时长和摘要；摘要用于重复导入识别以及主文件、Direct Boot 副本的完整性校验。验收期间发现并补强了 Direct Boot 既有副本复用前的摘要校验。

9. **铃声优先级**
   `单条提醒 → 班次默认 → 应用默认 → Android 系统默认`。显式选择“系统默认”会终止继续继承；记录缺失、文件不可用、路径或摘要异常时继续向下解析。

10. **试听实现**
    独立 `SoundPreviewPlayer` 使用 `MediaPlayer`、`USAGE_MEDIA` 和瞬时 Audio Focus，支持播放、暂停、恢复、进度和总时长。同一时刻只播放一个预览，切换铃声、离开页面、应用进后台或删除时会停止；不会创建 AlarmRecord 或启动正式响铃服务。

11. **正式响铃播放器实现**
    `AlarmRingingService` 内的 `AlarmAudioPlayer` 使用 Android `MediaPlayer` 循环播放内部文件，设置 `USAGE_ALARM`/`CONTENT_TYPE_SONIFICATION`，沿用第三阶段 AlarmManager、Receiver、锁屏 Activity、前台服务、停止、贪睡及 15 分钟超时链路。系统铃声失败时还有 `ToneGenerator` 最终兜底。

12. **Audio Focus 处理**
    试听请求媒体用途的瞬时焦点；正式响铃请求闹钟用途的瞬时焦点。焦点暂失会暂停，duck 时降低播放器增益，重新获得焦点后恢复；停止后释放焦点。人工验收的 `dumpsys audio` 明确显示 `GAIN_TRANSIENT`、`USAGE_ALARM`、SDK 36。实现遵循 Android 的[音频焦点指南](https://developer.android.com/media/optimize/audio-focus)及[高 targetSdk 后台焦点限制](https://developer.android.com/about/versions/15/behavior-changes-15)。

13. **音量渐强**
    正式接入既有渐强字段，默认从 8% 播放器增益开始，在 30 秒内线性升至 100%，每 500 ms 更新。关闭渐强时直接使用完整增益；每次贪睡再响会重新开始；不会永久修改系统闹钟音量。

14. **Direct Boot 铃声方案**
    仅为未来快照实际引用的自定义铃声创建设备保护副本；快照携带 soundId、主路径、设备保护路径、SHA-256、振动、贪睡和渐强参数。`LOCKED_BOOT_COMPLETED` 后从设备保护存储恢复 AlarmManager。失效副本会在解锁状态从主文件重建，不再使用的副本会清理。方案符合 Android 的[Direct Boot 存储模型](https://developer.android.com/privacy-and-security/direct-boot)。

15. **删除与替换事务**
    被引用铃声不能直接删除。事务先更新班次、单条提醒、未来 AlarmRecord 和默认标志，再重新同步 AlarmManager/Direct Boot，最后删除主文件和数据库记录。替换失败会整体回滚；文件删除失败不破坏引用，并留待启动清理。验收把 A 的 1 条提醒、8 条未来闹钟及应用默认安全替换成 B。

16. **异常兜底**
    正式播放依次验证主文件和 Direct Boot 副本；均不可用或解码失败时记录 `sound_event`，立即启动系统默认闹钟声音，振动、停止和贪睡继续可用，服务不崩溃。故障注入日志为 `custom_fallback ... reason=custom_sound_missing`，随后为 `system_started requested=<custom id>`。

17. **数据迁移**
    v3→v4 为增量迁移：建立独立 `alarm_sounds` 表及 checksum/default/available 索引，为 `alarm_records` 增加 `sound_id` 与索引；班次默认铃声和 ReminderRule 铃声 ID 保存在兼容 JSON 载荷中。v1/v2/v3 升级路径、既有班次、排班、闹钟记录、设置及调班日志均保留。手机从第三阶段数据直接升级成功。

18. **测试总数**
    共 **185 项**：Flutter/Dart/Widget 162 项 + Kotlin/JUnit 23 项，超过任务单要求的至少 160 项。

19. **Flutter 测试结果**
    `flutter analyze`：`No issues found`。`flutter test`：**162/162 passed**。覆盖模型、优先级、迁移、导入/重复、试听、重命名、默认值、引用替换、同步协调、页面状态及原有排班回归。

20. **Kotlin 测试结果**
    `:app:testDebugUnitTest`：**23/23 passed**。包含 AlarmPayload 6、闹钟规则 9、渐强 4、Direct Boot 文件摘要校验 4；失败、错误均为 0。

21. **Debug 和 Release APK**
    Debug：`build/app/outputs/flutter-apk/app-debug.apk`，168,351,280 bytes，SHA-256 `41BE9F26EA864CA917A41220D5151B422846229C52941585FC1117CFD42D1009`。
    Release：`build/app/outputs/flutter-apk/app-release.apk`，59,082,040 bytes，SHA-256 `71497CB615941401A5389E8A4EC29BF99FC45B80E73E7B5B8D3A973619313064`。
    两个构建命令均成功；Debug 已在 API 36 设备上覆盖安装并保留历史数据。

22. **人工验收结果**
    七条流程均通过：导入/试听；班次默认 B；单条“起床”覆盖 A；结束进程和锁屏正式播放；贪睡同一 A；主文件与 Direct Boot 文件故障时系统兜底；PIN 重启未解锁播放；引用保护删除并替换 B。最终设备存在 24 条 registered AlarmRecord 和 24 个唯一正式 AlarmManager ID。

23. **自定义铃声响铃截图或录屏说明**
    `build/stage4_directboot_ring.png`：锁屏全屏响铃页；对应日志明确记录自定义 A 从设备保护路径启动。
    `build/stage4_final_sounds.png`：最终铃声库，B 为应用默认并显示 26 个使用位置。
    `build/stage4_delete_protection.png`：删除引用保护对话框。
    `build/stage4_first_ring_log.txt` 和 `build/stage4_fallback_log.txt` 保存关键播放与兜底日志。

24. **Direct Boot 验证结果**
    设置临时测试锁屏凭据后登记两分钟自定义测试闹钟并重启；设备状态为 `RUNNING_LOCKED`，即 `userUnlocked=false`。闹钟到时前台服务正常启动，日志确认使用设备保护存储副本且 `directBoot=true`，Audio Focus 为 `USAGE_ALARM`；通知停止后服务、播放器、振动和 WakeLock 均释放。随后解锁并清除了临时凭据。

25. **干净日志**
    最终 crash buffer 为空；无 FATAL EXCEPTION/ANR；`AlarmRingingService` 无残留；无当前 ShiftAlarm Audio Focus 或活动播放器；`Wake Locks: size=0`；`alarm_sounds/temp` 为空；无 A 的悬空数据库记录或文件，24 条未来记录全部指向可用 B。

26. **已知问题**
    Release 当前使用项目既有 debug keystore，仅适合本地测试/分发，正式上架前必须配置专用 release keystore。Windows Flutter AOT 对原项目中文路径有编码问题，因此 Release 在等价的 ASCII 临时副本中构建后复制回正式目录；源码及产物内容不受影响。

27. **与任务单差异**
    任务单 P0 全部完成。P1 中完成音量渐强和同名安全唯一磁盘名；未实现裁剪起点、搜索、最近使用、分类等明确标为建议项的功能。播放器选用平台 `MediaPlayer` 而非可选的 Media3。人工“强制结束”使用 `am kill` 模拟进程死亡；没有使用 Android `force-stop`，因为后者会由系统撤销包的 AlarmManager 登记，语义不同于普通进程终止。删除保护流程选择 B 作为替代而非系统默认，以额外验证自定义到自定义的事务替换。

28. **下一阶段建议**
    第五阶段优先做发布准备与真实设备矩阵：配置 release 签名和 CI 产物校验；覆盖不同厂商的省电/自启动策略；增加真机来电、蓝牙/耳机切换、极短音频和低存储测试；再考虑铃声搜索、裁剪、最近使用、播放时长限制以及可选的导出/恢复策略。

## 验收中追加修复

- 新增铃声卡片“1 分钟测试闹钟”和“2 分钟重启测试闹钟”，直接走正式原生链路。
- 为正式播放器增加可审计的 custom/system/fallback 日志。
- Direct Boot 副本由“非空检查”提升为 SHA-256 复核，并增加损坏后自动重建。
- 修复故障恢复后使用位置计数短暂显示旧值的问题。
- 默认铃声被替换删除时，在同一数据库事务转移 `isDefault` 标志。
- 删除保护提示补充“当前是应用默认铃声”的说明。
