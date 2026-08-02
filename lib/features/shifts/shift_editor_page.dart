import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/clock_time.dart';
import '../../data/models/reminder_rule.dart';
import '../../data/models/shift_template.dart';
import '../settings/app_controller.dart';
import '../sounds/sound_controller.dart';
import '../sounds/sound_picker_sheet.dart';
import 'shift_controller.dart';

class ShiftEditorPage extends StatefulWidget {
  const ShiftEditorPage({super.key, this.existing});
  final ShiftTemplate? existing;

  @override
  State<ShiftEditorPage> createState() => _ShiftEditorPageState();
}

class _ShiftEditorPageState extends State<ShiftEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _aliasesController;
  late final TextEditingController _noteController;
  late ShiftType _type;
  ClockTime? _arrivalTime;
  late int _arrivalDayOffset;
  late int _colorValue;
  late bool _isEnabled;
  late List<ReminderRule> _reminders;
  String? _defaultSoundId;
  bool _dirty = false;
  bool _saving = false;
  bool _defaultsCreated = false;

  static const colors = [
    0xFF526AA0,
    0xFF2E7D6F,
    0xFF9A6B24,
    0xFFA04A62,
    0xFF6D5CA8,
    0xFF467B91,
    0xFF7D6A58,
    0xFF56615A,
  ];

  @override
  void initState() {
    super.initState();
    final shift = widget.existing;
    _codeController = TextEditingController(text: shift?.code ?? '');
    _nameController = TextEditingController(text: shift?.name ?? '');
    _aliasesController = TextEditingController(
      text: shift?.aliases.join('、') ?? '',
    );
    _noteController = TextEditingController(text: shift?.note ?? '');
    _type = shift?.type ?? ShiftType.work;
    _arrivalTime = shift?.arrivalTime ?? const ClockTime(hour: 8, minute: 0);
    _arrivalDayOffset = shift?.arrivalDayOffset ?? 0;
    _colorValue = shift?.colorValue ?? colors.first;
    _isEnabled = shift?.isEnabled ?? true;
    _reminders = List.of(shift?.reminderRules ?? const []);
    _defaultSoundId = shift?.defaultSoundId;
    for (final controller in [
      _codeController,
      _nameController,
      _aliasesController,
      _noteController,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_defaultsCreated || widget.existing != null) return;
    _defaultsCreated = true;
    _reminders = _defaultReminders();
  }

  List<ReminderRule> _defaultReminders() {
    final settings = context.read<AppController>().settings;
    final definitions = [('起床', 120), ('出发', 60), ('即将到岗', 20)];
    return [
      for (var index = 0; index < definitions.length; index++)
        ReminderRule(
          id: IdGenerator.create('reminder'),
          name: definitions[index].$1,
          timeMode: ReminderTimeMode.beforeArrival,
          minutesBeforeArrival: definitions[index].$2,
          isVibrationEnabled: settings.defaultVibrationEnabled,
          isSnoozeEnabled: true,
          snoozeMinutes: settings.defaultSnoozeMinutes,
          maxSnoozeCount: settings.defaultMaxSnoozeCount,
          isVolumeFadeInEnabled: settings.defaultFadeInEnabled,
          sortOrder: index,
        ),
    ];
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  void _update(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
    });
  }

  Future<void> _pickArrivalTime() async {
    final current = _arrivalTime ?? const ClockTime(hour: 8, minute: 0);
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: '选择到岗时间',
    );
    if (result != null) {
      _update(
        () =>
            _arrivalTime = ClockTime(hour: result.hour, minute: result.minute),
      );
    }
  }

  Future<void> _pickDefaultSound() async {
    final result = await showSoundPickerSheet(
      context,
      title: '班次默认铃声',
      selectedId: _defaultSoundId,
      inheritLabel: '跟随应用默认',
    );
    if (result != null && mounted) {
      _update(() => _defaultSoundId = result.soundId);
    }
  }

  Future<void> _editReminder({ReminderRule? existing, int? index}) async {
    final result = await showDialog<ReminderRule>(
      context: context,
      builder: (_) => _ReminderEditorDialog(
        existing: existing,
        suggestedSortOrder: index ?? _reminders.length,
      ),
    );
    if (result == null) return;
    _update(() {
      if (index == null) {
        _reminders.add(result);
      } else {
        _reminders[index] = result;
      }
      _normalizeReminderOrder();
    });
  }

  void _normalizeReminderOrder() {
    _reminders = [
      for (var i = 0; i < _reminders.length; i++)
        _reminders[i].copyWith(sortOrder: i),
    ];
  }

  void _moveReminder(int index, int offset) {
    final next = index + offset;
    if (next < 0 || next >= _reminders.length) return;
    _update(() {
      final item = _reminders.removeAt(index);
      _reminders.insert(next, item);
      _normalizeReminderOrder();
    });
  }

  String? _validateReminders() {
    for (final rule in _reminders) {
      if (rule.name.trim().isEmpty) return '提醒名称不能为空';
      if (rule.timeMode == ReminderTimeMode.fixed && rule.fixedTime == null) {
        return '固定时间提醒必须选择时间';
      }
      if (rule.timeMode == ReminderTimeMode.beforeArrival &&
          (rule.minutesBeforeArrival == null ||
              rule.minutesBeforeArrival! < 0)) {
        return '到岗前提醒必须填写非负分钟数';
      }
      if (rule.snoozeMinutes < 1 || rule.snoozeMinutes > 60) {
        return '贪睡时间应在 1–60 分钟之间';
      }
      if (rule.maxSnoozeCount < 0) return '最大贪睡次数不能为负数';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == ShiftType.work && _arrivalTime == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('工作班必须设置到岗时间')));
      return;
    }
    final reminderError = _type == ShiftType.work ? _validateReminders() : null;
    if (reminderError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reminderError)));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final aliases = _aliasesController.text
        .split(RegExp(r'[,，、\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    final shift = ShiftTemplate(
      id: widget.existing?.id ?? IdGenerator.create('shift'),
      code: _codeController.text.trim(),
      name: _nameController.text.trim(),
      type: _type,
      aliases: aliases,
      colorValue: _colorValue,
      arrivalTime: _type == ShiftType.work ? _arrivalTime : null,
      arrivalDayOffset: _type == ShiftType.work ? _arrivalDayOffset : 0,
      reminderRules: _type == ShiftType.work ? _reminders : const [],
      defaultSoundId: _type == ShiftType.work ? _defaultSoundId : null,
      note: _noteController.text.trim(),
      isEnabled: _isEnabled,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      await context.read<ShiftController>().save(shift);
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.existing == null ? '班次已创建' : '班次已更新')),
      );
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('班次保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('放弃修改？'),
            content: const Text('当前修改尚未保存，确定离开吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃并离开'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _aliasesController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final navigator = Navigator.of(context);
      if (await _confirmLeave() && mounted) {
        setState(() => _dirty = false);
        navigator.pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新建班次' : '编辑班次'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            _SectionLabel('基本信息'),
            TextFormField(
              key: const Key('shift-code-field'),
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '班次代码 *',
                hintText: '例如 A1、早、OFF',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入班次代码' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('shift-name-field'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '班次名称 *',
                hintText: '例如 早班',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入班次名称' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ShiftType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '班次类型'),
              items: ShiftType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                _update(() {
                  _type = value;
                  if (_type == ShiftType.work && _reminders.isEmpty) {
                    _reminders = _defaultReminders();
                  }
                });
              },
            ),
            if (_type == ShiftType.work) ...[
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                title: const Text('到岗时间 *'),
                subtitle: Text(_arrivalTime?.format() ?? '尚未设置'),
                trailing: const Icon(Icons.schedule_rounded),
                onTap: _pickArrivalTime,
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('当天到岗'),
                    icon: Icon(Icons.today_outlined),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('次日到岗'),
                    icon: Icon(Icons.nights_stay_outlined),
                  ),
                ],
                selected: {_arrivalDayOffset},
                onSelectionChanged: (value) =>
                    _update(() => _arrivalDayOffset = value.first),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _aliasesController,
              decoration: const InputDecoration(
                labelText: '识别别名',
                hintText: '多个别名用逗号或顿号分隔',
              ),
            ),
            _SectionLabel('班次颜色'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((value) {
                final selected = value == _colorValue;
                return Semantics(
                  label: '班次颜色 ${colors.indexOf(value) + 1}',
                  selected: selected,
                  child: InkWell(
                    onTap: () => _update(() => _colorValue = value),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_type == ShiftType.work) ...[
              _SectionLabel('班次默认铃声'),
              ListTile(
                key: const Key('shift-sound-tile'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                leading: const Icon(Icons.music_note_rounded),
                title: Text(
                  soundDisplayName(
                    context.watch<SoundController>().items,
                    _defaultSoundId,
                    inheritLabel: '跟随应用默认',
                  ),
                ),
                subtitle: const Text('未单独指定铃声的提醒会使用此设置'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickDefaultSound,
              ),
              _SectionLabel('提醒规则'),
              if (_reminders.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '暂无提醒规则',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (var index = 0; index < _reminders.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReminderTile(
                    rule: _reminders[index],
                    canMoveUp: index > 0,
                    canMoveDown: index < _reminders.length - 1,
                    onEdit: () => _editReminder(
                      existing: _reminders[index],
                      index: index,
                    ),
                    onDelete: () => _update(() => _reminders.removeAt(index)),
                    onToggle: (value) => _update(
                      () => _reminders[index] = _reminders[index].copyWith(
                        isEnabled: value,
                      ),
                    ),
                    onMoveUp: () => _moveReminder(index, -1),
                    onMoveDown: () => _moveReminder(index, 1),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _editReminder,
                icon: const Icon(Icons.add_alarm_rounded),
                label: const Text('新增提醒'),
              ),
            ],
            _SectionLabel('其他'),
            TextFormField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '可选',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用此班次'),
              subtitle: const Text('停用后仍会保留数据，但不用于新的排班'),
              value: _isEnabled,
              onChanged: (value) => _update(() => _isEnabled = value),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('save-shift-button'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? '正在保存…' : '保存班次'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.rule,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ReminderRule rule;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  String get timing => rule.timeMode == ReminderTimeMode.fixed
      ? '固定 ${rule.fixedTime?.format() ?? '未设置'}'
      : '到岗前 ${rule.minutesBeforeArrival ?? 0} 分钟';

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            rule.isEnabled ? Icons.alarm_on_rounded : Icons.alarm_off_rounded,
            color: rule.isEnabled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timing,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '铃声：${soundDisplayName(context.watch<SoundController>().items, rule.soundId, inheritLabel: '跟随班次')}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Switch(value: rule.isEnabled, onChanged: onToggle),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'up') onMoveUp();
              if (value == 'down') onMoveDown();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(
                value: 'up',
                enabled: canMoveUp,
                child: const Text('上移'),
              ),
              PopupMenuItem(
                value: 'down',
                enabled: canMoveDown,
                child: const Text('下移'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ReminderEditorDialog extends StatefulWidget {
  const _ReminderEditorDialog({
    this.existing,
    required this.suggestedSortOrder,
  });
  final ReminderRule? existing;
  final int suggestedSortOrder;

  @override
  State<_ReminderEditorDialog> createState() => _ReminderEditorDialogState();
}

class _ReminderEditorDialogState extends State<_ReminderEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _minutesController;
  late final TextEditingController _snoozeController;
  late final TextEditingController _maxSnoozeController;
  late ReminderTimeMode _mode;
  ClockTime? _fixedTime;
  late bool _vibration;
  late bool _snooze;
  late bool _fade;
  late bool _fullScreen;
  late bool _enabled;
  String? _soundId;

  @override
  void initState() {
    super.initState();
    final rule = widget.existing;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _minutesController = TextEditingController(
      text: '${rule?.minutesBeforeArrival ?? 30}',
    );
    _snoozeController = TextEditingController(
      text: '${rule?.snoozeMinutes ?? 10}',
    );
    _maxSnoozeController = TextEditingController(
      text: '${rule?.maxSnoozeCount ?? 3}',
    );
    _mode = rule?.timeMode ?? ReminderTimeMode.beforeArrival;
    _fixedTime = rule?.fixedTime;
    _vibration = rule?.isVibrationEnabled ?? true;
    _snooze = rule?.isSnoozeEnabled ?? true;
    _fade = rule?.isVolumeFadeInEnabled ?? true;
    _fullScreen = rule?.isFullScreenEnabled ?? false;
    _enabled = rule?.isEnabled ?? true;
    _soundId = rule?.soundId;
  }

  Future<void> _pickTime() async {
    final initial = _fixedTime ?? const ClockTime(hour: 7, minute: 0);
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (result != null) {
      setState(
        () => _fixedTime = ClockTime(hour: result.hour, minute: result.minute),
      );
    }
  }

  Future<void> _pickSound() async {
    final result = await showSoundPickerSheet(
      context,
      title: '提醒铃声',
      selectedId: _soundId,
      inheritLabel: '跟随班次',
    );
    if (result != null && mounted) {
      setState(() => _soundId = result.soundId);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_mode == ReminderTimeMode.fixed && _fixedTime == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择固定提醒时间')));
      return;
    }
    Navigator.pop(
      context,
      ReminderRule(
        id: widget.existing?.id ?? IdGenerator.create('reminder'),
        name: _nameController.text.trim(),
        timeMode: _mode,
        fixedTime: _mode == ReminderTimeMode.fixed ? _fixedTime : null,
        minutesBeforeArrival: _mode == ReminderTimeMode.beforeArrival
            ? int.parse(_minutesController.text)
            : null,
        soundId: _soundId,
        isVibrationEnabled: _vibration,
        isSnoozeEnabled: _snooze,
        snoozeMinutes: int.parse(_snoozeController.text),
        maxSnoozeCount: int.parse(_maxSnoozeController.text),
        isVolumeFadeInEnabled: _fade,
        isFullScreenEnabled: _fullScreen,
        isEnabled: _enabled,
        sortOrder: widget.existing?.sortOrder ?? widget.suggestedSortOrder,
      ),
    );
  }

  String? _nonNegative(String? value, String emptyMessage) {
    final number = int.tryParse(value ?? '');
    if (number == null) return emptyMessage;
    if (number < 0) return '不能为负数';
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minutesController.dispose();
    _snoozeController.dispose();
    _maxSnoozeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '新增提醒' : '编辑提醒'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('reminder-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: '提醒名称 *'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入提醒名称' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReminderTimeMode>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: '时间模式'),
                items: ReminderTimeMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _mode = value ?? _mode),
              ),
              const SizedBox(height: 12),
              if (_mode == ReminderTimeMode.beforeArrival)
                TextFormField(
                  key: const Key('reminder-minutes-field'),
                  controller: _minutesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '提前分钟数 *',
                    suffixText: '分钟',
                  ),
                  validator: (value) => _nonNegative(value, '请输入提前分钟数'),
                )
              else
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  title: const Text('固定时间 *'),
                  subtitle: Text(_fixedTime?.format() ?? '尚未选择'),
                  trailing: const Icon(Icons.schedule_rounded),
                  onTap: _pickTime,
                ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('reminder-sound-tile'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('提醒铃声'),
                subtitle: Text(
                  soundDisplayName(
                    context.watch<SoundController>().items,
                    _soundId,
                    inheritLabel: '跟随班次',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickSound,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用提醒'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('振动'),
                value: _vibration,
                onChanged: (value) => setState(() => _vibration = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许贪睡'),
                value: _snooze,
                onChanged: (value) => setState(() => _snooze = value),
              ),
              if (_snooze) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _snoozeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '贪睡分钟'),
                        validator: (value) {
                          final number = int.tryParse(value ?? '');
                          if (number == null) return '请输入分钟数';
                          if (number < 1 || number > 60) return '范围 1–60';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _maxSnoozeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '最大次数'),
                        validator: (value) => _nonNegative(value, '请输入次数'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('音量渐强'),
                value: _fade,
                onChanged: (value) => setState(() => _fade = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('全屏提醒（预留）'),
                value: _fullScreen,
                onChanged: (value) => setState(() => _fullScreen = value),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('save-reminder-button'),
        onPressed: _submit,
        child: const Text('确定'),
      ),
    ],
  );
}
