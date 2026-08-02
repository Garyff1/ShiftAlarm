import 'app_enums.dart';
import 'model_parsers.dart';

class ScheduleChangeLog {
  const ScheduleChangeLog({
    required this.id,
    required this.date,
    this.originalShiftTemplateId,
    this.newShiftTemplateId,
    this.relatedDate,
    this.batchOperationId,
    this.originalShiftCode,
    this.originalShiftName,
    this.newShiftCode,
    this.newShiftName,
    required this.changeType,
    this.reason = '',
    required this.createdAt,
  });

  final String id;
  final DateTime date;
  final String? originalShiftTemplateId;
  final String? newShiftTemplateId;
  final DateTime? relatedDate;
  final String? batchOperationId;
  final String? originalShiftCode;
  final String? originalShiftName;
  final String? newShiftCode;
  final String? newShiftName;
  final ScheduleChangeType changeType;
  final String reason;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'date': DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
    'dateKey':
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'originalShiftTemplateId': originalShiftTemplateId,
    'newShiftTemplateId': newShiftTemplateId,
    'relatedDate': relatedDate == null
        ? null
        : DateTime(
            relatedDate!.year,
            relatedDate!.month,
            relatedDate!.day,
          ).millisecondsSinceEpoch,
    'batchOperationId': batchOperationId,
    'originalShiftCode': originalShiftCode,
    'originalShiftName': originalShiftName,
    'newShiftCode': newShiftCode,
    'newShiftName': newShiftName,
    'changeType': changeType.storageValue,
    'reason': reason,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory ScheduleChangeLog.fromMap(Map<String, Object?> map) =>
      ScheduleChangeLog(
        id: map['id']?.toString() ?? '',
        date: parseDateTime(map['date']),
        originalShiftTemplateId: parseNullableString(
          map['originalShiftTemplateId'],
        ),
        newShiftTemplateId: parseNullableString(map['newShiftTemplateId']),
        relatedDate: map['relatedDate'] == null
            ? null
            : parseDateTime(map['relatedDate']),
        batchOperationId: parseNullableString(map['batchOperationId']),
        originalShiftCode: parseNullableString(map['originalShiftCode']),
        originalShiftName: parseNullableString(map['originalShiftName']),
        newShiftCode: parseNullableString(map['newShiftCode']),
        newShiftName: parseNullableString(map['newShiftName']),
        changeType: ScheduleChangeType.fromStorage(map['changeType']),
        reason: map['reason']?.toString() ?? '',
        createdAt: parseDateTime(map['createdAt']),
      );
}
