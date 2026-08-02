import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/widgets/async_states.dart';
import 'alarm_controller.dart';
import 'alarm_records_page.dart';

class PermissionCenterPage extends StatelessWidget {
  const PermissionCenterPage({super.key});

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限中心'),
        actions: [
          IconButton(
            tooltip: '刷新权限状态',
            onPressed: controller.refreshPermissions,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
                        controller.overallStatus,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('系统权限可能随时被撤销，应用每次回到前台都会重新检查。'),
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
                  title: '精确闹钟',
                  status: state.exactAlarm ? '已开启' : '未开启',
                  good: state.exactAlarm,
                  action: '去设置',
                  onTap: () => _explainExact(context),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.notifications_active_outlined,
                  title: '通知',
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
                  title: '锁屏全屏提醒',
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
                  title: '电池优化',
                  status: state.ignoringBatteryOptimizations ? '不受限制' : '可能受限',
                  good: state.ignoringBatteryOptimizations,
                  action: '查看说明',
                  onTap: controller.openBatterySettings,
                ),
              ],
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
                const Text('登记后可以锁屏或强制结束应用；测试记录不会混入正式排班统计。'),
                const SizedBox(height: 14),
                if (remaining == null)
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await controller.startTestAlarm();
                      if (!ok &&
                          context.mounted &&
                          !controller.permissions.exactAlarm) {
                        await _explainExact(context);
                      }
                    },
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('一分钟后测试'),
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
        ],
      ),
    );
  }
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
