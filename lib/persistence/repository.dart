import '../models/models.dart';

abstract class Repository {
  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String value);
  List<Transfer> loadTransfers();
  void saveTransfer(Transfer transfer);
  String? getSetting(String key);
  void setSetting(String key, String value);
  List<Map<String, dynamic>> texts();
  void addText(String peer, String text);
  void clearTexts();
  void close();
}
