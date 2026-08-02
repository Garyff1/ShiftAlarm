import 'model_parsers.dart';

class AlarmSound {
  const AlarmSound({
    required this.id,
    required this.displayName,
    required this.internalPath,
    required this.sourceName,
    this.sourceUri,
    required this.mimeType,
    required this.format,
    required this.fileSize,
    required this.durationMilliseconds,
    this.isSystemSound = false,
    this.isDefault = false,
    this.isAvailable = true,
    required this.checksum,
    required this.importedAt,
    this.lastVerifiedAt,
    this.failureReason,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String displayName;
  final String internalPath;
  final String sourceName;
  final String? sourceUri;
  final String mimeType;
  final String format;
  final int fileSize;
  final int durationMilliseconds;
  final bool isSystemSound;
  final bool isDefault;
  final bool isAvailable;
  final String checksum;
  final DateTime importedAt;
  final DateTime? lastVerifiedAt;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  AlarmSound copyWith({
    String? displayName,
    String? internalPath,
    String? sourceName,
    String? sourceUri,
    String? mimeType,
    String? format,
    int? fileSize,
    int? durationMilliseconds,
    bool? isDefault,
    bool? isAvailable,
    String? checksum,
    DateTime? lastVerifiedAt,
    String? failureReason,
    bool clearFailureReason = false,
    DateTime? updatedAt,
  }) => AlarmSound(
    id: id,
    displayName: displayName ?? this.displayName,
    internalPath: internalPath ?? this.internalPath,
    sourceName: sourceName ?? this.sourceName,
    sourceUri: sourceUri ?? this.sourceUri,
    mimeType: mimeType ?? this.mimeType,
    format: format ?? this.format,
    fileSize: fileSize ?? this.fileSize,
    durationMilliseconds: durationMilliseconds ?? this.durationMilliseconds,
    isSystemSound: isSystemSound,
    isDefault: isDefault ?? this.isDefault,
    isAvailable: isAvailable ?? this.isAvailable,
    checksum: checksum ?? this.checksum,
    importedAt: importedAt,
    lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    failureReason: clearFailureReason
        ? null
        : failureReason ?? this.failureReason,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'displayName': displayName,
    'internalPath': internalPath,
    'sourceName': sourceName,
    'sourceUri': sourceUri,
    'mimeType': mimeType,
    'format': format,
    'fileSize': fileSize,
    'durationMilliseconds': durationMilliseconds,
    'isSystemSound': isSystemSound,
    'isDefault': isDefault,
    'isAvailable': isAvailable,
    'checksum': checksum,
    'importedAt': importedAt.millisecondsSinceEpoch,
    'lastVerifiedAt': lastVerifiedAt?.millisecondsSinceEpoch,
    'failureReason': failureReason,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory AlarmSound.fromMap(Map<String, Object?> map) => AlarmSound(
    id: map['id']?.toString() ?? '',
    displayName: map['displayName']?.toString() ?? '',
    internalPath: map['internalPath']?.toString() ?? '',
    sourceName: map['sourceName']?.toString() ?? '',
    sourceUri: parseNullableString(map['sourceUri']),
    mimeType: map['mimeType']?.toString() ?? 'audio/*',
    format: map['format']?.toString() ?? '',
    fileSize: parseInt(map['fileSize']),
    durationMilliseconds: parseInt(map['durationMilliseconds']),
    isSystemSound: parseBool(map['isSystemSound']),
    isDefault: parseBool(map['isDefault']),
    isAvailable: parseBool(map['isAvailable'], fallback: true),
    checksum: map['checksum']?.toString() ?? '',
    importedAt: map['importedAt'] == null
        ? parseDateTime(map['createdAt'])
        : parseDateTime(map['importedAt']),
    lastVerifiedAt: map['lastVerifiedAt'] == null
        ? null
        : parseDateTime(map['lastVerifiedAt']),
    failureReason: parseNullableString(map['failureReason']),
    createdAt: parseDateTime(map['createdAt']),
    updatedAt: map['updatedAt'] == null
        ? parseDateTime(map['createdAt'])
        : parseDateTime(map['updatedAt']),
  );
}
