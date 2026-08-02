class BatchScheduleResult {
  const BatchScheduleResult({
    required this.savedCount,
    required this.skippedCount,
  });
  final int savedCount;
  final int skippedCount;
}

class ShiftReferenceSummary {
  const ShiftReferenceSummary({
    required this.scheduleCount,
    required this.changeLogCount,
  });
  final int scheduleCount;
  final int changeLogCount;
  int get total => scheduleCount + changeLogCount;
  bool get isReferenced => total > 0;
}
