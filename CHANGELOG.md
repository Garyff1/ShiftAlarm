# Changelog

本项目遵循语义化版本标签；Android `versionCode` 通过 `pubspec.yaml` 中的 `+N` 管理。

## [1.0.0-beta.1] - 2026-08-02

首个 GitHub 内部测试预发布版本。

### Added

- 班次模板、提醒规则和五页主导航
- 月历排班、批量操作、临时调班、恢复、交换与变更记录
- Android 精确闹钟、锁屏 Activity、前台响铃服务、停止与贪睡
- 重启/时间/时区/权限恢复及 Direct Boot 快照
- 自定义音频导入、SHA-256 校验、铃声库、试听和安全删除
- 应用/班次/提醒三级配置与系统铃声最终兜底
- 30 秒音量渐强和 15 分钟最大响铃时间
- 1 分钟普通链路与 2 分钟重启链路测试入口

### Verified

- Flutter/Dart/Widget 162 项通过
- Kotlin/JUnit 23 项通过
- API 36 七条人工验收流程通过
- 用户未解锁的 Direct Boot 自定义铃声流程通过

### Security and distribution

- Release APK 当前使用 Debug certificate，仅限内部测试
- 源码仓库不包含 APK、keystore、私人音频、运行数据库或本地配置

[1.0.0-beta.1]: https://github.com/Garyff1/ShiftAlarm/releases/tag/v1.0.0-beta.1
