import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app_navigation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/alarm_time_calculator.dart';
import '../../core/utils/id_generator.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/shift_template.dart';
import '../shifts/shift_controller.dart';
import 'schedule_controller.dart';
import 'shift_change_confirmation.dart';
import 'shift_picker_sheet.dart';

Future<void> showScheduleDayDetails(BuildContext context, DateTime date) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _ScheduleDaySheet(date: DailySchedule.normalizeDate(date)),
    );

class _ScheduleDaySheet extends StatefulWidget {
  const _ScheduleDaySheet({required this.date});
  final DateTime date;

  @override
  State<_ScheduleDaySheet> createState() => _ScheduleDaySheetState();
}

class _ScheduleDaySheetState extends State<_ScheduleDaySheet> {
  static const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

  String get dateText =>
      '${widget.date.year}年${widget.date.month}月${widget.date.day}日 · ${weekdays[widget.date.weekday - 1]}';

  bool get isPast {
    final today = DailySchedule.normalizeDate(DateTime.now());
    return widget.date.isBefore(today);
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _closeWithMessage(String text) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirmPastEdit() async {
    if (!isPast) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('修改过去日期？'),
            content: const Text('这是过去日期，修改仅用于记录，不会补发过去的提醒。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续修改'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _chooseShift({ShiftType? filter}) async {
    if (!await _confirmPastEdit() || !mounted) return;
    final controller = context.read<ScheduleController>();
    final selected = await showShiftPicker(
      context,
      shifts: controller.enabledTemplates,
      initialFilter: filter,
    );
    if (selected == null || !mounted) return;
    final existing = controller.scheduleFor(widget.date);
    if (existing?.shiftTemplateId == selected.id) {
      _message('当前已经是 ${selected.code} ${selected.name}');
      return;
    }
    final updated = await confirmAndSetShift(
      context,
      date: widget.date,
      newShift: selected,
      reason: existing == null ? '手动安排班次' : '临时调班',
    );
    if (updated != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _markSpecial(ShiftType type) async {
    final controller = context.read<ScheduleController>();
    var shift = controller.enabledTemplates
        .where((item) => item.type == type)
        .firstOrNull;
    if (shift == null) {
      final create = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('还没有${type.label}班次'),
          content: Text(
            '是否快速创建一个${type == ShiftType.rest ? 'OFF 休息' : 'LEAVE 请假'}班次？',
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
      if (create != true || !mounted) return;
      final shifts = context.read<ShiftController>();
      final baseCode = type == ShiftType.rest ? 'OFF' : 'LEAVE';
      var code = baseCode;
      var suffix = 2;
      while (shifts.items.any((item) => item.code.toUpperCase() == code)) {
        code = '$baseCode$suffix';
        suffix++;
      }
      final now = DateTime.now();
      shift = ShiftTemplate(
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
        await controller.refresh(showLoading: false);
      } on AppException catch (error) {
        _message(error.userMessage);
        return;
      }
    }
    if (!mounted) return;
    await _applySpecialShift(shift);
  }

  Future<void> _applySpecialShift(ShiftTemplate shift) async {
    if (!await _confirmPastEdit() || !mounted) return;
    final updated = await confirmAndSetShift(
      context,
      date: widget.date,
      newShift: shift,
      reason: '标记${shift.type.label}',
    );
    if (updated != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _restore(DailySchedule schedule) async {
    final controller = context.read<ScheduleController>();
    final current = controller.shiftFor(schedule);
    final original = controller.originalShiftFor(schedule);
    if (original == null) {
      _message('原班次数据缺失，请重新选择班次');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复原排班？'),
        content: Text(
          '当前为 ${current?.code ?? '未知'} ${current?.name ?? ''}，原排班为 ${original.code} ${original.name}。确认恢复吗？${original.isEnabled ? '' : '\n\n该班次目前已停用，仍可恢复。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.restore(widget.date);
      if (!mounted) return;
      _closeWithMessage('已恢复原排班');
    } on AppException catch (error) {
      _message(error.userMessage);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除当天排班？'),
        content: const Text('删除后，该日期将变为未排班。后续接入闹钟功能后，对应提醒也会被取消。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ScheduleController>().deleteDate(widget.date);
      if (!mounted) return;
      _closeWithMessage('已删除当天排班');
    } on AppException catch (error) {
      _message(error.userMessage);
    }
  }

  Future<void> _swap(DailySchedule schedule) async {
    final target = await showDatePicker(
      context: context,
      initialDate: widget.date.add(const Duration(days: 1)),
      firstDate: DateTime(widget.date.year - 2),
      lastDate: DateTime(widget.date.year + 3),
      helpText: '选择要交换的日期',
    );
    if (target == null || !mounted) return;
    final controller = context.read<ScheduleController>();
    final other = await controller.repository.getByDate(target);
    if (!mounted) return;
    if (other == null) {
      final move = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('目标日期未排班'),
          content: Text(
            '是否将 ${widget.date.month}月${widget.date.day}日的班次移动到 ${target.month}月${target.day}日？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认移动'),
            ),
          ],
        ),
      );
      if (move != true) return;
    } else {
      final firstShift = controller.shiftFor(schedule);
      final secondShift = controller.shiftFor(other);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('交换班次预览'),
          content: Text(
            '交换前：\n${widget.date.month}月${widget.date.day}日：${firstShift?.code ?? '数据缺失'}\n${target.month}月${target.day}日：${secondShift?.code ?? '数据缺失'}\n\n交换后两天都会标记为临时调班。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认交换'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await controller.swap(widget.date, target);
      if (!mounted) return;
      _closeWithMessage(other == null ? '班次已移动' : '两天班次已交换');
    } on AppException catch (error) {
      _message(error.userMessage);
    }
  }

  Future<void> _copy(DailySchedule schedule) async {
    final target = await showDatePicker(
      context: context,
      initialDate: widget.date.add(const Duration(days: 1)),
      firstDate: DateTime(widget.date.year - 2),
      lastDate: DateTime(widget.date.year + 3),
      helpText: '复制到其他日期',
    );
    if (target == null || !mounted) return;
    final controller = context.read<ScheduleController>();
    final existing = await controller.repository.getByDate(target);
    if (!mounted) return;
    var overwrite = false;
    if (existing != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('覆盖已有排班？'),
          content: Text('${target.month}月${target.day}日已有排班，是否覆盖？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      overwrite = true;
    }
    try {
      await controller.copyTo(schedule, target, overwriteExisting: overwrite);
      _message('排班已复制');
    } on AppException catch (error) {
      _message(error.userMessage);
    }
  }

  Future<void> _editNote(DailySchedule schedule) async {
    final note = TextEditingController(text: schedule.note);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改当天备注'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '可选备注'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, note.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    note.dispose();
    if (result == null || !mounted) return;
    try {
      await context.read<ScheduleController>().updateNote(widget.date, result);
      _message('备注已保存');
    } on AppException catch (error) {
      _message(error.userMessage);
    }
  }

  void _openShifts() {
    Navigator.pop(context);
    context.read<AppNavigationController>().select(2);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ScheduleController>();
    final schedule = controller.scheduleFor(widget.date);
    final shift = controller.shiftFor(schedule);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateText,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (isPast)
                          Text(
                            '过去日期',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: schedule == null
                  ? _UnscheduledContent(
                      busy: controller.isOperating,
                      onChoose: _chooseShift,
                      onRest: () => _markSpecial(ShiftType.rest),
                      onLeave: () => _markSpecial(ShiftType.leave),
                      onCreateShift: _openShifts,
                    )
                  : _ScheduledContent(
                      schedule: schedule,
                      shift: shift,
                      originalShift: controller.originalShiftFor(schedule),
                      onChange: _chooseShift,
                      onRestore: () => _restore(schedule),
                      onRest: () => _markSpecial(ShiftType.rest),
                      onLeave: () => _markSpecial(ShiftType.leave),
                      onSwap: () => _swap(schedule),
                      onCopy: () => _copy(schedule),
                      onNote: () => _editNote(schedule),
                      onDelete: _delete,
                      onPauseChanged: (value) =>
                          controller.setRemindersPaused(widget.date, value),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnscheduledContent extends StatelessWidget {
  const _UnscheduledContent({
    required this.busy,
    required this.onChoose,
    required this.onRest,
    required this.onLeave,
    required this.onCreateShift,
  });
  final bool busy;
  final VoidCallback onChoose;
  final VoidCallback onRest;
  final VoidCallback onLeave;
  final VoidCallback onCreateShift;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.event_busy_outlined, size: 46),
              const SizedBox(height: 12),
              Text(
                '当天尚未排班',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('选择一个班次模板来安排这一天'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: busy ? null : onChoose,
        icon: const Icon(Icons.badge_outlined),
        label: const Text('设置班次'),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onRest,
              icon: const Icon(Icons.weekend_outlined),
              label: const Text('标记休息'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onLeave,
              icon: const Icon(Icons.personal_injury_outlined),
              label: const Text('标记请假'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed: onCreateShift,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建班次模板'),
      ),
    ],
  );
}

class _ScheduledContent extends StatelessWidget {
  const _ScheduledContent({
    required this.schedule,
    required this.shift,
    required this.originalShift,
    required this.onChange,
    required this.onRestore,
    required this.onRest,
    required this.onLeave,
    required this.onSwap,
    required this.onCopy,
    required this.onNote,
    required this.onDelete,
    required this.onPauseChanged,
  });

  final DailySchedule schedule;
  final ShiftTemplate? shift;
  final ShiftTemplate? originalShift;
  final VoidCallback onChange;
  final VoidCallback onRestore;
  final VoidCallback onRest;
  final VoidCallback onLeave;
  final VoidCallback onSwap;
  final VoidCallback onCopy;
  final VoidCallback onNote;
  final VoidCallback onDelete;
  final ValueChanged<bool> onPauseChanged;

  String _dateTime(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final reminders = shift == null || shift!.type != ShiftType.work
        ? const <MapEntry<dynamic, DateTime>>[]
        : AlarmTimeCalculator.calculateAndSort(
            scheduleDate: schedule.date,
            arrivalTime: shift!.arrivalTime,
            arrivalDayOffset: shift!.arrivalDayOffset,
            rules: schedule.reminderOverrides.isEmpty
                ? shift!.reminderRules
                : schedule.reminderOverrides,
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: shift == null
                ? const Row(
                    children: [
                      Icon(Icons.error_outline_rounded),
                      SizedBox(width: 12),
                      Expanded(child: Text('班次模板数据缺失，请重新选择班次')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Color(
                                shift!.colorValue,
                              ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: Text(
                              shift!.code,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(shift!.colorValue),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shift!.name,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${shift!.type.label} · ${shift!.arrivalTime?.format() ?? '无需到岗'}',
                                ),
                              ],
                            ),
                          ),
                          if (schedule.isTemporaryChanged)
                            const Chip(
                              avatar: Icon(
                                Icons.change_circle_outlined,
                                size: 18,
                              ),
                              label: Text('临时调班'),
                            ),
                        ],
                      ),
                      if (schedule.isTemporaryChanged) ...[
                        const SizedBox(height: 14),
                        Text(
                          '原排班：${originalShift?.code ?? '数据缺失'} ${originalShift?.name ?? ''}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (schedule.note.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('备注：${schedule.note}'),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (reminders.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '计划提醒',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('仅为计算预览，尚未登记系统闹钟'),
                  const SizedBox(height: 12),
                  for (final item in reminders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_dateTime(item.value)} · ${item.key.name}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('暂停当天全部提醒'),
                    value: schedule.isAllRemindersPaused,
                    onChanged: onPauseChanged,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        if (schedule.isTemporaryChanged)
          FilledButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('恢复原排班'),
          ),
        if (schedule.isTemporaryChanged) const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onChange,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('更换班次 / 临时调班'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onRest,
                child: const Text('标记休息'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: onLeave,
                child: const Text('标记请假'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onSwap,
          icon: const Icon(Icons.compare_arrows_rounded),
          label: const Text('与其他日期交换班次'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('复制到其他日期'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onNote,
          icon: const Icon(Icons.notes_rounded),
          label: const Text('修改备注'),
        ),
        const SizedBox(height: 18),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('删除当天排班'),
        ),
      ],
    );
  }
}
