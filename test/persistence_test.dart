import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnilink/models/models.dart';
import 'package:omnilink/persistence/local_repository.dart';

void main() {
  test(
    'SQLite persiste transferências, ajustes e histórico e recupera estado interrompido',
    () async {
      final directory = await Directory.systemTemp.createTemp('omnilink-db-');
      final path = '${directory.path}/history.sqlite';
      var repository = LocalRepository(path);
      try {
        repository.setSetting('name', 'Computador do João');
        final t =
            Transfer(
                id: 'id',
                peerId: 'peer',
                name: 'férias.txt',
                size: 4,
                hash: 'hash',
                path: 'local',
                incoming: true,
              )
              ..done = 2
              ..state = 'transferindo';
        repository.saveTransfer(t);
        repository.addText('Android', 'Olá!');
        repository.close();
        repository = LocalRepository(path);
        expect(repository.getSetting('name'), 'Computador do João');
        expect(repository.loadTransfers().single.done, 2);
        expect(repository.loadTransfers().single.state, 'interrompido');
        expect(repository.texts().single['text'], 'Olá!');
        for (var i = 0; i < 110; i++) {
          repository.addText('peer', '$i');
        }
        expect(repository.texts().length, 100);
        repository.clearTexts();
        expect(repository.texts(), isEmpty);
      } finally {
        repository.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
