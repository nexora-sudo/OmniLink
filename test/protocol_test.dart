import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnilink/communication/identity.dart';
import 'package:omnilink/communication/link_node.dart';
import 'package:omnilink/models/models.dart';
import 'support/memory_repository.dart';

void main() {
  late Identity identityA, identityB;
  late Directory temp;
  late MemoryRepository repoA, repoB;
  late LinkNode a, b;
  var allow = true;

  setUpAll(() {
    identityA = Identity.generate();
    identityB = Identity.generate();
  });
  LinkNode makeNode(Identity identity, MemoryRepository repo, String name) =>
      LinkNode(
        identity: identity,
        repository: repo,
        downloads: Directory('${temp.path}/$name'),
        name: name,
        approve: (_, _) async => allow,
        deviceInfo: () async => {
          'os': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
          'battery': null,
          'freeBytes': null,
        },
      );
  setUp(() async {
    allow = true;
    temp = await Directory.systemTemp.createTemp('omnilink-test-');
    repoA = MemoryRepository();
    repoB = MemoryRepository();
    a = makeNode(identityA, repoA, 'a');
    b = makeNode(identityB, repoB, 'b');
    await a.start(port: 0, heartbeat: false);
    await b.start(port: 0, heartbeat: false);
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await temp.delete(recursive: true);
  });
  Future<Peer> pair() => a.pair(b.createInvite('127.0.0.1'));

  test(
    'pareamento TLS estabelece credencial nos dois lados e convite é de uso único',
    () async {
      final invite = b.createInvite('127.0.0.1');
      final peer = await a.pair(Invite.parse(invite.encode()));
      expect(peer.status, 'conectado');
      expect(b.peers[a.identity.id]!.token, peer.token);
      await expectLater(a.pair(invite), throwsA(isA<LinkException>()));
    },
  );
  test('recusa de pareamento não autoriza dispositivo', () async {
    allow = false;
    await expectLater(pair(), throwsA(isA<LinkException>()));
    expect(a.peers, isEmpty);
    expect(b.peers, isEmpty);
  });
  test('segredo errado é rejeitado', () async {
    final invite = b.createInvite('127.0.0.1');
    await expectLater(
      a.pair(
        Invite(invite.host, invite.port, invite.fingerprint, randomSecret()),
      ),
      throwsA(isA<LinkException>()),
    );
    expect(b.peers, isEmpty);
  });
  test('convite expirado é rejeitado', () async {
    final invite = b.createInvite('127.0.0.1');
    b.inviteExpires = DateTime.now().subtract(const Duration(seconds: 1));
    await expectLater(a.pair(invite), throwsA(isA<LinkException>()));
  });
  test('certificado diferente é rejeitado antes do pareamento', () async {
    final invite = b.createInvite('127.0.0.1');
    await expectLater(
      a.pair(
        Invite(invite.host, invite.port, identityA.fingerprint, invite.secret),
      ),
      throwsA(isA<HandshakeException>()),
    );
    expect(b.peers, isEmpty);
  });
  test('token inválido e dispositivo removido não acessam endpoints', () async {
    final peer = await pair();
    final forged = Peer(
      id: peer.id,
      name: peer.name,
      host: peer.host,
      port: peer.port,
      fingerprint: peer.fingerprint,
      token: randomSecret(),
    );
    await expectLater(
      a.requestPeer(forged, '/v1/info'),
      throwsA(isA<LinkException>()),
    );
    await b.forget(b.peers[a.identity.id]!);
    await expectLater(
      a.requestPeer(peer, '/v1/info'),
      throwsA(isA<LinkException>()),
    );
  });
  test(
    'arquivo real multibloco é recebido com bytes e SHA-256 idênticos',
    () async {
      final peer = await pair();
      final bytes = List.generate(900000, (i) => i % 251);
      final source = await File('${temp.path}/arquivo.bin').writeAsBytes(bytes);
      final t = await a.sendFile(peer, source);
      expect(t.state, 'concluído', reason: t.error);
      final receipt = b.transfers[t.id]!;
      expect(receipt.state, 'concluído');
      expect(await File(receipt.path).readAsBytes(), bytes);
      expect(
        await LinkNode.hashFile(receipt.path),
        sha256.convert(bytes).toString(),
      );
      expect(repoA.loadTransfers().single.state, 'concluído');
    },
  );
  test('arquivo vazio é transferido e validado', () async {
    final peer = await pair();
    final file = await File('${temp.path}/vazio.txt').writeAsBytes([]);
    final t = await a.sendFile(peer, file);
    expect(t.state, 'concluído', reason: t.error);
    expect(await File(b.transfers[t.id]!.path).length(), 0);
  });
  test('recusa de recebimento não grava arquivo parcial', () async {
    final peer = await pair();
    allow = false;
    final source = await File(
      '${temp.path}/negado.txt',
    ).writeAsString('segredo');
    final t = await a.sendFile(peer, source);
    expect(t.state, 'interrompido');
    expect(b.transfers, isEmpty);
  });
  test(
    'SHA-256 divergente impede publicação e zera parcial corrompido',
    () async {
      final peer = await pair();
      final id = sha256.convert([1]).toString();
      await a.requestPeer(
        peer,
        '/v1/offer',
        json: {
          'id': id,
          'name': 'teste.txt',
          'size': 3,
          'hash': sha256.convert(utf8.encode('abc')).toString(),
        },
      );
      await a.requestPeer(
        peer,
        '/v1/chunk',
        bytes: utf8.encode('xyz'),
        headers: {'x-transfer-id': id, 'x-offset': '0'},
      );
      await expectLater(
        a.requestPeer(peer, '/v1/complete', json: {'id': id}),
        throwsA(isA<LinkException>()),
      );
      expect(b.transfers[id]!.state, 'falhou');
      expect(await File(b.transfers[id]!.path).length(), 0);
    },
  );
  test('retomada usa offset persistido após reiniciar receptor', () async {
    final peer = await pair();
    final bytes = List.generate(600000, (i) => i % 127);
    final source = await File('${temp.path}/retomar.bin').writeAsBytes(bytes);
    final hash = sha256.convert(bytes).toString();
    final id = sha256
        .convert(
          utf8.encode(
            '${a.identity.id}|${peer.id}|retomar.bin|$hash|${bytes.length}',
          ),
        )
        .toString();
    await a.requestPeer(
      peer,
      '/v1/offer',
      json: {
        'id': id,
        'name': 'retomar.bin',
        'size': bytes.length,
        'hash': hash,
      },
    );
    await a.requestPeer(
      peer,
      '/v1/chunk',
      bytes: bytes.sublist(0, LinkNode.chunkSize),
      headers: {'x-transfer-id': id, 'x-offset': '0'},
    );
    final oldPort = b.port;
    await b.close();
    b = makeNode(identityB, repoB, 'b');
    await b.start(port: oldPort, heartbeat: false);
    expect(b.transfers[id]!.done, LinkNode.chunkSize);
    final t = await a.sendFile(peer, source);
    expect(t.state, 'concluído', reason: t.error);
    expect(await File(b.transfers[id]!.path).readAsBytes(), bytes);
  });
  test(
    'cancelamento no receptor impede próximos blocos e permite excluir parcial',
    () async {
      final peer = await pair();
      final id = sha256.convert([2]).toString();
      await a.requestPeer(
        peer,
        '/v1/offer',
        json: {
          'id': id,
          'name': 'cancelar.bin',
          'size': 3,
          'hash': sha256.convert([1, 2, 3]).toString(),
        },
      );
      await a.requestPeer(
        peer,
        '/v1/chunk',
        bytes: [1],
        headers: {'x-transfer-id': id, 'x-offset': '0'},
      );
      final t = b.transfers[id]!;
      await b.cancel(t);
      await expectLater(
        a.requestPeer(
          peer,
          '/v1/chunk',
          bytes: [2],
          headers: {'x-transfer-id': id, 'x-offset': '1'},
        ),
        throwsA(isA<LinkException>()),
      );
      await b.discardPartial(t);
      expect(await File(t.path).exists(), isFalse);
      expect(t.state, 'cancelado');
    },
  );
  test('reconexão autentica novamente após falha de rede', () async {
    final peer = await pair();
    final oldPort = b.port;
    await b.close();
    await a.refresh(peer);
    expect(peer.status, 'desconectado');
    final source = await File('${temp.path}/offline.txt').writeAsString('rede');
    final t = await a.sendFile(peer, source);
    expect(t.state, 'interrompido');
    expect(t.error, isNotEmpty);
    b = makeNode(identityB, repoB, 'b');
    await b.start(port: oldPort, heartbeat: false);
    await a.poll();
    expect(peer.status, 'conectado');
    await a.resume(t);
    expect(t.state, 'concluído', reason: t.error);
  });
  test(
    'offset incorreto, caminhos perigosos e tamanho excessivo são rejeitados',
    () async {
      final peer = await pair();
      final id = sha256.convert([3]).toString();
      final offer = {
        'id': id,
        'name': '../escape',
        'size': 3,
        'hash': sha256.convert([1, 2, 3]).toString(),
      };
      await expectLater(
        a.requestPeer(peer, '/v1/offer', json: offer),
        throwsA(isA<LinkException>()),
      );
      offer['name'] = 'ok.bin';
      offer['size'] = LinkNode.maxFileSize + 1;
      await expectLater(
        a.requestPeer(peer, '/v1/offer', json: offer),
        throwsA(isA<LinkException>()),
      );
      offer['size'] = 3;
      await a.requestPeer(peer, '/v1/offer', json: offer);
      await expectLater(
        a.requestPeer(
          peer,
          '/v1/chunk',
          bytes: [1],
          headers: {'x-transfer-id': id, 'x-offset': '1'},
        ),
        throwsA(isA<LinkException>()),
      );
      expect(b.transfers[id]!.done, 0);
    },
  );
  test(
    'textos trafegam por TLS e desativar o recurso bloqueia recebimento',
    () async {
      final peer = await pair();
      final received = b.incomingTexts.first;
      await a.sendText(peer, 'Olá, Android!');
      expect((await received)['text'], 'Olá, Android!');
      expect(repoB.messages, isEmpty);
      b.clipboardEnabled = false;
      await expectLater(
        a.sendText(peer, 'não receber'),
        throwsA(isA<LinkException>()),
      );
    },
  );
  test(
    'revogação persistida não é sobrescrita por heartbeat concorrente',
    () async {
      final peer = await pair();
      final entered = Completer<void>();
      final release = Completer<void>();
      var first = true;
      repoA.beforeSecretWrite = (key, value) async {
        if (key == 'peers' && first) {
          first = false;
          entered.complete();
          await release.future;
        }
      };
      final refreshing = a.refresh(peer);
      await entered.future;
      final forgetting = a.forget(peer);
      release.complete();
      await Future.wait([refreshing, forgetting]);
      expect(jsonDecode((await repoA.readSecret('peers'))!), isEmpty);
      expect(a.peers, isEmpty);
    },
  );
  test(
    'cancelamento pelo remetente encerra envio ativo sem publicar arquivo',
    () async {
      final peer = await pair();
      final source = await File(
        '${temp.path}/cancelar-remetente.bin',
      ).writeAsBytes(List.generate(3 * 1024 * 1024, (i) => i % 251));
      Future<void>? cancellation;
      final subscription = a.changes.listen((_) {
        for (final t in a.transfers.values) {
          if (t.done >= LinkNode.chunkSize && cancellation == null) {
            cancellation = a.cancel(t);
          }
        }
      });
      try {
        final t = await a.sendFile(peer, source);
        await cancellation;
        expect(t.state, 'cancelado');
        expect(t.done, lessThan(t.size));
        expect(b.transfers[t.id]!.state, 'cancelado');
        expect(b.transfers[t.id]!.path, endsWith('.omnipart'));
      } finally {
        await subscription.cancel();
      }
    },
  );
  test('nomes Windows reservados e endereços externos não são aceitos', () {
    for (final name in [
      'CON',
      'aux.txt',
      'LPT1.txt',
      '..',
      'a/b',
      r'a\b',
      'a:stream',
      'fim.',
      ' nome',
    ]) {
      expect(() => checkedName(name), throwsFormatException);
    }
    expect(checkedName('foto férias.png'), 'foto férias.png');
    expect(() => checkedEndpoint('8.8.8.8', 443), throwsFormatException);
    expect(() => checkedEndpoint('example.com', 443), throwsFormatException);
    expect(() => Invite.parse('https://example.com'), throwsFormatException);
  });
}
