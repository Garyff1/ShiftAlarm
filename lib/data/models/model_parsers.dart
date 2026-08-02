DateTime parseDateTime(Object? value, {DateTime? fallback}) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) {
    return DateTime.tryParse(value) ??
        fallback ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
}

int parseInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool parseBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  return fallback;
}

String? parseNullableString(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}
