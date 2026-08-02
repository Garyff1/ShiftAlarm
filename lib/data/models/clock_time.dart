import 'model_parsers.dart';

class ClockTime implements Comparable<ClockTime> {
  const ClockTime({required this.hour, required this.minute})
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  final int hour;
  final int minute;

  int get totalMinutes => hour * 60 + minute;

  Map<String, Object> toMap() => {'hour': hour, 'minute': minute};

  static ClockTime? fromMap(Object? value) {
    if (value is! Map) return null;
    final hour = parseInt(value['hour'], fallback: -1);
    final minute = parseInt(value['minute'], fallback: -1);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return ClockTime(hour: hour, minute: minute);
  }

  String format({bool use24Hour = true}) {
    if (use24Hour) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }
    final suffix = hour < 12 ? '上午' : '下午';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$suffix $displayHour:${minute.toString().padLeft(2, '0')}';
  }

  @override
  int compareTo(ClockTime other) => totalMinutes.compareTo(other.totalMinutes);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && hour == other.hour && minute == other.minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}
