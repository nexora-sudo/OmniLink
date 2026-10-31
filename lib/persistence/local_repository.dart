import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import '../models/models.dart';
import 'repository.dart';

class LocalRepository implements Repository {
  LocalRepository(String path) : db = sqlite3.open(path) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS transfers (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS texts (id INTEGER PRIMARY KEY, peer TEXT, text TEXT, date TEXT)',
    );
  }
  final Database db;
  final FlutterSecureStorage secure = const FlutterSecureStorage();
  @override
  Future<String?> readSecret(String key) => secure.read(key: 'omnilink.$key');
  @override
  Future<void> writeSecret(String key, String value) =>
      secure.write(key: 'omnilink.$key', value: value);
  @override
  List<Transfer> loadTransfers() => db
      .select('SELECT data FROM transfers')
      .map((r) => Transfer.fromJson(jsonDecode(r['data'])))
      .toList();
  @override
  void saveTransfer(Transfer t) => db.execute(
    'INSERT OR REPLACE INTO transfers VALUES (?, ?)',
    [t.id, jsonEncode(t.toJson())],
  );
  @override
  String? getSetting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'];
  }

  @override
  void setSetting(String key, String value) =>
      db.execute('INSERT OR REPLACE INTO settings VALUES (?, ?)', [key, value]);
  @override
  List<Map<String, dynamic>> texts() => db
      .select('SELECT * FROM texts ORDER BY id DESC LIMIT 100')
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  @override
  void addText(String peer, String text) {
    db.execute('INSERT INTO texts(peer,text,date) VALUES (?,?,?)', [
      peer,
      text,
      DateTime.now().toIso8601String(),
    ]);
    db.execute(
      'DELETE FROM texts WHERE id NOT IN (SELECT id FROM texts ORDER BY id DESC LIMIT 100)',
    );
  }

  @override
  void clearTexts() => db.execute('DELETE FROM texts');
  @override
  void close() => db.close();
}
