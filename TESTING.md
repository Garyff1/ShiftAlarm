# ShiftAlarm 测试说明

适用版本：`v1.0.0-beta.1`

## 发布基线

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| Flutter/Dart/Widget | 162/162 passed |
| Kotlin/JUnit | 23/23 passed |
| 自动化总计 | 185/185 passed |
| Android API 36 人工流程 | 7/7 passed |
| Debug APK | 构建成功 |
| Release APK | 构建、覆盖安装成功 |

第三、第四阶段的详细验收证据分别见 `docs/STAGE3_ACCEPTANCE_REPORT.md` 和 `docs/STAGE4_ACCEPTANCE_REPORT.md`。

## 本地自动化命令

```text
flutter clean
flutter pub get
flutter analyze
flutter test --reporter expanded

cd android
./gradlew :app:testDebugUnitTest
cd ..

flutter build apk --debug
flutter build apk --release
```

Windows 可使用 `gradlew.bat`。若项目路径包含非 ASCII 字符导致 Release AOT 路径编码错误，可将同一源码复制到临时 ASCII 目录构建；不要修改包名、版本或签名配置。

## API 36 已通过的人工流程

1. 导入两段 MP3，读取格式/时长/大小，切换试听并重启应用
2. 班次默认铃声、单条提醒覆盖及 24 条未来闹钟重新同步
3. 回到桌面并结束应用进程后，锁屏到时播放自定义铃声
4. 贪睡后以同一 soundId 和同一内部音源再次响铃
5. 主文件与 Direct Boot 副本故障时自动使用系统默认声音
6. 设置临时锁屏凭据、重启并保持 `RUNNING_LOCKED` 时从设备保护副本响铃
7. 删除被引用铃声时显示使用位置，事务替换后清理主文件和 Direct Boot 副本

## 真机 Beta 测试重点

- 覆盖安装前先记录旧版本和签名来源，不要在签名不一致时直接卸载
- 分别记录精确闹钟、通知、全屏提醒、电池优化和厂商自启动状态
- 结束普通应用进程与系统“强制停止”必须区分；后者会撤销系统闹钟
- 至少验证一次锁屏、一次贪睡、一次重启未解锁和一次时间/时区变化
- 自定义铃声测试只使用无隐私的样本音频
- 测试后确认没有持续前台服务、声音、振动或 WakeLock

## CI 行为

CI 固定使用 Flutter 3.41.8、Dart 3.11.5 对应 SDK 与 JDK 21，执行静态分析、Flutter 测试、Kotlin/JUnit 和 Debug APK 编译。CI 不读取签名密钥、不构建发布用 Release APK，也不自动创建 GitHub Release。
