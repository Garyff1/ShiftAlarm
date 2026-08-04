import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/errors/app_exception.dart';
import '../../data/models/shift_template.dart';
import '../../shared/empty_states/empty_state.dart';
import '../../shared/widgets/async_states.dart';
import 'shift_controller.dart';
import 'shift_editor_page.dart';

class ShiftListPage extends StatelessWidget {
  const ShiftListPage({super.key});

  Future<void> _openEditor(BuildContext context, [ShiftTemplate? shift]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ShiftEditorPage(existing: shift)),
    );
  }

  Future<void> _delete(BuildContext context, ShiftTemplate shift) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除班次？'),
        content: Text('“${shift.code} · ${shift.name}”删除后无法恢复。'),
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
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<ShiftController>().delete(shift.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('班次已删除')));
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
    final controller = context.watch<ShiftController>();
    Widget body;
    if (controller.isLoading) {
      body = const LoadingState(message: '正在读取班次…');
    } else if (controller.errorMessage != null) {
      body = ErrorState(
        message: controller.errorMessage!,
        onRetry: controller.load,
      );
    } else if (controller.items.isEmpty) {
      body = EmptyState(
        icon: Icons.badge_outlined,
        title: '还没有班次',
        message: '创建工作、休息或请假班次，作为后续排班的模板',
        actionLabel: '新建班次',
        onAction: () => _openEditor(context),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: controller.load,
        child: ListView.separated(
          key: const PageStorageKey('shift-list'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          itemCount: controller.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final shift = controller.items[index];
            return _ShiftCard(
              shift: shift,
              onTap: () => _openEditor(context, shift),
              onDelete: () => _delete(context, shift),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('班次')),
      body: body,
      floatingActionButton: controller.items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建班次'),
            ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.onTap,
    required this.onDelete,
  });
  final ShiftTemplate shift;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = Color(shift.colorValue);
    final time = shift.arrivalTime?.format() ?? '无需到岗';
    final enabledReminders = shift.reminderRules
        .where((rule) => rule.isEnabled)
        .length;
    return Semantics(
      button: true,
      label:
          '${shift.code}${shift.name}，$time，$enabledReminders条提醒，${shift.isEnabled ? '已启用' : '已停用'}',
      hint: '双击编辑班次',
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    shift.code,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
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
                          Flexible(
                            child: Text(
                              shift.name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (!shift.isEnabled) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text('已停用'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${shift.type.label} · $time${shift.arrivalDayOffset == 1 ? '（次日）' : ''}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (shift.reminderRules.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${shift.reminderRules.where((rule) => rule.isEnabled).length} 条启用提醒',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多班次操作',
                  onSelected: (value) => value == 'edit' ? onTap() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('编辑'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('删除'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
