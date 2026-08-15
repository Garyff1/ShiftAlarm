import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_mode_theme.dart';
import '../../data/models/alarm_lifecycle_event.dart';
import '../../services/alarm/alarm_diagnostic_service.dart';
import '../../shared/widgets/async_states.dart';
import 'alarm_controller.dart';

class AlarmDiagnosticsPage extends StatelessWidget {
  const AlarmDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AlarmController>();
    final summaries = controller.diagnosticSummaries;
    return Scaffold(
      appBar: AppBar(title: const Text('闹钟诊断')),
      body: RefreshIndicator(
        onRefresh: controller.runHealthCheck,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppModeTheme.of(context).pagePadding,
            8,
            AppModeTheme.of(context).pagePadding,
            32,
          ),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '每一次响铃都留下可核对的链路',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '这里区分“已提交系统”和“声音真正开始播放”。Android 不允许普通应用枚举系统中全部闹钟，因此不会伪造“系统已确认存在”的数量。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (summaries.isEmpty)
              const SectionCard(child: Text('还没有正式闹钟记录。设置排班后会在这里显示诊断链路。'))
            else
              for (final summary in summaries.take(60)) ...[
                _DiagnosticCard(summary: summary),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.summary});
  final AlarmDiagnosticSummary summary;

  @override
  Widget build(BuildContext context) {
    final alarm = summary.alarm;
    final color = switch (summary.state) {
      AlarmDiagnosticState.normal => Colors.green.shade700,
      AlarmDiagnosticState.failed => Theme.of(context).colorScheme.error,
      AlarmDiagnosticState.needsAttention => Theme.of(
        context,
      ).colorScheme.tertiary,
      AlarmDiagnosticState.ready => Theme.of(context).colorScheme.primary,
    };
    final icon = switch (summary.state) {
      AlarmDiagnosticState.normal => Icons.check_circle_rounded,
      AlarmDiagnosticState.failed => Icons.error_rounded,
      AlarmDiagnosticState.needsAttention => Icons.warning_amber_rounded,
      AlarmDiagnosticState.ready => Icons.schedule_rounded,
    };
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AlarmDiagnosticDetailPage(summary: summary),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(AppModeTheme.of(context).cardPadding),
          child: Row(
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alarm.triggerAt.month}月${alarm.triggerAt.day}日 ${_time(alarm.triggerAt)} · ${alarm.reminderName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.headline,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.conclusion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

class AlarmDiagnosticDetailPage extends StatelessWidget {
  const AlarmDiagnosticDetailPage({super.key, required this.summary});
  final AlarmDiagnosticSummary summary;

  static const _timeline = [
    (AlarmLifecycleStage.planned, '计划时间'),
    (AlarmLifecycleStage.scheduled, '系统登记'),
    (AlarmLifecycleStage.receiverReceived, '系统触发'),
    (AlarmLifecycleStage.ringServiceStarted, '响铃服务'),
    (AlarmLifecycleStage.audioPrepared, '声音准备'),
    (AlarmLifecycleStage.audioStarted, '音频播放'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('诊断详情')),
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        AppModeTheme.of(context).pagePadding,
        8,
        AppModeTheme.of(context).pagePadding,
        32,
      ),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.headline,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(summary.conclusion),
              if (summary.failureCategory != null) ...[
                const SizedBox(height: 8),
                Text(
                  '分类：${summary.failureCategory!.label}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            children: [
              for (final (stage, label) in _timeline)
                _TimelineRow(
                  label: label,
                  planned: stage == AlarmLifecycleStage.planned
                      ? summary.alarm.triggerAt
                      : null,
                  event: summary.eventFor(stage),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '技术信息',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text('原生 ID：${summary.alarm.nativeAlarmId ?? '未分配'}'),
              Text('生命周期事件：${summary.events.length} 条'),
              Text('当前记录状态：${summary.alarm.status.label}'),
              if (summary
                      .eventFor(AlarmLifecycleStage.scheduled)
                      ?.details['scheduleApi'] !=
                  null)
                Text(
                  '登记 API：${summary.eventFor(AlarmLifecycleStage.scheduled)!.details['scheduleApi']}',
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.label, required this.event, this.planned});
  final String label;
  final AlarmLifecycleEvent? event;
  final DateTime? planned;

  @override
  Widget build(BuildContext context) {
    final time = event?.occurredAt ?? planned;
    final completed = event != null || planned != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: completed
                ? Colors.green.shade700
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(time == null ? '--' : _dateTime(time)),
        ],
      ),
    );
  }
}

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _dateTime(DateTime value) =>
    '${value.month}/${value.day} ${_time(value)}:${value.second.toString().padLeft(2, '0')}';
