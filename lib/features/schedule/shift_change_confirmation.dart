import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_mode_theme.dart';
import '../../core/utils/alarm_time_calculator.dart';
import '../../core/utils/friendly_status.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/reminder_rule.dart';
import '../../data/models/shift_template.dart';
import '../../features/settings/app_controller.dart';
import '../../services/interaction/interaction_feedback_service.dart';
import '../alarms/permission_center_page.dart';
import 'schedule_controller.dart';

Future<DailySchedule?> confirmAndSetShift(
  BuildContext context, {
  required DateTime date,
  required ShiftTemplate newShift,
  String reason = '手动修改班次',
}) async {
  final controller = context.read<ScheduleController>();
  final current = controller.scheduleFor(date);
  final oldShift = controller.shiftFor(current);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ShiftChangeDialog(
      date: date,
      current: current,
      oldShift: oldShift,
      newShift: newShift,
    ),
  );
  if (confirmed != true || !context.mounted) return null;
  final settings = context.read<AppController>().settings;
  unawaited(InteractionFeedbackService.selection(settings));
  try {
    await controller.setShift(date, newShift, reason: reason);
    if (!context.mounted) return controller.scheduleFor(date);
    final updated = controller.scheduleFor(date);
    final syncStatus = updated?.alarmSyncStatus ?? AlarmSyncStatus.failed;
    final successful =
        syncStatus == AlarmSyncStatus.synchronized ||
        syncStatus == AlarmSyncStatus.notRequired;
    if (successful) {
      unawaited(InteractionFeedbackService.success(settings));
    } else {
      unawaited(InteractionFeedbackService.warning(settings));
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        key: const Key('shift-change-result'),
        duration: const Duration(seconds: 7),
        content: successful
            ? Text(
                '已经改为 ${newShift.code}${newShift.name}，${FriendlyStatus.sync(syncStatus)}',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('班次已经修改，但${FriendlyStatus.sync(syncStatus)}'),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.inversePrimary,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PermissionCenterPage(
                          simpleMode:
                              settings.interfaceMode.usesSimpleNavigation,
                        ),
                      ),
                    ),
                    child: const Text('打开闹钟健康中心'),
                  ),
                ],
              ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            try {
              await controller.undoShiftChange(date, current);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已撤销上一次班次修改')));
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('撤销失败，请重新打开该日期检查')),
                );
              }
            }
          },
        ),
      ),
    );
    return updated;
  } catch (_) {
    if (context.mounted) {
      unawaited(InteractionFeedbackService.warning(settings));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.errorMessage ?? '班次修改失败，请重试')),
      );
    }
    return null;
  }
}

class _ShiftChangeDialog extends StatelessWidget {
  const _ShiftChangeDialog({
    required this.date,
    required this.current,
    required this.oldShift,
    required this.newShift,
  });

  final DateTime date;
  final DailySchedule? current;
  final ShiftTemplate? oldShift;
  final ShiftTemplate newShift;

  int _enabledAlarmCount(ShiftTemplate? shift) =>
      shift?.reminderRules.where((item) => item.isEnabled).length ?? 0;

  @override
  Widget build(BuildContext context) {
    final mode = AppModeTheme.of(context);
    return AlertDialog(
      key: const Key('shift-change-preview-dialog'),
      title: Text('确认修改 ${date.month}月${date.day}日 的班次吗？'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShiftPreview(
                label: '原来',
                date: date,
                shift: oldShift,
                schedule: current,
              ),
              SizedBox(height: mode.sectionSpacing / 2),
              Icon(
                Icons.arrow_downward_rounded,
                color: Theme.of(context).colorScheme.primary,
                semanticLabel: '修改为',
              ),
              SizedBox(height: mode.sectionSpacing / 2),
              _ShiftPreview(label: '修改后', date: date, shift: newShift),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '闹钟变化',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('将取消 ${_enabledAlarmCount(oldShift)} 个旧闹钟'),
                    Text('将设置 ${_enabledAlarmCount(newShift)} 个新闹钟'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel-shift-change'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('不修改'),
        ),
        FilledButton(
          key: const Key('confirm-shift-change'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认修改'),
        ),
      ],
    );
  }
}

class _ShiftPreview extends StatelessWidget {
  const _ShiftPreview({
    required this.label,
    required this.date,
    required this.shift,
    this.schedule,
  });

  final String label;
  final DateTime date;
  final ShiftTemplate? shift;
  final DailySchedule? schedule;

  String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final item = shift;
    final reminders = item == null
        ? const <MapEntry<ReminderRule, DateTime>>[]
        : AlarmTimeCalculator.calculateAndSort(
            scheduleDate: date,
            arrivalTime: item.arrivalTime,
            arrivalDayOffset: item.arrivalDayOffset,
            rules: item.reminderRules,
          );
    return Semantics(
      label: item == null
          ? '$label，未排班'
          : '$label，${item.code}${item.name}，${item.arrivalTime?.format() ?? '无需到岗'}，${reminders.length}条提醒',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: schedule?.isTemporaryChanged == true
              ? Border.all(
                  color: Theme.of(context).colorScheme.tertiary,
                  width: 1.5,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item == null ? '尚未排班' : '${item.code} ${item.name}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (item != null) ...[
              const SizedBox(height: 4),
              Text('${item.arrivalTime?.format() ?? '无需'} 到岗'),
              for (final reminder in reminders)
                Text('${_formatTime(reminder.value)} ${reminder.key.name}'),
            ],
          ],
        ),
      ),
    );
  }
}
