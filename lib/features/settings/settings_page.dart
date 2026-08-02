import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/sound_ids.dart';
import '../../shared/widgets/async_states.dart';
import '../alarms/alarm_controller.dart';
import '../alarms/alarm_records_page.dart';
import '../alarms/permission_center_page.dart';
import '../sounds/sound_controller.dart';
import '../sounds/sound_picker_sheet.dart';
import 'app_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _save(BuildContext context, AppSettings settings) async {
    final ok = await context.read<AppController>().updateSettings(settings);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置保存失败，已恢复原设置')));
    }
  }

  Future<void> _pickDefaultSound(BuildContext context) async {
    final sounds = context.read<SoundController>();
    final result = await showSoundPickerSheet(
      context,
      title: '应用默认铃声',
      selectedId: sounds.defaultSoundId,
    );
    if (result == null || !context.mounted) return;
    try {
      final selected = result.soundId == SoundIds.system
          ? null
          : sounds.items.where((item) => item.id == result.soundId).firstOrNull;
      await sounds.setDefault(selected);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('默认铃声保存失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppController>().settings;
    final alarms = context.watch<AlarmController>();
    return CustomScrollView(
      key: const PageStorageKey('settings-page'),
      slivers: [
        const SliverAppBar.large(title: Text('设置')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          sliver: SliverList.list(
            children: [
              _SectionTitle('外观'),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '主题模式',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<AppThemeMode>(
                        segments: AppThemeMode.values
                            .map(
                              (mode) => ButtonSegment(
                                value: mode,
                                label: Text(mode.label),
                              ),
                            )
                            .toList(),
                        selected: {settings.themeMode},
                        onSelectionChanged: (selection) => _save(
                          context,
                          settings.copyWith(themeMode: selection.first),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _SectionTitle('日历与时间'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('一周起始日'),
                      subtitle: const Text('影响后续排班日历的星期顺序'),
                      trailing: DropdownButton<int>(
                        value: settings.weekStartDay,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('星期一')),
                          DropdownMenuItem(value: 7, child: Text('星期日')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _save(
                              context,
                              settings.copyWith(weekStartDay: value),
                            );
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('使用 24 小时制'),
                      subtitle: const Text('关闭后使用上午/下午格式'),
                      value: settings.use24HourFormat,
                      onChanged: (value) => _save(
                        context,
                        settings.copyWith(use24HourFormat: value),
                      ),
                    ),
                  ],
                ),
              ),
              _SectionTitle('提醒默认值'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('app-default-sound-tile'),
                      leading: const Icon(Icons.music_note_rounded),
                      title: const Text('应用默认铃声'),
                      subtitle: Text(
                        context
                                .watch<SoundController>()
                                .defaultCustomSound
                                ?.displayName ??
                            '系统默认闹钟铃声',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _pickDefaultSound(context),
                    ),
                    const Divider(height: 1),
                    _IntegerSettingTile(
                      title: '闹钟生成范围',
                      value: settings.alarmGenerationDays,
                      unit: '天',
                      min: 1,
                      max: 30,
                      onChanged: (value) => _save(
                        context,
                        settings.copyWith(alarmGenerationDays: value),
                      ),
                    ),
                    const Divider(height: 1),
                    _IntegerSettingTile(
                      title: '默认贪睡时间',
                      value: settings.defaultSnoozeMinutes,
                      unit: '分钟',
                      min: 1,
                      max: 30,
                      onChanged: (value) => _save(
                        context,
                        settings.copyWith(defaultSnoozeMinutes: value),
                      ),
                    ),
                    const Divider(height: 1),
                    _IntegerSettingTile(
                      title: '默认最大贪睡次数',
                      value: settings.defaultMaxSnoozeCount,
                      unit: '次',
                      min: 0,
                      max: 10,
                      onChanged: (value) => _save(
                        context,
                        settings.copyWith(defaultMaxSnoozeCount: value),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('默认振动'),
                      value: settings.defaultVibrationEnabled,
                      onChanged: (value) => _save(
                        context,
                        settings.copyWith(defaultVibrationEnabled: value),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('默认音量渐强'),
                      value: settings.defaultFadeInEnabled,
                      onChanged: (value) => _save(
                        context,
                        settings.copyWith(defaultFadeInEnabled: value),
                      ),
                    ),
                  ],
                ),
              ),
              _SectionTitle('应用'),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('权限中心'),
                      subtitle: Text(alarms.overallStatus),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PermissionCenterPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.alarm_outlined),
                      title: const Text('闹钟记录'),
                      subtitle: Text('共 ${alarms.formalRecords.length} 条'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AlarmRecordsPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('关于 ShiftAlarm'),
                      subtitle: const Text('轻量、清晰的排班闹钟'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: AppConstants.appName,
                        applicationVersion: AppConstants.version,
                        applicationLegalese: '第一阶段：项目基础、班次模板与本地设置',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  '版本 ${AppConstants.version}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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

class _IntegerSettingTile extends StatelessWidget {
  const _IntegerSettingTile({
    required this.title,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text(
              '$value $unit',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value $unit',
          onChanged: (next) => onChanged(next.round()),
        ),
      ],
    ),
  );
}
