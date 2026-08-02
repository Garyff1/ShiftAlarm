abstract interface class AudioService {
  /// Reserved for a later phase; no audio is imported or played in phase one.
  Future<void> importSound();
}
