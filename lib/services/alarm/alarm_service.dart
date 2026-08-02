abstract interface class ScheduleAlarmSyncCoordinator {
  Future<void> markPending(Iterable<DateTime> dates);
}

class PendingOnlyScheduleAlarmSyncCoordinator
    implements ScheduleAlarmSyncCoordinator {
  const PendingOnlyScheduleAlarmSyncCoordinator();

  @override
  Future<void> markPending(Iterable<DateTime> dates) async {
    // Used by isolated repository tests that do not provide an Android scheduler.
  }
}

class DelegatingScheduleAlarmSyncCoordinator
    implements ScheduleAlarmSyncCoordinator {
  ScheduleAlarmSyncCoordinator? delegate;

  @override
  Future<void> markPending(Iterable<DateTime> dates) async {
    await delegate?.markPending(dates);
  }
}
