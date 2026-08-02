import 'package:flutter/material.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/shift_template.dart';

Future<ShiftTemplate?> showShiftPicker(
  BuildContext context, {
  required Iterable<ShiftTemplate> shifts,
  ShiftType? initialFilter,
}) => showModalBottomSheet<ShiftTemplate>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ShiftPickerSheet(
    shifts: shifts.where((item) => item.isEnabled).toList(),
    initialFilter: initialFilter,
  ),
);

class _ShiftPickerSheet extends StatefulWidget {
  const _ShiftPickerSheet({required this.shifts, this.initialFilter});
  final List<ShiftTemplate> shifts;
  final ShiftType? initialFilter;

  @override
  State<_ShiftPickerSheet> createState() => _ShiftPickerSheetState();
}

class _ShiftPickerSheetState extends State<_ShiftPickerSheet> {
  ShiftType? filter;

  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final visible = filter == null
        ? widget.shifts
        : widget.shifts.where((item) => item.type == filter).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                '选择班次',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: filter == null,
                    onSelected: (_) => setState(() => filter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final type in [
                    ShiftType.work,
                    ShiftType.rest,
                    ShiftType.leave,
                  ]) ...[
                    ChoiceChip(
                      label: Text(type.label),
                      selected: filter == type,
                      onSelected: (_) => setState(() => filter = type),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        filter == null ? '暂无可用班次' : '暂无${filter!.label}班次',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final shift = visible[index];
                        final color = Color(shift.colorValue);
                        return Card(
                          child: ListTile(
                            onTap: () => Navigator.pop(context, shift),
                            leading: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                shift.code,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(
                              shift.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${shift.type.label} · ${shift.arrivalTime?.format() ?? '无需到岗'}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
