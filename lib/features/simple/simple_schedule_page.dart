import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_mode_theme.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/shift_template.dart';
import '../schedule/schedule_controller.dart';
import '../schedule/schedule_page.dart';
import '../shifts/shift_editor_page.dart';
import 'simple_shift_selection_page.dart';

class SimpleSchedulePage extends StatelessWidget {
  const SimpleSchedulePage({super.key});

  static const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

  String _dateLabel(DateTime date, DateTime today) {
    final offset = date.difference(today).inDays;
    if (offset == 0) return '今天';
    if (offset == 1) return '明天';
    if (offset == 2) return '后天';
    return _weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final schedules = context.watch<ScheduleController>();
    final mode = AppModeTheme.of(context);
    final clock = DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final dates = List.generate(7, (index) => today.add(Duration(days: index)));
    return CustomScrollView(
      key: const PageStorageKey('simple-schedule-page'),
      slivers: [
        const SliverAppBar.large(title: Text('排班')),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            mode.pagePadding,
            0,
            mode.pagePadding,
            28,
          ),
          sliver: SliverList.list(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const Key('open-full-calendar-button'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: SafeArea(bottom: false, child: SchedulePage()),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: const Text('查看整月排班'),
                ),
              ),
              SizedBox(height: mode.sectionSpacing),
              if (schedules.enabledTemplates.isEmpty) ...[
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(mode.cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '还没有班次规则',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text('先建立工作、休息或请假班次，再安排日期。'),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ShiftEditorPage(),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('新建第一个班次'),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                for (final date in dates) ...[
                  _SevenDayCard(
                    date: date,
                    dateLabel: _dateLabel(date, today),
                    schedule: schedules.scheduleFor(date),
                    shift: schedules.shiftFor(schedules.scheduleFor(date)),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SevenDayCard extends StatelessWidget {
  const _SevenDayCard({
    required this.date,
    required this.dateLabel,
    required this.schedule,
    required this.shift,
  });

  final DateTime date;
  final String dateLabel;
  final DailySchedule? schedule;
  final ShiftTemplate? shift;

  @override
  Widget build(BuildContext context) {
    final item = shift;
    final semantic = item == null
        ? '${date.month}月${date.day}日，$dateLabel，未排班，双击设置班次'
        : '${date.month}月${date.day}日，$dateLabel，${item.code}${item.name}，${item.arrivalTime?.format() ?? '无需到岗'}，${schedule?.isTemporaryChanged == true ? '临时调班' : '正常排班'}，双击查看详情';
    return Semantics(
      button: true,
      label: semantic,
      child: Card(
        child: InkWell(
          key: Key('simple-date-${DailySchedule.dateKeyOf(date)}'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SimpleShiftSelectionPage(date: date),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(AppModeTheme.of(context).cardPadding),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text('${date.month}月${date.day}日'),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item == null ? '未排班' : '${item.code} ${item.name}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item == null
                            ? '点击设置班次'
                            : '${item.arrivalTime?.format() ?? '无需'} 到公司',
                      ),
                      if (schedule?.isTemporaryChanged == true)
                        Row(
                          children: [
                            Icon(
                              Icons.change_circle_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                            const SizedBox(width: 5),
                            const Text('临时调班'),
                          ],
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
