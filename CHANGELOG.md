# Changelog

本项目遵循语义化版本标签；Android `versionCode` 通过 `pubspec.yaml` 中的 `+N` 管理。

## [Unreleased] - Beta002 candidate

当前开发版本为 `1.0.0+5`。在真机发布验收与 CI 全部通过前，不创建 `v1.0.0-beta.2` 标签。

### Added

- 标准、大字、简易三种可持久化界面模式和首次启动选择页
- 简易模式“今天 / 排班 / 更多”三页结构及七天排班列表
- 下一次闹钟分钟级倒计时、通俗化闹钟状态和权限异常提示
- 调班前后班次、提醒时间及新旧闹钟数量确认
- 高对比度、减少动态效果、触觉反馈和基础 TalkBack 语义
- 模式、主题、状态映射和无障碍页面回归测试
- 全平台应用图标更新为 2026-08-04 新版 ShiftAlarm Logo

### Changed

- 大字模式统一从主题层放大字号、间距、按钮、图标触控区和底部导航
- 标准首页今日卡片支持展开完整提醒、铃声和闹钟状态
- 日历、班次、铃声、权限和主要图标按钮补充中文语义或工具提示
- 旧版本设置缺少界面模式字段时保持标准模式，不强制重新展示引导页

### Verified locally

- `flutter analyze`：No issues found
- Flutter/Dart/Widget：230/230 passed
- Kotlin/JUnit：23/23 passed
- Debug、Release APK 均构建并通过签名校验
- API 36 模拟器完成首次选择、七天排班、前后预览、三模式持久化、最大字体和系统闹钟数量回归

### Pending before beta.2 tag

- 真机 TalkBack、权限关闭/恢复、锁屏自定义铃声、贪睡和资源释放
- API 24–35 运行时兼容性及主要厂商后台策略矩阵
- 正式 Release keystore；当前候选 Release 仍使用 Debug certificate

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
