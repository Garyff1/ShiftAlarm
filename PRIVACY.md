# ShiftAlarm 隐私与本地数据说明

更新时间：2026-08-02
适用版本：`v1.0.0-beta.1`

本文依据当前仓库的 Android Manifest、Dart/Kotlin 源码和依赖清单编写。后续若加入网络、诊断导出、云同步或崩溃上报，必须同步更新本文。

## 当前网络能力

当前 Android Manifest **没有声明 `android.permission.INTERNET`**；当前依赖不包含 HTTP 客户端、遥测、广告或第三方崩溃上报 SDK，源码中也没有用户数据上传流程。因此本 Beta 构建不会把班表、音频或闹钟记录发送到 ShiftAlarm 服务器。GitHub Release 下载发生在浏览器/GitHub 客户端中，不是应用自身的网络行为。

## 本地保存的数据

- 班次模板、排班、调班记录、提醒和 AlarmRecord：应用私有 SQLite 数据库
- 主题、周起始日、默认铃声等设置：应用私有 SharedPreferences
- 用户导入音频：复制到应用私有 `files/alarm_sounds/`，正式响铃不依赖原外部文件
- 近期闹钟恢复信息和实际需要的铃声副本：Android 设备保护存储，用于 Direct Boot
- 原生闹钟事件与声音失败原因：应用私有设备保护 SharedPreferences

应用卸载通常会由 Android 清除上述应用私有数据。当前版本尚未提供完整数据导出和恢复功能。

## 音频文件处理

用户主动通过 Android 系统文件选择器选取 MP3、WAV、M4A、AAC 或 OGG。应用读取所选内容，检查文件大小、媒体轨道和实际解码，计算 SHA-256 后复制进内部目录。数据库会保存用户可见名称、内部安全文件名、来源 URI 字符串、格式、大小、时长和校验摘要。

应用不会把音频提交到本仓库、GitHub Issue 或网络服务。反馈 Bug 时请不要上传私人 MP3 或其他音频。

## Android 权限及用途

| 权限 | 用途 |
| --- | --- |
| `SCHEDULE_EXACT_ALARM` | 按用户排班时间登记精确系统闹钟 |
| `POST_NOTIFICATIONS` | 显示响铃前台通知及停止/贪睡操作 |
| `USE_FULL_SCREEN_INTENT` | 在系统允许时显示锁屏全屏响铃页 |
| `FOREGROUND_SERVICE` | 运行响铃前台服务 |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | 在前台服务中播放正式闹钟音频 |
| `RECEIVE_BOOT_COMPLETED` | 开机后恢复未来闹钟 |
| `WAKE_LOCK` | 响铃期间短暂保持 CPU/屏幕唤醒链路 |
| `VIBRATE` | 按提醒设置振动 |

应用还会打开系统精确闹钟、通知、全屏提醒、声音和电池优化设置页，由用户自行决定是否授权。

## 不应上传到 Bug 报告的内容

- 私人音频文件
- 公司完整班表或带姓名的排班截图
- 姓名、电话、地址或账号信息
- 手机 PIN、图案或密码
- 应用数据库、SharedPreferences 或 Direct Boot 文件
- keystore、签名密码、Token 或其他密钥

如果问题必须结合截图说明，请先裁剪或打码个人信息。

## 反馈与删除

当前版本没有 ShiftAlarm 云端账户或服务端数据。要删除本机数据，可在 Android 系统中清除应用存储或卸载应用；执行前请注意当前版本没有完整备份恢复功能。问题反馈请使用 GitHub 仓库的 Bug Report 模板。
