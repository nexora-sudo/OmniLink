import 'package:omnilink/models/models.dart';
import 'package:omnilink/persistence/repository.dart';

/// Test fixture only. Production always uses SQLite and OS secure storage.
class MemoryRepository implements Repository {
  Future<void> Function(String key, String value)? beforeSecretWrite;
  final secrets = <String, String>{};
  final settings = <String, String>{};
  final transfers = <String, Map<String, dynamic>>{};
  final messages = <Map<String, dynamic>>[];
  @override
  Future<String?> readSecret(String key) async => secrets[key];
  @override
  Future<void> writeSecret(String key, String value) async {
    await beforeSecretWrite?.call(key, value);
    secrets[key] = value;
  }

  @override
  List<Transfer> loadTransfers() =>
      transfers.values.map(Transfer.fromJson).toList();
  @override
  void saveTransfer(Transfer t) {
    transfers[t.id] = t.toJson();
  }

  @override
  String? getSetting(String key) => settings[key];
  @override
  void setSetting(String key, String value) {
    settings[key] = value;
  }

  @override
  List<Map<String, dynamic>> texts() => messages;
  @override
  void addText(String peer, String text) =>
      messages.add({'peer': peer, 'text': text});
  @override
  void clearTexts() => messages.clear();
  @override
  void close() {}
}
