import 'package:flutter/material.dart';
import '../../data/models/schedule_change_log.dart';

Future<void> showScheduleChangeLogs(
  BuildContext context,
  List<ScheduleChangeLog> logs,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              '调班记录',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text('本月暂无调班记录'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: logs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _LogTile(log: logs[index]),
                  ),
          ),
        ],
      ),
    ),
  ),
);

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final ScheduleChangeLog log;

  String _date(DateTime value) => '${value.month}月${value.day}日';

  @override
  Widget build(BuildContext context) {
    final oldText = log.originalShiftCode ?? log.originalShiftName ?? '未排班';
    final newText = log.newShiftCode ?? log.newShiftName ?? '未排班';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            log.changeType == .restore
                ? Icons.restore_rounded
                : Icons.swap_horiz_rounded,
          ),
        ),
        title: Text(
          '${_date(log.date)} · ${log.changeType.label}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '$oldText → $newText${log.relatedDate == null ? '' : '\n关联日期：${_date(log.relatedDate!)}'}${log.reason.isEmpty ? '' : '\n${log.reason}'}',
        ),
        isThreeLine: log.relatedDate != null || log.reason.isNotEmpty,
      ),
    );
  }
}
