import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_mode_theme.dart';
import '../../core/utils/id_generator.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/shift_template.dart';
import '../../shared/widgets/async_states.dart';
import '../settings/app_controller.dart';
import '../shifts/shift_controller.dart';
import 'schedule_change_log_sheet.dart';
import 'schedule_controller.dart';
import 'schedule_day_sheet.dart';
import 'shift_picker_sheet.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  Future<ShiftTemplate?> _quickCreateSpecialShift(
    BuildContext context,
    ShiftType type,
  ) async {
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('还没有${type.label}班次'),
        content: Text(
          '是否快速创建一个${type == ShiftType.rest ? 'OFF 休息' : 'LEAVE 请假'}班次，并用于本次批量排班？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('快速创建'),
          ),
        ],
      ),
    );
    if (create != true || !context.mounted) return null;
    final shifts = context.read<ShiftController>();
    final baseCode = type == ShiftType.rest ? 'OFF' : 'LEAVE';
    var code = baseCode;
    var suffix = 2;
    while (shifts.items.any((item) => item.code.toUpperCase() == code)) {
      code = '$baseCode$suffix';
      suffix++;
    }
    final now = DateTime.now();
    final shift = ShiftTemplate(
      id: IdGenerator.create('shift'),
      code: code,
      name: type == ShiftType.rest ? '休息' : '请假',
      type: type,
      colorValue: type == ShiftType.rest ? 0xFF56615A : 0xFFA04A62,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await shifts.save(shift);
      if (!context.mounted) return null;
      await context.read<ScheduleController>().refresh(showLoading: false);
      return shift;
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
      return null;
    }
  }

  Future<void> _pickMonth(BuildContext context) async {
    final controller = context.read<ScheduleController>();
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      helpText: '选择月份（日期仅用于定位月份）',
    );
    if (picked != null) await controller.selectMonth(picked);
  }

  Future<void> _applyBatch(BuildContext context, {ShiftType? filter}) async {
    final controller = context.read<ScheduleController>();
    final matching = filter == null
        ? controller.enabledTemplates
        : controller.enabledTemplates.where((item) => item.type == filter);
    ShiftTemplate? shift;
    if (filter != null && matching.isEmpty) {
      shift = await _quickCreateSpecialShift(context, filter);
    } else {
      shift = await showShiftPicker(
        context,
        shifts: controller.enabledTemplates,
        initialFilter: filter,
      );
    }
    if (shift == null || !context.mounted) return;
    final existingCount = controller.selectedDateKeys
        .where((key) => controller.schedules.containsKey(key))
        .length;
    var overwrite = true;
    if (existingCount > 0) {
      final decision = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认批量排班'),
          content: Text(
            '已选择 ${controller.selectedDateKeys.length} 天，其中 $existingCount 天已有排班。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'skip'),
              child: const Text('只设置未排班日期'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'overwrite'),
              child: const Text('覆盖全部'),
            ),
          ],
        ),
      );
      if (decision == null) return;
      overwrite = decision == 'overwrite';
    }
    try {
      final result = await controller.applyBatch(
        shift,
        overwriteExisting: overwrite,
      );
      if (context.mounted && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已为 ${result.savedCount} 个日期设置 ${shift.code} ${shift.name}${result.skippedCount == 0 ? '' : '，跳过 ${result.skippedCount} 天'}',
            ),
          ),
        );
      }
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    }
  }

  Future<void> _clearBatch(BuildContext context) async {
    final controller = context.read<ScheduleController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所选日期排班？'),
        content: Text('将清除 ${controller.selectedDateKeys.length} 个所选日期中的已有排班。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.clearBatch();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('批量清除完成')));
      }
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ScheduleController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          controller.batchMode
              ? '已选择 ${controller.selectedDateKeys.length} 天'
              : '排班',
        ),
        leading: controller.batchMode
            ? IconButton(
                onPressed: controller.clearSelection,
                icon: const Icon(Icons.close_rounded),
                tooltip: '退出批量模式',
              )
            : null,
        actions: controller.batchMode
            ? null
            : [
                TextButton(
                  onPressed: controller.goToToday,
                  child: const Text('今天'),
                ),
                IconButton(
                  onPressed: () =>
                      showScheduleChangeLogs(context, controller.changeLogs),
                  icon: const Icon(Icons.history_rounded),
                  tooltip: '调班记录',
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'batch') controller.enterBatch(DateTime.now());
                    if (value == 'history') {
                      showScheduleChangeLogs(context, controller.changeLogs);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'batch',
                      child: ListTile(
                        leading: Icon(Icons.library_add_check_outlined),
                        title: Text('批量排班'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'history',
                      child: ListTile(
                        leading: Icon(Icons.history_rounded),
                        title: Text('调班记录'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: controller.isLoading
          ? const LoadingState(message: '正在加载本月排班…')
          : controller.errorMessage != null
          ? ErrorState(
              message: controller.errorMessage!,
              onRetry: controller.refresh,
            )
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                key: const PageStorageKey('schedule-calendar'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  _MonthHeader(
                    month: controller.selectedMonth,
                    onPrevious: () => controller.changeMonth(-1),
                    onNext: () => controller.changeMonth(1),
                    onPick: () => _pickMonth(context),
                  ),
                  const SizedBox(height: 12),
                  _CalendarGrid(controller: controller),
                  const SizedBox(height: 14),
                  _MonthSummary(controller: controller),
                ],
              ),
            ),
      bottomNavigationBar: controller.batchMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: controller.selectedDateKeys.isEmpty
                            ? null
                            : () => _applyBatch(context),
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('设置班次'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () =>
                          _applyBatch(context, filter: ShiftType.rest),
                      icon: const Icon(Icons.weekend_outlined),
                      tooltip: '标记休息',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () =>
                          _applyBatch(context, filter: ShiftType.leave),
                      icon: const Icon(Icons.personal_injury_outlined),
                      tooltip: '标记请假',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _clearBatch(context),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: '清除排班',
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => SectionCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: '上个月',
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '${month.year}年 ${month.month}月',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: '下个月',
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({required this.controller});
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final weekStart = context.watch<AppController>().settings.weekStartDay;
    final mode = AppModeTheme.of(context);
    const mondayLabels = ['一', '二', '三', '四', '五', '六', '日'];
    final labels = weekStart == 7
        ? ['日', ...mondayLabels.take(6)]
        : mondayLabels;
    final first = DateTime(
      controller.selectedMonth.year,
      controller.selectedMonth.month,
      1,
    );
    final offset = weekStart == 7 ? first.weekday % 7 : first.weekday - 1;
    final start = first.subtract(Duration(days: offset));
    final dates = [for (var i = 0; i < 42; i++) start.add(Duration(days: i))];
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      child: Column(
        children: [
          Row(
            children: labels
                .map(
                  (label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: mode.largeText ? 0.58 : 0.76,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: dates.length,
            itemBuilder: (context, index) =>
                _CalendarCell(date: dates[index], controller: controller),
          ),
        ],
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({required this.date, required this.controller});
  final DateTime date;
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final isCurrentMonth =
        date.year == controller.selectedMonth.year &&
        date.month == controller.selectedMonth.month;
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isPast = date.isBefore(DateTime(today.year, today.month, today.day));
    final schedule = isCurrentMonth ? controller.scheduleFor(date) : null;
    final shift = controller.shiftFor(schedule);
    final selected = controller.selectedDateKeys.contains(
      DailySchedule.dateKeyOf(date),
    );
    final color = shift == null
        ? Theme.of(context).colorScheme.outline
        : Color(shift.colorValue);
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final semanticLabel = shift == null
        ? '${date.month}月${date.day}日，${weekdays[date.weekday - 1]}，未排班'
        : '${date.month}月${date.day}日，${weekdays[date.weekday - 1]}，${shift.code}${shift.name}${schedule?.isTemporaryChanged == true ? '，临时调班' : ''}';
    return Semantics(
      container: true,
      button: isCurrentMonth,
      selected: selected,
      label: semanticLabel,
      hint: isCurrentMonth
          ? controller.batchMode
                ? '双击选择或取消选择日期'
                : shift == null
                ? '双击设置班次'
                : '双击查看详情'
          : '不在当前月份',
      child: Opacity(
        opacity: isCurrentMonth ? (isPast ? 0.78 : 1) : 0.35,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('calendar-${DailySchedule.dateKeyOf(date)}'),
            onTap: () {
              if (!isCurrentMonth) return;
              if (controller.batchMode) {
                controller.toggleDate(date);
              } else {
                showScheduleDayDetails(context, date);
              }
            },
            onLongPress: isCurrentMonth
                ? () => controller.enterBatch(date)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : shift == null
                    ? null
                    : color.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.22
                            : 0.13,
                      ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: schedule?.isTemporaryChanged == true
                      ? Colors.orange
                      : isToday
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: schedule?.isTemporaryChanged == true || isToday
                      ? 1.6
                      : 1,
                ),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontWeight: isToday
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: isToday
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (shift != null)
                        Text(
                          shift.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                height: 1.05,
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                        )
                      else if (schedule != null)
                        Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      const SizedBox(height: 2),
                    ],
                  ),
                  if (schedule?.isTemporaryChanged == true)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '调',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (selected)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(Icons.check_circle_rounded, size: 16),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.controller});
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    var work = 0;
    var rest = 0;
    var leave = 0;
    var changed = 0;
    for (final schedule in controller.schedules.values) {
      final type = controller.shiftFor(schedule)?.type;
      if (type == ShiftType.work) work++;
      if (type == ShiftType.rest) rest++;
      if (type == ShiftType.leave) leave++;
      if (schedule.isTemporaryChanged) changed++;
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本月概览',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatChip(label: '工作', value: work),
              _StatChip(label: '休息', value: rest),
              _StatChip(label: '请假', value: leave),
              _StatChip(label: '临时调班', value: changed, color: Colors.orange),
            ],
          ),
          if (controller.schedules.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('本月暂无排班，点击日期开始安排，长按日期可进入批量模式。'),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.color});
  final String label;
  final int value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Chip(
    avatar: CircleAvatar(
      backgroundColor: color ?? Theme.of(context).colorScheme.primary,
      child: Text(
        '$value',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    ),
    label: Text(label),
  );
}
