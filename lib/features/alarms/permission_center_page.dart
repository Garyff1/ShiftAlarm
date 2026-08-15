import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_mode_theme.dart';
import '../../services/alarm/native_alarm_scheduler.dart';
import '../../shared/widgets/async_states.dart';
import 'alarm_controller.dart';
import 'alarm_diagnostics_page.dart';
import 'alarm_records_page.dart';

class PermissionCenterPage extends StatelessWidget {
  const PermissionCenterPage({super.key, this.simpleMode = false});

  final bool simpleMode;

  Future<void> _startTest(
    BuildContext context,
    AlarmController controller,
    AlarmTestMode mode,
  ) async {
    final ok = await controller.startTestAlarm(
      delaySeconds: mode.delaySeconds,
      mode: mode,
    );
    if (!ok && context.mounted && !controller.permissions.exactAlarm) {
      await _explainExact(context);
    }
  }

  Future<void> _explainExact(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开启精确闹钟权限'),
        content: const Text(
          'ShiftAlarm 需要在应用被结束或设备休眠时，仍按排班时间准时触发闹钟。下一步将打开系统“闹钟和提醒”设置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不开启'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去开启'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AlarmController>().openExactAlarmSettings();
    }
  }

  Future<void> _explainNotifications(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('允许闹钟通知'),
        content: const Text(
          '通知用于显示正在响铃状态、锁屏提醒，以及停止和贪睡按钮。拒绝通知不会让应用崩溃，但锁屏操作会受限。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final controller = context.read<AlarmController>();
    final granted = await controller.requestNotificationPermission();
    if (!granted && context.mounted) {
      await controller.openNotificationSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AlarmController>();
    final state = controller.permissions;
    final remaining = controller.testRemainingSeconds;
    final simple = simpleMode;
    final overall = simple
        ? controller.hasHealthIssue
              ? '有一项需要处理'
              : '闹钟设置正常'
        : controller.healthHeadline;
    return Scaffold(
      appBar: AppBar(
        title: const Text('闹钟健康中心'),
        actions: [
          IconButton(
            tooltip: '一键检查',
            onPressed: controller.runHealthCheck,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppModeTheme.of(context).pagePadding,
          8,
          AppModeTheme.of(context).pagePadding,
          32,
        ),
        children: [
          SectionCard(
            child: Row(
              children: [
                Icon(
                  state.ready
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  size: 38,
                  color: state.ready
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overall,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(controller.healthDescription),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _PermissionTile(
                  icon: Icons.alarm_on_rounded,
                  title: simple ? '允许闹钟准时响' : '精确闹钟',
                  status: state.exactAlarm ? '已开启' : '未开启',
                  good: state.exactAlarm,
                  action: simple ? '现在去开启' : '去设置',
                  onTap: () => _explainExact(context),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.notifications_active_outlined,
                  title: simple ? '允许显示闹钟提醒' : '通知',
                  status: state.notifications ? '已开启' : '未开启',
                  good: state.notifications,
                  action: state.notifications ? '设置' : '申请',
                  onTap: () => state.notifications
                      ? controller.openNotificationSettings()
                      : _explainNotifications(context),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.fullscreen_rounded,
                  title: simple ? '允许锁屏时显示闹钟画面' : '锁屏全屏提醒',
                  status: state.fullScreenIntent ? '已开启' : '受限',
                  good: state.fullScreenIntent,
                  action: '去设置',
                  onTap: controller.openFullScreenIntentSettings,
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.volume_up_outlined,
                  title: '闹钟音量',
                  status: state.volumeMuted
                      ? '静音'
                      : state.volumeLow
                      ? '过低'
                      : '正常 · ${state.alarmVolume}/${state.maxAlarmVolume}',
                  good: !state.volumeMuted && !state.volumeLow,
                  action: '声音设置',
                  onTap: controller.openAlarmVolumeSettings,
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.battery_saver_outlined,
                  title: simple ? '防止手机限制闹钟运行' : '电池优化',
                  status: state.ignoringBatteryOptimizations ? '不受限制' : '可能受限',
                  good: state.ignoringBatteryOptimizations,
                  action: '查看说明',
                  onTap: controller.openBatterySettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _HealthTile(
                  icon: Icons.sync_rounded,
                  title: '最近同步',
                  value: controller.lastSyncAt == null
                      ? '尚未完成同步'
                      : controller.lastSyncResult?.successful == true
                      ? '最近一次同步成功'
                      : '最近一次同步需要处理',
                  good: controller.lastSyncResult?.successful != false,
                ),
                const Divider(height: 1),
                _HealthTile(
                  icon: Icons.notifications_active_rounded,
                  title: '最近一次响铃结果',
                  value:
                      controller.latestCompletedDiagnostic?.headline ??
                      '还没有响铃结果',
                  good:
                      controller.latestCompletedDiagnostic?.state.name !=
                      'failed',
                ),
                const Divider(height: 1),
                _HealthTile(
                  icon: Icons.music_note_rounded,
                  title: '自定义铃声状态',
                  value: controller.latestCustomSoundFailure == null
                      ? '未检测到铃声不可用或降级'
                      : '最近一次自定义铃声不可用，已降级到系统铃声',
                  good: controller.latestCustomSoundFailure == null,
                ),
                const Divider(height: 1),
                _HealthTile(
                  icon: Icons.restart_alt_rounded,
                  title: '最近一次重启恢复',
                  value: controller.latestDirectBootEvent == null
                      ? '暂无恢复记录'
                      : '已记录 Direct Boot 恢复',
                  good:
                      controller.latestDirectBootEvent?.failureCategory == null,
                ),
                const Divider(height: 1),
                _HealthTile(
                  icon: Icons.public_rounded,
                  title: '最近一次时间或时区重算',
                  value: controller.latestTimezoneEvent == null
                      ? '暂无变化记录'
                      : controller.latestTimezoneEvent!.stage.label,
                  good: controller.latestTimezoneEvent?.failureCategory == null,
                ),
                const Divider(height: 1),
                _HealthTile(
                  icon: Icons.pan_tool_alt_rounded,
                  title: '强行停止检测',
                  value: controller.latestForceStopEvent == null
                      ? '本机未检测到强行停止记录'
                      : controller.forceStopRecoveredThisLaunch
                      ? '检测到后已恢复未来闹钟'
                      : '曾检测到强行停止',
                  good:
                      controller.latestForceStopEvent == null ||
                      controller.forceStopRecoveredThisLaunch,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: controller.isSyncing ? null : controller.runHealthCheck,
            icon: controller.isSyncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_rounded),
            label: Text(controller.isSyncing ? '正在检查…' : '一键检查'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AlarmDiagnosticsPage(),
              ),
            ),
            icon: const Icon(Icons.account_tree_rounded),
            label: const Text('查看闹钟诊断'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.isExportingDiagnostics
                ? null
                : () async {
                    final ok = await controller.exportDiagnosticReport();
                    if (context.mounted && !ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('诊断报告导出失败，请重试')),
                      );
                    }
                  },
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(
              controller.isExportingDiagnostics ? '正在生成…' : '导出脱敏诊断报告',
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '闹钟自检',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  remaining == null
                      ? controller.testStatus
                      : '${controller.testStatus} · ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.activeTestMode?.instruction ??
                      '每次只运行一种测试；测试记录不会混入正式排班统计。',
                ),
                const SizedBox(height: 14),
                if (remaining == null)
                  Column(
                    children: AlarmTestMode.values
                        .map(
                          (mode) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _AlarmTestModeCard(
                              mode: mode,
                              onTap: () =>
                                  _startTest(context, controller, mode),
                            ),
                          ),
                        )
                        .toList(),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: controller.cancelTestAlarm,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('取消测试闹钟'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AlarmRecordsPage()),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('查看闹钟记录'),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '不建议在手机系统设置中对 ShiftAlarm 使用“强行停止”，这可能让系统移除已安排的闹钟。普通划掉后台或系统回收进程不会被视为关闭闹钟。',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmTestModeCard extends StatelessWidget {
  const _AlarmTestModeCard({required this.mode, required this.onTap});

  final AlarmTestMode mode;
  final VoidCallback onTap;

  IconData get icon => switch (mode) {
    AlarmTestMode.standard => Icons.timer_outlined,
    AlarmTestMode.lockScreen => Icons.screen_lock_portrait_outlined,
    AlarmTestMode.background => Icons.layers_clear_outlined,
    AlarmTestMode.reboot => Icons.restart_alt_rounded,
  };

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${mode.label}，${mode.instruction}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode == AlarmTestMode.standard ? '一分钟后测试' : mode.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(mode.instruction),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.good,
  });
  final IconData icon;
  final String title;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(value),
    trailing: Icon(
      good ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
      color: good ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
      semanticLabel: good ? '正常' : '需要处理',
    ),
  );
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.good,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String status;
  final bool good;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(
      status,
      style: TextStyle(
        color: good
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
        fontWeight: FontWeight.w700,
      ),
    ),
    trailing: TextButton(onPressed: onTap, child: Text(action)),
  );
}
