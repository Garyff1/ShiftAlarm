import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app_navigation.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/shift_template.dart';
import '../../shared/widgets/async_states.dart';
import '../alarms/alarm_controller.dart';
import '../alarms/alarm_records_page.dart';
import '../alarms/permission_center_page.dart';
import '../schedule/schedule_controller.dart';
import '../schedule/schedule_day_sheet.dart';
import '../shifts/shift_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String _dateText(DateTime date) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${date.year}年${date.month}月${date.day}日  ${weekdays[date.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final shifts = context.watch<ShiftController>();
    final schedules = context.watch<ScheduleController>();
    final alarms = context.watch<AlarmController>();
    final now = DateTime.now();
    return CustomScrollView(
      key: const PageStorageKey('home-page'),
      slivers: [
        SliverAppBar.large(
          title: const Text('早上好'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Center(
                child: Text(
                  _dateText(now),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              _ScheduleOverviewCard(
                eyebrow: '今天',
                schedule: schedules.todaySchedule,
                shift: schedules.shiftFor(schedules.todaySchedule),
                originalShift: schedules.originalShiftFor(
                  schedules.todaySchedule,
                ),
                onTap: () => showScheduleDayDetails(context, now),
              ),
              const SizedBox(height: 12),
              _ScheduleOverviewCard(
                eyebrow: '明天',
                schedule: schedules.tomorrowSchedule,
                shift: schedules.shiftFor(schedules.tomorrowSchedule),
                originalShift: schedules.originalShiftFor(
                  schedules.tomorrowSchedule,
                ),
                onTap: () => showScheduleDayDetails(
                  context,
                  now.add(const Duration(days: 1)),
                ),
              ),
              const SizedBox(height: 12),
              _AlarmStatusCard(
                controller: alarms,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => alarms.permissions.exactAlarm
                        ? const AlarmRecordsPage()
                        : const PermissionCenterPage(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '快捷操作',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  _QuickAction(
                    icon: Icons.today_rounded,
                    label: '安排今天',
                    onTap: () => showScheduleDayDetails(context, now),
                  ),
                  _QuickAction(
                    icon: Icons.change_circle_outlined,
                    label: '临时调班',
                    onTap: () =>
                        context.read<AppNavigationController>().select(1),
                  ),
                  _QuickAction(
                    icon: Icons.calendar_month_outlined,
                    label: '查看本月',
                    onTap: () =>
                        context.read<AppNavigationController>().select(1),
                  ),
                  _QuickAction(
                    icon: Icons.add_rounded,
                    label: '新增班次',
                    onTap: () =>
                        context.read<AppNavigationController>().select(2),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SectionCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '班次模板',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            shifts.items.isEmpty
                                ? '还没有班次，先创建一个常用班次吧'
                                : '已创建 ${shifts.items.length} 个班次模板',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () =>
                          context.read<AppNavigationController>().select(2),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('创建'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleOverviewCard extends StatelessWidget {
  const _ScheduleOverviewCard({
    required this.eyebrow,
    required this.schedule,
    required this.shift,
    required this.originalShift,
    required this.onTap,
  });
  final String eyebrow;
  final DailySchedule? schedule;
  final ShiftTemplate? shift;
  final ShiftTemplate? originalShift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = schedule == null
        ? '尚未安排班次'
        : shift == null
        ? '班次数据缺失'
        : '${shift!.code} · ${shift!.name}';
    final description = schedule == null
        ? '点击这里安排当天班次'
        : shift == null
        ? '请点击并重新选择班次'
        : '${shift!.type.label} · ${shift!.arrivalTime?.format() ?? '无需到岗'}${schedule!.isTemporaryChanged ? ' · 临时调班' : ''}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: shift == null
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Color(shift!.colorValue).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  schedule?.isTemporaryChanged == true
                      ? Icons.change_circle_outlined
                      : Icons.today_rounded,
                  color: shift == null ? null : Color(shift!.colorValue),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (schedule?.isTemporaryChanged == true)
                      Text(
                        '原排班：${originalShift == null ? '数据缺失' : '${originalShift!.code} · ${originalShift!.name}'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
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
}

class _AlarmStatusCard extends StatelessWidget {
  const _AlarmStatusCard({required this.controller, required this.onTap});
  final AlarmController controller;
  final VoidCallback onTap;

  String _time(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final next = controller.nextRegistered;
    final failed = controller.records
        .where((item) => item.failureReason != null)
        .firstOrNull;
    final (title, detail) = !controller.permissions.exactAlarm
        ? ('精确闹钟权限未开启', '点击进入权限中心，开启后将自动同步')
        : !controller.permissions.notifications
        ? ('通知权限未开启', '闹钟声音仍会尝试播放，但锁屏操作受限')
        : next != null
        ? (
            '${_time(next.triggerAt)} · ${next.shiftCode} ${next.reminderName}',
            '闹钟已开启',
          )
        : failed != null
        ? ('闹钟登记失败', failed.failureReason ?? '点击查看详情')
        : controller.isSyncing
        ? ('正在同步闹钟', '请稍候')
        : ('暂无未来系统闹钟', '安排未来工作班后将自动登记');
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.alarm_outlined),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '下一次系统闹钟',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
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
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}
