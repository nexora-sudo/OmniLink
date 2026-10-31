import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnilink/services/app_language.dart';
import 'package:omnilink/persistence/local_repository.dart';

void main() {
  tearDown(() => AppLanguage.load(null));

  test('English default and Portuguese selection apply immediately', () {
    AppLanguage.load(null);
    expect(tr('Arquivos', 'Files'), 'Files');
    AppLanguage.load('pt');
    expect(tr('Arquivos', 'Files'), 'Arquivos');
    AppLanguage.load('en');
    expect(tr('Arquivos', 'Files'), 'Files');
    AppLanguage.load('invalid');
    expect(AppLanguage.code, 'en');
  });

  test('language preference survives closing and reopening SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('omnilink-language-');
    final path = '${dir.path}/settings.sqlite';
    var repo = LocalRepository(path);
    try {
      for (final language in ['pt', 'en']) {
        repo.setSetting('language', language);
        repo.close();
        repo = LocalRepository(path);
        AppLanguage.load(repo.getSetting('language'));
        expect(AppLanguage.code, language);
      }
    } finally {
      repo.close();
      await dir.delete(recursive: true);
    }
  });

  test('all stored statuses have English labels without altering values', () {
    for (final entry in AppLanguage.statuses.entries) {
      AppLanguage.load('en');
      expect(statusLabel(entry.key), entry.value);
      AppLanguage.load('pt');
      expect(statusLabel(entry.key), entry.key);
    }
    expect(statusLabel('device-name.txt'), 'device-name.txt');
  });

  test('confirmation and save errors follow language and keep details', () {
    const prompt =
        'My phone (192.168.1.2) deseja se conectar.\nConfirme somente se iniciou este pareamento.';
    expect(
      AppLanguage.message(prompt),
      contains('My phone (192.168.1.2) wants to connect.'),
    );
    expect(
      AppLanguage.message('PlatformException: Arquivo não encontrado.'),
      'PlatformException: File not found.',
    );
    AppLanguage.load('pt');
    expect(AppLanguage.message(prompt), prompt);
  });
}
