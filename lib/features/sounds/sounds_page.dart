import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/alarm_sound.dart';
import '../../data/models/sound_ids.dart';
import '../../data/repositories/alarm_sound_repository.dart';
import '../../shared/empty_states/empty_state.dart';
import '../../shared/widgets/async_states.dart';
import '../../services/sounds/native_sound_service.dart';
import 'sound_controller.dart';
import 'sound_picker_sheet.dart';

class SoundsPage extends StatefulWidget {
  const SoundsPage({super.key});

  @override
  State<SoundsPage> createState() => _SoundsPageState();
}

class _SoundsPageState extends State<SoundsPage> {
  Future<void> _importSound() async {
    final controller = context.read<SoundController>();
    final candidate = await controller.pickSound();
    if (!mounted) return;
    if (candidate == null) {
      _showMessage(controller.errorMessage ?? controller.noticeMessage);
      return;
    }
    try {
      final duplicate = await controller.findDuplicate(candidate);
      if (!mounted) return;
      if (duplicate != null) {
        final action = await _duplicateAction(duplicate);
        if (action == _DuplicateAction.cancel || action == null) {
          await controller.discardCandidate(candidate);
          return;
        }
        if (action == _DuplicateAction.useExisting) {
          await controller.discardCandidate(candidate);
          await controller.playPreview(duplicate);
          if (mounted) _showMessage('正在试听已有铃声“${duplicate.displayName}”');
          return;
        }
      }
      final sound = await controller.commitCandidate(candidate);
      if (mounted) _showMessage('“${sound.displayName}”已导入铃声库');
    } catch (error) {
      await controller.discardCandidate(candidate);
      if (mounted) _showMessage('导入失败：${_errorText(error)}');
    }
  }

  Future<_DuplicateAction?> _duplicateAction(AlarmSound existing) =>
      showDialog<_DuplicateAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('该音频已经导入过'),
          content: Text('铃声库中已有“${existing.displayName}”，是否仍保留一份副本？'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateAction.cancel),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateAction.useExisting),
              child: const Text('使用已有铃声'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateAction.importCopy),
              child: const Text('仍然导入'),
            ),
          ],
        ),
      );

  Future<void> _rename(AlarmSound sound) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSoundDialog(initialName: sound.displayName),
    );
    if (name == null || !mounted) return;
    try {
      await context.read<SoundController>().rename(sound, name);
      if (mounted) _showMessage('铃声已重命名');
    } catch (error) {
      if (mounted) _showMessage(_errorText(error));
    }
  }

  Future<void> _setDefault(AlarmSound? sound) async {
    try {
      await context.read<SoundController>().setDefault(sound);
      if (mounted) {
        _showMessage(sound == null ? '已改用系统默认闹钟铃声' : '已设为应用默认铃声');
      }
    } catch (error) {
      if (mounted) _showMessage(_errorText(error));
    }
  }

  Future<void> _showUsage(AlarmSound sound) async {
    final summary = await context.read<SoundController>().usageFor(sound);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UsageSheet(sound: sound, summary: summary),
    );
  }

  Future<void> _scheduleTestAlarm(
    AlarmSound sound, {
    int delaySeconds = 60,
  }) async {
    final ok = await context.read<SoundController>().scheduleTestAlarm(
      sound,
      delaySeconds: delaySeconds,
    );
    if (!mounted) return;
    _showMessage(
      ok
          ? '${delaySeconds ~/ 60} 分钟测试闹钟已登记；可以锁屏、结束进程或重启手机'
          : '测试闹钟登记失败，请先检查精确闹钟权限',
    );
  }

  Future<void> _delete(AlarmSound sound) async {
    final controller = context.read<SoundController>();
    final usage = await controller.usageFor(sound);
    if (!mounted) return;
    String? replacementId;
    if (usage.isReferenced) {
      final action = await showDialog<_DeleteAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('铃声正在使用中'),
          content: Text(
            '“${sound.displayName}”正被 ${usage.shiftCount} 个班次、${usage.reminderCount} 条提醒和 ${usage.futureAlarmCount} 条未来闹钟使用${usage.isAppDefault ? '，并且是应用默认铃声' : ''}。删除前必须安全替换引用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DeleteAction.viewUsage),
              child: const Text('查看使用位置'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DeleteAction.chooseReplacement),
              child: const Text('选择替代铃声'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DeleteAction.useSystem),
              child: const Text('改为系统默认并删除'),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;
      if (action == _DeleteAction.viewUsage) {
        await _showUsage(sound);
        return;
      }
      if (action == _DeleteAction.chooseReplacement) {
        final selection = await showSoundPickerSheet(
          context,
          title: '选择替代铃声',
          selectedId: SoundIds.system,
        );
        if (!mounted || selection == null) return;
        if (selection.soundId == sound.id) {
          _showMessage('不能使用待删除铃声替代自身');
          return;
        }
        replacementId = selection.soundId ?? SoundIds.system;
      } else {
        replacementId = SoundIds.system;
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('删除铃声？'),
          content: Text('将永久删除应用内部的“${sound.displayName}”，此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      replacementId = SoundIds.system;
    }
    try {
      await controller.replaceAndDelete(sound, replacementId: replacementId);
      if (mounted) _showMessage(controller.noticeMessage ?? '铃声已删除');
    } catch (error) {
      if (mounted) _showMessage('删除失败：${_errorText(error)}');
    }
  }

  void _showMessage(String? message) {
    if (message == null || message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SoundController>();
    return CustomScrollView(
      key: const PageStorageKey('sounds-page'),
      slivers: [
        SliverAppBar.large(
          title: const Text('铃声'),
          actions: [
            IconButton(
              key: const Key('import-sound-button'),
              tooltip: '导入铃声',
              onPressed: controller.isBusy ? null : _importSound,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 6),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          sliver: SliverList.list(
            children: [
              _DefaultBanner(controller: controller),
              const _SectionTitle('系统铃声'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  key: const Key('system-sound-tile'),
                  leading: IconButton.filledTonal(
                    tooltip:
                        controller.previewSoundId == SoundIds.system &&
                            controller.previewState.isPlaying
                        ? '暂停试听'
                        : '试听铃声',
                    onPressed: controller.playSystemPreview,
                    icon: Icon(
                      controller.previewSoundId == SoundIds.system &&
                              controller.previewState.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  title: const Text('系统默认闹钟铃声'),
                  subtitle: const Text('由 Android 系统提供，始终作为最终兜底'),
                  trailing: controller.defaultSoundId == SoundIds.system
                      ? const Icon(Icons.check_circle_rounded)
                      : TextButton(
                          onPressed: () => _setDefault(null),
                          child: const Text('设为默认'),
                        ),
                ),
              ),
              const _SectionTitle('自定义铃声'),
              if (controller.isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.errorMessage != null)
                ErrorState(
                  message: controller.errorMessage!,
                  onRetry: () => controller.load(showLoading: true),
                )
              else if (controller.items.isEmpty)
                EmptyState(
                  icon: Icons.library_music_outlined,
                  title: '还没有自定义铃声',
                  message: '可以从手机中导入 MP3、WAV、M4A、AAC 或 OGG 音频文件。',
                  actionLabel: '导入铃声',
                  onAction: _importSound,
                )
              else
                for (final sound in controller.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SoundCard(
                      sound: sound,
                      usage: controller.usageSnapshot(sound),
                      isDefault: controller.defaultSoundId == sound.id,
                      isPlaying:
                          controller.previewSoundId == sound.id &&
                          controller.previewState.isPlaying,
                      progress: controller.previewSoundId == sound.id
                          ? controller.previewState
                          : const SoundPreviewState(),
                      onPlay: sound.isAvailable
                          ? () => controller.playPreview(sound)
                          : null,
                      onRename: () => _rename(sound),
                      onSetDefault: () => _setDefault(sound),
                      onTestAlarm: () => _scheduleTestAlarm(sound),
                      onRebootTestAlarm: () =>
                          _scheduleTestAlarm(sound, delaySeconds: 120),
                      onUsage: () => _showUsage(sound),
                      onDelete: () => _delete(sound),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _DuplicateAction { useExisting, importCopy, cancel }

enum _DeleteAction { viewUsage, chooseReplacement, useSystem }

class _RenameSoundDialog extends StatefulWidget {
  const _RenameSoundDialog({required this.initialName});
  final String initialName;

  @override
  State<_RenameSoundDialog> createState() => _RenameSoundDialogState();
}

class _RenameSoundDialogState extends State<_RenameSoundDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('重命名铃声'),
    content: TextField(
      key: const Key('sound-rename-field'),
      controller: controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: '铃声名称'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('保存'),
      ),
    ],
  );
}

class _DefaultBanner extends StatelessWidget {
  const _DefaultBanner({required this.controller});
  final SoundController controller;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.notifications_active_outlined),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前应用默认铃声', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 3),
              Text(
                controller.defaultCustomSound?.displayName ?? '系统默认闹钟铃声',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SoundCard extends StatelessWidget {
  const _SoundCard({
    required this.sound,
    required this.usage,
    required this.isDefault,
    required this.isPlaying,
    required this.progress,
    required this.onPlay,
    required this.onRename,
    required this.onSetDefault,
    required this.onTestAlarm,
    required this.onRebootTestAlarm,
    required this.onUsage,
    required this.onDelete,
  });

  final AlarmSound sound;
  final SoundReferenceSummary usage;
  final bool isDefault;
  final bool isPlaying;
  final SoundPreviewState progress;
  final VoidCallback? onPlay;
  final VoidCallback onRename;
  final VoidCallback onSetDefault;
  final VoidCallback onTestAlarm;
  final VoidCallback onRebootTestAlarm;
  final VoidCallback onUsage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('sound-card-${sound.id}'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
      child: Column(
        children: [
          ListTile(
            leading: IconButton.filledTonal(
              tooltip: sound.isAvailable
                  ? (isPlaying ? '暂停试听' : '试听铃声')
                  : '铃声不可用',
              onPressed: onPlay,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    sound.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDefault) ...[const SizedBox(width: 8), const _Tag('默认')],
                if (!sound.isAvailable) ...[
                  const SizedBox(width: 8),
                  const _Tag('不可用', error: true),
                ],
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${sound.format.toUpperCase()} · ${_formatDuration(sound.durationMilliseconds)} · ${_formatBytes(sound.fileSize)} · 使用 ${usage.total} 处',
              ),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'rename') onRename();
                if (value == 'default') onSetDefault();
                if (value == 'test') onTestAlarm();
                if (value == 'test-reboot') onRebootTestAlarm();
                if (value == 'usage') onUsage();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(
                  value: 'default',
                  enabled: sound.isAvailable && !isDefault,
                  child: const Text('设为默认'),
                ),
                PopupMenuItem(
                  value: 'test',
                  enabled: sound.isAvailable,
                  child: const Text('1 分钟测试闹钟'),
                ),
                PopupMenuItem(
                  value: 'test-reboot',
                  enabled: sound.isAvailable,
                  child: const Text('2 分钟重启测试闹钟'),
                ),
                const PopupMenuItem(value: 'usage', child: Text('查看使用位置')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
          if (progress.durationMilliseconds > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value:
                          (progress.positionMilliseconds /
                                  progress.durationMilliseconds)
                              .clamp(0.0, 1.0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_formatDuration(progress.positionMilliseconds)} / ${_formatDuration(progress.durationMilliseconds)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          if (!sound.isAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '文件异常：${sound.failureReason ?? '无法读取'}；正式闹钟会自动使用下一级铃声。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _UsageSheet extends StatelessWidget {
  const _UsageSheet({required this.sound, required this.summary});
  final AlarmSound sound;
  final SoundReferenceSummary summary;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sound.displayName,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('应用默认：${summary.isAppDefault ? '是' : '否'}'),
            _UsageGroup('班次（${summary.shiftCount}）', summary.shiftNames),
            _UsageGroup('提醒（${summary.reminderCount}）', summary.reminderNames),
            _UsageGroup(
              '未来闹钟（${summary.futureAlarmCount}）',
              summary.futureAlarmLabels,
            ),
          ],
        ),
      ),
    ),
  );
}

class _UsageGroup extends StatelessWidget {
  const _UsageGroup(this.title, this.items);
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Text(
            '无',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $item'),
            ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}

String _formatDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
