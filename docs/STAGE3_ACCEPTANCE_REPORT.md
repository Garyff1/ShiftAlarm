# ShiftAlarm V1.0 第三阶段补充验收报告

验收日期：2026-08-02
验收环境：Android API 36 模拟器（`IdeaBase_Debug_API36`）
结论：**通过，可以进入第四阶段。**

本轮已走通完整真实链路：排班生成闹钟、权限恢复、应用进程被结束后锁屏响铃、贪睡三次、停止、临时调班替换系统闹钟、重启恢复、首次解锁前 Direct Boot 恢复，以及时区切换重算。

## 28 项交付说明

1. **项目路径**：仓库根目录。
2. **版本与数据库**：应用 `1.0.0+3`、`versionCode=3`、SQLite Schema `v3`、包名 `com.shiftalarm.app`、`minSdk=24`、`targetSdk=36`。v2 实机数据原位升级成功，保留 3 个班次、9 条排班和原有调班日志；最终 `PRAGMA integrity_check=ok`。
3. **新增 Android 权限**：`SCHEDULE_EXACT_ALARM`、`POST_NOTIFICATIONS`、`USE_FULL_SCREEN_INTENT`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`RECEIVE_BOOT_COMPLETED`、`WAKE_LOCK`、`VIBRATE`。
4. **精确闹钟权限选择**：仅声明 `SCHEDULE_EXACT_ALARM`，便于内测阶段真实验证用户关闭、撤销和重新授权后的恢复流程；没有同时声明 `USE_EXACT_ALARM`。Android 14 新安装应用通常不会预授予该特殊权限，应用每次同步前都会检查 `canScheduleExactAlarms()`。参考：[Android 精确闹钟说明](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)。
5. **Kotlin 原生组件**：`NativeAlarmScheduler`、`AlarmReceiver`、`AlarmActionReceiver`、`AlarmRingingService`、`AlarmRingingActivity`、`BootAndTimeChangeReceiver`、`NativeAlarmStore`、`AlarmNotifications`、`AlarmPayload`、`AlarmRules`。
6. **Flutter/Android 通信**：使用 MethodChannel `com.shiftalarm.app/alarm`，Flutter 负责排班计算、SQLite 状态与幂等比较，Kotlin 负责系统权限、登记/取消、响铃执行、Direct Boot 快照和原生事件回传。
7. **AlarmManager API**：每条提醒均为一次性闹钟；起床类使用 `setAlarmClock()`，出发/即将到岗使用 `setExactAndAllowWhileIdle(RTC_WAKEUP)`。这符合系统对精确用户闹钟的推荐用途。参考：[Schedule alarms](https://developer.android.com/develop/background-work/services/alarms)、[AlarmManager API](https://developer.android.com/reference/android/app/AlarmManager)。
8. **PendingIntent 唯一 ID**：SQLite 持久化递增 `nativeAlarmId`，正式闹钟从 10000 起；测试闹钟固定使用 9001。广播 action 同时包含 ID，停止/贪睡 action requestCode 使用 `nativeAlarmId * 10 + offset`，不依赖 Dart 临时 `hashCode`。
9. **同步与取消逻辑**：`AlarmPlanBuilder` 生成目标集合，`ScheduleAlarmSyncCoordinator` 以 `scheduleId + reminderRuleId` 稳定键比较目标与已有记录；顺序执行取消作废、替换变更、新增缺失、保留未变，重复同步不会增加系统闹钟。
10. **全屏提醒**：原生 `AlarmRingingActivity` 设置 `directBootAware`、`showWhenLocked`、`turnScreenOn`，通知使用 `CATEGORY_ALARM`、公开锁屏可见和 full-screen intent。全屏能力受限时仍保留高优先级悬浮通知、声音、停止和贪睡。参考：[时间敏感通知](https://developer.android.com/develop/ui/views/notifications/time-sensitive)、[NotificationManager](https://developer.android.com/reference/android/app/NotificationManager)。
11. **前台响铃服务**：`AlarmRingingService` 使用 `mediaPlayback` 前台服务类型，播放系统默认闹钟音频、振动、音频焦点和专用 partial WakeLock，15 分钟后自动释放并记录未响应原因。参考：[Android 14 前台服务类型要求](https://developer.android.com/about/versions/14/changes/fgs-types-required)。
12. **停止与贪睡**：全屏页支持长按停止，通知支持停止/贪睡；操作后释放音频、振动、通知、服务和 WakeLock。贪睡继续使用同一稳定系统 ID，按班次规则登记下一次单次精确闹钟；达到 3/3 后贪睡按钮消失，超过到岗时间前会二次确认。
13. **Direct Boot 与重启恢复**：最小闹钟快照保存到 device-protected storage，相关 Activity、Service、Receiver 均为 `directBootAware`，监听 `LOCKED_BOOT_COMPLETED` 和 `BOOT_COMPLETED`。严格测试中，模拟器设置临时 PIN 后重启，在 `userUnlocked=false` 时恢复 25 条闹钟（24 条正式 + 1 条测试），测试闹钟随后仍在首次解锁前点亮锁屏并打开原生响铃页；测试 PIN 已清除。参考：[Direct Boot 支持](https://developer.android.com/privacy-and-security/direct-boot)。
14. **时间与时区处理**：监听 `TIME_SET`、`TIMEZONE_CHANGED`、`DATE_CHANGED`。GMT 切换到 Asia/Tokyo 后，24 个唯一系统 ID 保持不变，8 月 3 日 06:00 的 epoch 精确前移 `32,400,000 ms`；切回 GMT 后恢复原值，无重复、无立即误响。
15. **权限中心**：真实显示精确闹钟、通知、全屏提醒、闹钟音量和电池优化状态；关闭权限时显示“闹钟尚未生效”，恢复全部权限后显示“所有权限正常”，并自动把 24 条 `permissionBlocked` 记录重新登记。
16. **一分钟测试闹钟**：支持权限检查、60 秒倒计时、取消、锁屏/杀进程测试、停止、1 分钟贪睡、最多 3 次以及结果回显；测试事件不写入正式排班统计。
17. **自动化测试总数**：125 项，其中 Flutter/Dart/Widget/数据库迁移 113 项，Kotlin/JUnit 12 项，超过任务单要求的至少 90 项。
18. **`flutter analyze`**：通过，`No issues found`。
19. **`flutter test`**：113/113 通过，`All tests passed`。
20. **原生测试**：`AlarmPayloadTest` 3 项、`AlarmRulesTest` 9 项，共 12/12 通过；`compileDebugKotlin` 同时通过。
21. **APK**：Debug `build/app/outputs/flutter-apk/app-debug.apk`，153,106,820 字节，SHA-256 `079342867D12C3849BBC84F6A1FCDC3E59CC076FB2F27E391981AACF597C915F`；Release `build/app/outputs/flutter-apk/app-release.apk`，53,357,730 字节，SHA-256 `7631417710F36D224C9B5A6426308A65C87B308BC5DA45094E1C8DBA3104AAC4`。两包均通过 APK Signature Scheme v2 校验。
22. **`dumpsys alarm`**：最终系统活动队列为 24 条、24 个唯一 ID；调班前的 10000–10002 已从活动队列取消，新 B1 闹钟为 10024–10026；数据库最终为 24 条 `registered`、3 条历史 `cancelled`。
23. **六组人工验收**：基础闹钟通过；贪睡通过；调班同步通过；权限撤销/恢复通过；手机重启且不打开应用通过；时区变化重算通过。基础测试还验证了 `am kill` 后进程不存在、锁屏 Dozing、到点重新拉起进程和前台服务。
24. **日志与资源**：干净启动日志无 FATAL EXCEPTION、应用 ANR、`ForegroundServiceStartNotAllowedException` 或应用相关 `SecurityException`；停止后无残留 `AlarmRingingService` 和 `com.shiftalarm.app:ringing:*` WakeLock。
25. **截图证据**：保存在 `build/acceptance`，包括权限关闭/恢复、倒计时、锁屏响铃、三次贪睡上限、调班结果、重启后通知、首次解锁前 Direct Boot 响铃和最终首页，共 13 张关键截图及对应 UI XML。
26. **已知问题**：当前 Release APK 为内测包，仍使用 Android Debug 证书，正式发布前必须配置独立 release keystore；Android 的全屏展示策略最终仍会受具体品牌系统、通知频道用户设置和省电策略影响，必须再用目标真机覆盖测试；历史测试数据中的 `Morning/Evening` 因增量升级原则被保留。
27. **与任务单差异及本阶段补充**：闹钟记录页已提供正式记录列表和重新同步，但任务单中“单条详情/暂停/恢复”属于建议项，本轮未扩展为完整管理页；自定义 MP3 严格留到第四阶段。额外完成了应用 Logo 的普通、圆形和 adaptive icon 资源替换，未混入闹钟业务逻辑。
28. **下一阶段建议**：进入第四阶段，优先完成 MP3 导入与内部复制、铃声库、班次/单条提醒铃声绑定、音频解码失败兜底、正式签名与升级策略；同时安排至少一台 Android 14/15/16 真机做锁屏、重启、厂商省电和权限撤销回归。

## 最终判定

第三阶段完成标志中的核心链路已全部通过：

> 安排班次 → 自动登记系统闹钟 → 结束应用进程 → 锁屏准时响铃 → 贪睡后再次响铃 → 停止 → 临时调班 → 旧闹钟取消 → 新闹钟登记 → 重启后及首次解锁前恢复。
