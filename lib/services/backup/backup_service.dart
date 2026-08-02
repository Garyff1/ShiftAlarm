abstract interface class BackupService {
  Future<String> exportData();
  Future<void> importData(String serializedData);
}
