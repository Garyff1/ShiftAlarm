import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_mode_theme.dart';
import '../../data/models/app_enums.dart';
import '../../services/interaction/interaction_feedback_service.dart';
import 'app_controller.dart';

class InterfaceModePage extends StatefulWidget {
  const InterfaceModePage({super.key, this.onboarding = false});

  final bool onboarding;

  @override
  State<InterfaceModePage> createState() => _InterfaceModePageState();
}

class _InterfaceModePageState extends State<InterfaceModePage> {
  AppInterfaceMode? _selected;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected ??= context.read<AppController>().settings.interfaceMode;
  }

  Future<void> _save() async {
    if (_saving) return;
    final app = context.read<AppController>();
    setState(() => _saving = true);
    final ok = await app.updateSettings(
      app.settings.copyWith(
        interfaceMode: _selected,
        onboardingCompleted: true,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('界面模式保存失败，请重试')));
      return;
    }
    await InteractionFeedbackService.success(app.settings);
    if (!widget.onboarding && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final modeTheme = AppModeTheme.of(context);
    final settings = context.watch<AppController>().settings;
    final content = ListView(
      padding: EdgeInsets.fromLTRB(
        modeTheme.pagePadding,
        widget.onboarding ? 28 : 16,
        modeTheme.pagePadding,
        28,
      ),
      children: [
        if (widget.onboarding) ...[
          Text(
            '选择适合你的界面',
            key: const Key('interface-mode-title'),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '只会改变页面、字号和操作方式，不会改变排班、闹钟或铃声。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
        ],
        for (final mode in AppInterfaceMode.values) ...[
          _ModeCard(
            mode: mode,
            selected: _selected == mode,
            onTap: () {
              unawaited(InteractionFeedbackService.selection(settings));
              setState(() => _selected = mode);
            },
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('use-interface-mode-button'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Text(_saving ? '正在保存' : '使用这个模式'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '以后可以在“设置—界面模式”中随时更改，不影响排班和闹钟。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    if (widget.onboarding) {
      return Scaffold(body: SafeArea(child: content));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('界面模式')),
      body: content,
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final AppInterfaceMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = AppModeTheme.of(context).reduceMotion;
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label}，${mode.description}',
      hint: '双击选择',
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2.2 : 1,
          ),
        ),
        child: InkWell(
          key: Key('interface-mode-${mode.storageValue}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(switch (mode) {
                      AppInterfaceMode.standard => Icons.dashboard_rounded,
                      AppInterfaceMode.largeText => Icons.text_increase_rounded,
                      AppInterfaceMode.simple => Icons.touch_app_rounded,
                    }, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        mode.label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected ? colors.primary : colors.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(mode.description),
                const SizedBox(height: 14),
                _ModePreview(mode: mode),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModePreview extends StatelessWidget {
  const _ModePreview({required this.mode});
  final AppInterfaceMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final large = mode == AppInterfaceMode.largeText;
    final simple = mode == AppInterfaceMode.simple;
    final items = simple
        ? const ['今天', '排班', '更多']
        : const ['首页', '排班', '班次', '铃声', '设置'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            simple ? '今天上早班' : '今天 · A1早班',
            style:
                (large
                        ? Theme.of(context).textTheme.headlineSmall
                        : Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(large ? '06:00  下一次闹钟' : '08:00 到岗 · 06:00 闹钟'),
          if (simple) ...[const SizedBox(height: 4), const Text('明天上晚班')],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map(
                  (item) => Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: large ? 12 : 9,
                      vertical: large ? 8 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(item),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
