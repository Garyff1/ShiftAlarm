import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_mode_theme.dart';
import '../../core/utils/alarm_time_calculator.dart';
import '../../core/utils/friendly_status.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/reminder_rule.dart';
import '../../data/models/shift_template.dart';
import '../alarms/alarm_controller.dart';
import '../alarms/permission_center_page.dart';
import '../schedule/schedule_controller.dart';
import 'simple_shift_selection_page.dart';

class SimpleHomePage extends StatefulWidget {
  const SimpleHomePage({super.key});

  @override
  State<SimpleHomePage> createState() => _SimpleHomePageState();
}

class _SimpleHomePageState extends State<SimpleHomePage>
    with WidgetsBindingObserver {
  Timer? _minuteTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      _startTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _minuteTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedules = context.watch<ScheduleController>();
    final alarms = context.watch<AlarmController>();
    final mode = AppModeTheme.of(context);
    final today = DateTime(_now.year, _now.month, _now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final warning = _warningFor(alarms);
    return CustomScrollView(
      key: const PageStorageKey('simple-home-page'),
      slivers: [
        const SliverAppBar.large(title: Text('今天')),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            mode.pagePadding,
            0,
            mode.pagePadding,
            28,
          ),
          sliver: SliverList.list(
            children: [
              if (warning != null) ...[
                _EmergencyCard(message: warning, alarms: alarms),
                SizedBox(height: mode.sectionSpacing / 2),
              ],
              _SimpleScheduleCard(
                key: const Key('simple-today-card'),
                dateLabel: '今天',
                date: today,
                schedule: schedules.scheduleFor(today),
                shift: schedules.shiftFor(schedules.scheduleFor(today)),
                buttonLabel: schedules.scheduleFor(today) == null
                    ? '安排今天班次'
                    : '修改今天班次',
              ),
              SizedBox(height: mode.sectionSpacing / 2),
              _NextAlarmCard(alarms: alarms, now: _now),
              SizedBox(height: mode.sectionSpacing / 2),
              _SimpleScheduleCard(
                key: const Key('simple-tomorrow-card'),
                dateLabel: '明天',
                date: tomorrow,
                schedule: schedules.scheduleFor(tomorrow),
                shift: schedules.shiftFor(schedules.scheduleFor(tomorrow)),
                buttonLabel: schedules.scheduleFor(tomorrow) == null
                    ? '安排明天班次'
                    : '修改明天班次',
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _warningFor(AlarmController alarms) {
    if (!alarms.permissions.exactAlarm) return '明天的闹钟可能无法准时响，需要允许闹钟准时响。';
    if (!alarms.permissions.notifications) return '闹钟画面可能无法正常显示，需要允许显示闹钟提醒。';
    if (!alarms.permissions.fullScreenIntent) {
      return '锁屏时可能看不到闹钟画面，需要检查全屏提醒设置。';
    }
    if (alarms.records.any((item) => item.failureReason != null)) {
      return '有闹钟设置失败，需要查看并处理。';
    }
    return null;
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.message, required this.alarms});
  final String message;
  final AlarmController alarms;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '有一项设置需要处理。$message',
    child: Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: EdgeInsets.all(AppModeTheme.of(context).cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, semanticLabel: '需要处理'),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '有一项设置需要处理',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(message),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PermissionCenterPage(simpleMode: true),
                ),
              ),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('查看并处理'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SimpleScheduleCard extends StatelessWidget {
  const _SimpleScheduleCard({
    super.key,
    required this.dateLabel,
    required this.date,
    required this.schedule,
    required this.shift,
    required this.buttonLabel,
  });

  final String dateLabel;
  final DateTime date;
  final DailySchedule? schedule;
  final ShiftTemplate? shift;
  final String buttonLabel;

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final mode = AppModeTheme.of(context);
    final item = shift;
    final reminders = item == null
        ? const <MapEntry<ReminderRule, DateTime>>[]
        : AlarmTimeCalculator.calculateAndSort(
            scheduleDate: date,
            arrivalTime: item.arrivalTime,
            arrivalDayOffset: item.arrivalDayOffset,
            rules: item.reminderRules,
          );
    final isRest = item != null && item.arrivalTime == null;
    final title = item == null
        ? '$dateLabel还没有安排'
        : isRest
        ? '$dateLabel${item.name}'
        : '$dateLabel上${item.name}';
    final semantic = item == null
        ? '$dateLabel未排班，双击设置班次'
        : '${item.code}${item.name}，${item.arrivalTime?.format() ?? '无需到岗'}，${reminders.length}条提醒，${schedule?.isTemporaryChanged == true ? '临时调班' : '已安排'}';
    return Semantics(
      container: true,
      label: semantic,
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(mode.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (schedule?.isTemporaryChanged == true)
                    Chip(
                      avatar: const Icon(Icons.change_circle_rounded, size: 18),
                      label: const Text('临时调班'),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                ],
              ),
              if (item == null) ...[
                const SizedBox(height: 8),
                const Text('选择一个班次后，闹钟会自动设置。'),
              ] else if (isRest) ...[
                const SizedBox(height: 10),
                const Text('当天没有工作闹钟'),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  '${item.arrivalTime!.format()} 到公司',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final reminder in reminders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.alarm_rounded, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_time(reminder.value)} ${reminder.key.name}',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SimpleShiftSelectionPage(date: date),
                  ),
                ),
                icon: const Icon(Icons.edit_calendar_rounded),
                label: Text(buttonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextAlarmCard extends StatelessWidget {
  const _NextAlarmCard({required this.alarms, required this.now});
  final AlarmController alarms;
  final DateTime now;

  String _friendlyTime(DateTime value) {
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    final prefix = date == today
        ? '今天'
        : date == today.add(const Duration(days: 1))
        ? '明天'
        : '${value.month}月${value.day}日';
    return '$prefix ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  String _countdown(DateTime trigger) {
    final remaining = trigger.difference(now);
    if (remaining <= const Duration(minutes: 1)) return '即将响铃';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours == 0) return '$minutes分钟';
    if (minutes == 0) return '$hours小时';
    return '$hours小时 $minutes分钟';
  }

  @override
  Widget build(BuildContext context) {
    final next = alarms.nextRegistered;
    final exactAlarmReady = alarms.permissions.exactAlarm;
    final title = !exactAlarmReady
        ? '下一次闹钟还没有生效'
        : next == null
        ? '暂时没有未来闹钟'
        : _friendlyTime(next.triggerAt);
    final status = !exactAlarmReady
        ? '需要开启闹钟权限'
        : next == null
        ? '安排工作班后会自动设置'
        : FriendlyStatus.alarm(next.status);
    return Semantics(
      container: true,
      label: next == null
          ? '$title，$status'
          : '$title${next.reminderName}，$status，距离响铃${_countdown(next.triggerAt)}',
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(AppModeTheme.of(context).cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.alarm_rounded, semanticLabel: '下一次闹钟'),
                  const SizedBox(width: 10),
                  Text(
                    '下一次闹钟',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                key: const Key('simple-next-alarm-time'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 6),
                Text(next.reminderName),
                const SizedBox(height: 10),
                Text('距离下一次闹钟：${_countdown(next.triggerAt)}'),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    exactAlarmReady
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: exactAlarmReady
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(status)),
                ],
              ),
              if (!exactAlarmReady) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const PermissionCenterPage(simpleMode: true),
                    ),
                  ),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('现在去开启'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
