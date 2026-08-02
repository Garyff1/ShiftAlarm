import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/alarm_sound.dart';
import '../../data/models/sound_ids.dart';
import 'sound_controller.dart';

const _inheritSoundChoice = '__inherit_sound__';

class SoundSelection {
  const SoundSelection(this.soundId);

  /// `null` means inherit from the parent level; [SoundIds.system] is explicit.
  final String? soundId;
}

Future<SoundSelection?> showSoundPickerSheet(
  BuildContext context, {
  required String title,
  required String? selectedId,
  String? inheritLabel,
}) async {
  final controller = context.read<SoundController>();
  try {
    return await showModalBottomSheet<SoundSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SoundPickerSheet(
        title: title,
        selectedId: selectedId,
        inheritLabel: inheritLabel,
      ),
    );
  } finally {
    await controller.stopPreview();
  }
}

String soundDisplayName(
  Iterable<AlarmSound> sounds,
  String? soundId, {
  required String inheritLabel,
}) {
  if (soundId == null || soundId.isEmpty) return inheritLabel;
  if (soundId == SoundIds.system) return '系统默认闹钟铃声';
  for (final sound in sounds) {
    if (sound.id == soundId) {
      return sound.isAvailable
          ? sound.displayName
          : '${sound.displayName}（不可用）';
    }
  }
  return '已失效铃声（将自动降级）';
}

class _SoundPickerSheet extends StatelessWidget {
  const _SoundPickerSheet({
    required this.title,
    required this.selectedId,
    required this.inheritLabel,
  });

  final String title;
  final String? selectedId;
  final String? inheritLabel;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SoundController>();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: RadioGroup<String>(
                groupValue: selectedId ?? _inheritSoundChoice,
                onChanged: (value) {
                  if (value == null) return;
                  Navigator.pop(
                    context,
                    SoundSelection(value == _inheritSoundChoice ? null : value),
                  );
                },
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                  children: [
                    if (inheritLabel != null)
                      RadioListTile<String>(
                        value: _inheritSoundChoice,
                        title: Text(inheritLabel!),
                        subtitle: const Text('以后会自动跟随上一级设置'),
                        secondary: const Icon(Icons.alt_route_rounded),
                      ),
                    RadioListTile<String>(
                      value: SoundIds.system,
                      title: const Text('系统默认闹钟铃声'),
                      secondary: IconButton(
                        tooltip: '试听系统铃声',
                        onPressed: controller.playSystemPreview,
                        icon: Icon(
                          controller.previewSoundId == SoundIds.system &&
                                  controller.previewState.isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                      ),
                    ),
                    if (controller.items.isNotEmpty) const Divider(),
                    for (final sound in controller.items)
                      RadioListTile<String>(
                        value: sound.id,
                        enabled: sound.isAvailable,
                        title: Text(sound.displayName),
                        subtitle: Text(
                          sound.isAvailable
                              ? '${sound.format.toUpperCase()} · ${_duration(sound.durationMilliseconds)}'
                              : '文件不可用，闹钟将自动降级',
                        ),
                        secondary: IconButton(
                          tooltip: sound.isAvailable ? '试听' : '不可用',
                          onPressed: sound.isAvailable
                              ? () => controller.playPreview(sound)
                              : null,
                          icon: Icon(
                            controller.previewSoundId == sound.id &&
                                    controller.previewState.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
