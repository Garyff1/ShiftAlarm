import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/alarm_record.dart';
import '../../shared/empty_states/empty_state.dart';
import 'alarm_controller.dart';

class AlarmRecordsPage extends StatelessWidget {
  const AlarmRecordsPage({super.key});

  String _time(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AlarmController>();
    final records = controller.formalRecords;
    return Scaffold(
      appBar: AppBar(
        title: const Text('闹钟记录'),
        actions: [
          IconButton(
            tooltip: '重新同步',
            onPressed: controller.isSyncing ? null : controller.synchronize,
            icon: controller.isSyncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: records.isEmpty
          ? EmptyState(
              icon: Icons.alarm_off_outlined,
              title: '还没有闹钟记录',
              message: '为未来工作日安排班次后，系统闹钟会显示在这里',
              actionLabel: '重新同步',
              onAction: controller.synchronize,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _AlarmRecordCard(
                record: records[index],
                timeText: _time(records[index].triggerAt),
              ),
            ),
    );
  }
}

class _AlarmRecordCard extends StatelessWidget {
  const _AlarmRecordCard({required this.record, required this.timeText});
  final AlarmRecord record;
  final String timeText;

  @override
  Widget build(BuildContext context) {
    final color = switch (record.status.storageValue) {
      'registered' => Theme.of(context).colorScheme.primary,
      'ringing' => Theme.of(context).colorScheme.error,
      'failed' || 'permission_blocked' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.alarm_rounded, color: color),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$timeText · ${record.reminderName}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text('${record.shiftCode} · ${record.shiftName}'),
                  Text(
                    record.status.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  if (record.snoozeCount > 0)
                    Text(
                      '已贪睡 ${record.snoozeCount}/${record.maxSnoozeCount} 次',
                    ),
                  if (record.failureReason != null)
                    Text(
                      record.failureReason!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
