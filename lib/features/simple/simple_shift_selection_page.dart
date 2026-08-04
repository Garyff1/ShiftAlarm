import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_mode_theme.dart';
import '../../core/utils/alarm_time_calculator.dart';
import '../../data/models/shift_template.dart';
import '../schedule/schedule_controller.dart';
import '../schedule/shift_change_confirmation.dart';
import '../shifts/shift_editor_page.dart';

class SimpleShiftSelectionPage extends StatelessWidget {
  const SimpleShiftSelectionPage({super.key, required this.date});

  final DateTime date;

  Future<void> _select(BuildContext context, ShiftTemplate shift) async {
    final result = await confirmAndSetShift(
      context,
      date: date,
      newShift: shift,
      reason: '简易模式修改班次',
    );
    if (result != null && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final schedules = context.watch<ScheduleController>();
    final templates = schedules.enabledTemplates;
    final current = schedules.scheduleFor(date);
    final mode = AppModeTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回上一页',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('请选择 ${date.month}月${date.day}日 的班次'),
      ),
      body: templates.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(mode.pagePadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      '还没有班次规则',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
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
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                mode.pagePadding,
                12,
                mode.pagePadding,
                28,
              ),
              itemCount: templates.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final shift = templates[index];
                return _ShiftChoiceCard(
                  date: date,
                  shift: shift,
                  selected: current?.shiftTemplateId == shift.id,
                  enabled: !schedules.isOperating,
                  onTap: () => _select(context, shift),
                );
              },
            ),
    );
  }
}

class _ShiftChoiceCard extends StatelessWidget {
  const _ShiftChoiceCard({
    required this.date,
    required this.shift,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DateTime date;
  final ShiftTemplate shift;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final reminders = AlarmTimeCalculator.calculateAndSort(
      scheduleDate: date,
      arrivalTime: shift.arrivalTime,
      arrivalDayOffset: shift.arrivalDayOffset,
      rules: shift.reminderRules,
    );
    final firstReminder = reminders.firstOrNull;
    final semantic =
        '${shift.code}${shift.name}，${shift.arrivalTime?.format() ?? '无需到岗'}，'
        '${reminders.length}条提醒${selected ? '，当前班次' : '，双击选择'}';
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semantic,
      child: Card(
        child: InkWell(
          key: Key('simple-shift-${shift.id}'),
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: EdgeInsets.all(AppModeTheme.of(context).cardPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color(shift.colorValue).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: selected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          )
                        : null,
                  ),
                  child: Text(
                    shift.code,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              shift.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (selected) const Chip(label: Text('当前')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${shift.arrivalTime?.format() ?? '无需'} 到公司'),
                      const SizedBox(height: 4),
                      Text(
                        firstReminder == null
                            ? '当天没有工作闹钟'
                            : '${_time(firstReminder.value)} ${firstReminder.key.name} · 共 ${reminders.length} 条提醒',
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
