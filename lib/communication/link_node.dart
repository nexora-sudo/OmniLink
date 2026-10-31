import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../persistence/repository.dart';
import 'identity.dart';

class LinkException implements Exception {
  LinkException(this.message, [this.status = 400]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

typedef Approval = Future<bool> Function(String title, String message);

/// HTTPS is a framed TCP/TLS transport. No clear-text endpoints are exposed.
class LinkNode {
  LinkNode({
    required this.identity,
    required this.repository,
    required this.downloads,
    required this.name,
    required this.approve,
    required this.deviceInfo,
  });
  final Identity identity;
  final Repository repository;
  final Approval approve;
  final Future<Map<String, dynamic>> Function() deviceInfo;
  Directory downloads;
  String name;
  HttpServer? _server;
  Timer? _heartbeat;
  final Map<String, Peer> peers = {};
  final Map<String, Transfer> transfers = {};
  final _events = StreamController<void>.broadcast();
  Stream<void> get changes => _events.stream;
  final _texts = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get incomingTexts => _texts.stream;
  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;
  String? _inviteSecret;
  DateTime? inviteExpires;
  bool _pairBusy = false;
  bool _offerBusy = false;
  bool _polling = false;
  bool _closed = false;
  Future<void> _peerWrite = Future<void>.value();
  bool clipboardEnabled = true;
  bool textHistory = false;
  static const maxFileSize = 4 * 1024 * 1024 * 1024;
  static const chunkSize = 256 * 1024;
  int get port => _server?.port ?? 0;
  final Map<String, HttpClient> _activeClients = {};
  final Map<String, DateTime> _textRate = {};
  final Map<String, List<DateTime>> _pairAttempts = {};
  void changed() {
    if (!_closed) _events.add(null);
  }

  void report(Object error) {
    if (!_closed) _errors.add(error.toString());
  }

  Future<void> start({int port = 45832, bool heartbeat = true}) async {
    await downloads.create(recursive: true);
    final saved = await repository.readSecret('peers');
    if (saved != null) {
      for (final j in jsonDecode(saved) as List) {
        final peer = Peer.fromJson(j);
        peers[peer.id] = peer;
      }
    }
    for (final transfer in repository.loadTransfers()) {
      transfers[transfer.id] = transfer;
    }
    _server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      port,
      identity.context,
    );
    _server!.idleTimeout = const Duration(seconds: 15);
    _server!.listen((request) {
      unawaited(_handle(request));
    }, onError: report);
    if (heartbeat) {
      _heartbeat = Timer.periodic(
        const Duration(seconds: 8),
        (_) => unawaited(poll()),
      );
      unawaited(poll());
    }
    changed();
  }

  Future<void> _savePeers() {
    // Serialize writes so an earlier heartbeat cannot finish after a revocation
    // and restore an old credential on the next application launch.
    final write = _peerWrite.then(
      (_) => repository.writeSecret(
        'peers',
        jsonEncode(peers.values.map((peer) => peer.toJson()).toList()),
      ),
    );
    _peerWrite = write.catchError((Object error) {
      report('Não foi possível persistir dispositivos: $error');
    });
    return write;
  }

  Invite createInvite(String host) {
    checkedEndpoint(host, port);
    _inviteSecret = randomSecret();
    inviteExpires = DateTime.now().add(const Duration(minutes: 5));
    return Invite(host, port, identity.fingerprint, _inviteSecret!);
  }

  void revokeInvite() {
    _inviteSecret = null;
    inviteExpires = null;
  }

  HttpClient _client(String fingerprint) {
    checkedId(fingerprint);
    // An empty trust store ensures even a publicly trusted certificate must
    // pass our pin callback. A successful handshake alone is not enough.
    return HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (cert, host, port) =>
          secretEquals(sha256.convert(cert.der).toString(), fingerprint);
  }

  Future<Map<String, dynamic>> _request({
    required String host,
    required int port,
    required String fingerprint,
    required String route,
    String method = 'POST',
    String? token,
    Object? json,
    List<int>? bytes,
    Map<String, String>? headers,
    HttpClient? client,
  }) async {
    checkedEndpoint(host, port);
    final http = client ?? _client(fingerprint);
    try {
      final req = await http
          .openUrl(
            method,
            Uri(scheme: 'https', host: host, port: port, path: route),
          )
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.set('x-omni-id', identity.id);
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      headers?.forEach(req.headers.set);
      final body = bytes ?? utf8.encode(jsonEncode(json ?? {}));
      req.headers.contentType = bytes == null
          ? ContentType.json
          : ContentType.binary;
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 75));
      // Check pin again, including TLS session reuse.
      final cert = res.certificate;
      if (cert == null ||
          !secretEquals(sha256.convert(cert.der).toString(), fingerprint)) {
        throw LinkException('Certificado remoto divergente.', 401);
      }
      final data = await _readJson(res, 128 * 1024);
      if (res.statusCode != 200) {
        throw LinkException(
          data['error'] as String? ?? 'Falha remota.',
          res.statusCode,
        );
      }
      return data;
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  Future<Map<String, dynamic>> requestPeer(
    Peer peer,
    String route, {
    Object? json,
    List<int>? bytes,
    Map<String, String>? headers,
    HttpClient? client,
  }) => _request(
    host: peer.host,
    port: peer.port,
    fingerprint: peer.fingerprint,
    route: route,
    token: peer.token,
    json: json,
    bytes: bytes,
    headers: headers,
    client: client,
  );

  Future<Peer> pair(Invite invite) async {
    final j = await _request(
      host: invite.host,
      port: invite.port,
      fingerprint: invite.fingerprint,
      route: '/v1/pair',
      json: {
        'secret': invite.secret,
        'id': identity.id,
        'name': name,
        'fingerprint': identity.fingerprint,
        'port': port,
      },
    );
    if (j['id'] != invite.fingerprint ||
        j['token'] is! String ||
        (j['token'] as String).length != 44) {
      throw LinkException('Resposta de pareamento inválida.');
    }
    final peer = Peer(
      id: j['id'],
      name: j['name'],
      host: invite.host,
      port: invite.port,
      fingerprint: invite.fingerprint,
      token: j['token'],
    );
    peers[peer.id] = peer;
    await _savePeers();
    await refresh(peer);
    changed();
    return peer;
  }

  Future<void> forget(Peer peer) async {
    peers.remove(
      peer.id,
    ); // Authorization is revoked before persistence awaits.
    for (final t in transfers.values.where((t) => t.peerId == peer.id)) {
      if (t.busy || t.state == 'transferindo') {
        t.cancelled = true;
        _activeClients[t.id]?.close(force: true);
      }
    }
    await _savePeers();
    changed();
  }

  Future<void> refresh(Peer peer) async {
    peer.status = 'conectando';
    changed();
    try {
      final j = await requestPeer(peer, '/v1/info');
      peer.info = j;
      peer.name = j['name'] as String;
      peer.lastSeen = DateTime.now();
      peer.status = 'conectado';
      await _savePeers();
    } catch (_) {
      peer.status = 'desconectado';
    }
    changed();
  }

  Future<void> poll() async {
    if (_polling || _closed) return;
    _polling = true;
    try {
      await Future.wait(peers.values.toList().map(refresh));
    } finally {
      _polling = false;
    }
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      if (r.method != 'POST') throw LinkException('Método inválido.', 405);
      if (r.uri.path == '/v1/pair') {
        await _acceptPair(r);
        return;
      }
      final id = r.headers.value('x-omni-id');
      final peer = peers[id];
      final auth = r.headers.value(HttpHeaders.authorizationHeader) ?? '';
      if (peer == null || !secretEquals(auth, 'Bearer ${peer.token}')) {
        throw LinkException('Dispositivo não autorizado.', 401);
      }
      peer.lastSeen = DateTime.now();
      switch (r.uri.path) {
        case '/v1/info':
          await _readJson(r, 1024);
          await _reply(r, {
            'id': identity.id,
            'name': name,
            ...await deviceInfo(),
          });
        case '/v1/offer':
          await _offer(r, peer);
        case '/v1/chunk':
          await _chunk(r, peer);
        case '/v1/complete':
          await _complete(r, peer);
        case '/v1/cancel':
          final j = await _readJson(r, 1024);
          final t = _owned(j['id'], peer);
          t.cancelled = true;
          t.state = 'cancelado';
          _save(t);
          await _reply(r, {'ok': true});
        case '/v1/text':
          if (!clipboardEnabled) {
            throw LinkException('Compartilhamento de textos desativado.', 403);
          }
          final now = DateTime.now();
          if (now
                  .difference(_textRate[peer.id] ?? DateTime(2000))
                  .inMilliseconds <
              500) {
            throw LinkException('Aguarde antes de enviar outro texto.', 429);
          }
          final j = await _readJson(r, 80 * 1024);
          final text = j['text'];
          if (text is! String || utf8.encode(text).length > 64 * 1024) {
            throw LinkException('Texto muito grande.');
          }
          _textRate[peer.id] = now;
          if (textHistory) repository.addText(peer.name, text);
          _texts.add({'peer': peer.name, 'text': text});
          changed();
          await _reply(r, {'ok': true});
        default:
          throw LinkException('Rota inexistente.', 404);
      }
    } catch (e) {
      final code = e is LinkException
          ? e.status
          : e is FormatException
          ? 400
          : 500;
      if (code == 500) report('Falha ao atender solicitação: $e');
      try {
        await _reply(r, {
          'error': code == 500 ? 'Falha de E/S no receptor.' : e.toString(),
        }, code);
      } catch (_) {
        /* The remote may have cancelled the TLS socket. */
      }
    }
  }

  Future<void> _acceptPair(HttpRequest r) async {
    final address = r.connectionInfo!.remoteAddress.address;
    final now = DateTime.now();
    _pairAttempts.removeWhere(
      (_, times) => times.every((t) => now.difference(t).inMinutes >= 1),
    );
    if (_pairAttempts.length >= 128 && !_pairAttempts.containsKey(address)) {
      throw LinkException('Limite de solicitações.', 429);
    }
    final attempts = _pairAttempts.putIfAbsent(address, () => []);
    attempts.removeWhere((t) => now.difference(t).inMinutes >= 1);
    if (attempts.length >= 5) {
      throw LinkException('Muitas tentativas. Aguarde um minuto.', 429);
    }
    attempts.add(now);
    if (_pairBusy ||
        _inviteSecret == null ||
        inviteExpires == null ||
        now.isAfter(inviteExpires!)) {
      throw LinkException('Gere um novo convite no receptor.', 403);
    }
    final j = await _readJson(r, 4096);
    if (j['secret'] is! String || !secretEquals(j['secret'], _inviteSecret!)) {
      throw LinkException('Convite inválido.', 403);
    }
    checkedId(j['id']);
    checkedId(j['fingerprint']);
    if (j['id'] != j['fingerprint'] ||
        j['id'] == identity.id ||
        j['name'] is! String ||
        (j['name'] as String).length > 80) {
      throw LinkException('Identidade inválida.');
    }
    checkedEndpoint(address, j['port']);
    _pairBusy = true;
    revokeInvite(); // Single use, even when the user declines.
    try {
      if (!await approve(
        'Parear dispositivo?',
        '${j['name']} ($address) deseja se conectar.\nConfirme somente se iniciou este pareamento.',
      ).timeout(const Duration(seconds: 60), onTimeout: () => false)) {
        throw LinkException('Pareamento recusado.', 403);
      }
      final peer = Peer(
        id: j['id'],
        name: j['name'],
        host: address,
        port: j['port'],
        fingerprint: j['fingerprint'],
        token: randomSecret(),
      );
      peers[peer.id] = peer;
      await _savePeers();
      changed();
      await _reply(r, {'id': identity.id, 'name': name, 'token': peer.token});
    } finally {
      _pairBusy = false;
    }
  }

  Transfer _owned(dynamic id, Peer peer) {
    final t = transfers[id];
    if (t == null || !t.incoming || t.peerId != peer.id) {
      throw LinkException('Transferência não encontrada.', 404);
    }
    return t;
  }

  Future<void> _offer(HttpRequest r, Peer peer) async {
    if (_offerBusy) {
      throw LinkException('Outra confirmação está em andamento.', 409);
    }
    _offerBusy = true;
    try {
      final j = await _readJson(r, 4096);
      checkedId(j['id']);
      checkedId(j['hash']);
      checkedName(j['name']);
      if (j['size'] is! int || j['size'] < 0 || j['size'] > maxFileSize) {
        throw LinkException('Limite de 4 GiB por arquivo.', 413);
      }
      var t = transfers[j['id']];
      if (t != null) {
        t = _owned(j['id'], peer);
        if (t.hash != j['hash'] || t.size != j['size'] || t.name != j['name']) {
          throw LinkException('Metadados divergentes.', 409);
        }
        if (t.busy) throw LinkException('Transferência ocupada.', 409);
        if (t.state == 'concluído') {
          if (!await File(t.path).exists() ||
              await hashFile(t.path) != t.hash) {
            throw LinkException(
              'Arquivo final ausente ou alterado. Inicie um novo envio.',
              409,
            );
          }
          await _reply(r, {'offset': t.size, 'complete': true});
          return;
        }
      }
      final active = transfers.values
          .where(
            (x) =>
                x.incoming && x.state != 'concluído' && x.state != 'cancelado',
          )
          .length;
      if (t == null && active >= 16) {
        throw LinkException('Limite de transferências pendentes.', 429);
      }
      if (!await approve(
        'Receber arquivo?',
        '${peer.name} quer enviar ${j['name']}\n${(j['size'] / 1048576).toStringAsFixed(2)} MiB',
      ).timeout(const Duration(seconds: 60), onTimeout: () => false)) {
        throw LinkException('Arquivo recusado.', 403);
      }
      if (!peers.containsKey(peer.id)) {
        throw LinkException('Dispositivo removido.', 401);
      }
      t ??= Transfer(
        id: j['id'],
        peerId: peer.id,
        name: j['name'],
        size: j['size'],
        hash: j['hash'],
        path: p.join(downloads.path, '.${j['id']}.omnipart'),
        incoming: true,
      );
      final file = File(t.path);
      if (await FileSystemEntity.isLink(file.path)) {
        throw LinkException('Destino inválido.');
      }
      if (!await file.exists()) await file.create();
      t.done = await file.length();
      if (t.done > t.size) {
        await file.writeAsBytes([]);
        t.done = 0;
      }
      t.cancelled = false;
      t.state = 'transferindo';
      t.error = null;
      transfers[t.id] = t;
      _save(t);
      await _reply(r, {'offset': t.done, 'complete': false});
    } finally {
      _offerBusy = false;
    }
  }

  Future<void> _chunk(HttpRequest r, Peer peer) async {
    final t = _owned(r.headers.value('x-transfer-id'), peer);
    if (t.cancelled || t.state != 'transferindo') {
      throw LinkException('Transferência inativa.', 409);
    }
    if (t.busy) throw LinkException('Transferência ocupada.', 409);
    final offset = int.tryParse(r.headers.value('x-offset') ?? '');
    if (offset != t.done) {
      throw LinkException('Offset divergente. Retome o envio.', 409);
    }
    if (r.contentLength < 1 ||
        r.contentLength > chunkSize ||
        t.done + r.contentLength > t.size) {
      throw LinkException('Bloco inválido.', 413);
    }
    t.busy = true;
    final watch = Stopwatch()..start();
    try {
      final bytes = await _readBytes(r, chunkSize);
      if (bytes.length != r.contentLength ||
          t.cancelled ||
          !peers.containsKey(peer.id)) {
        throw LinkException('Envio cancelado.', 409);
      }
      final f = await File(t.path).open(mode: FileMode.append);
      try {
        if (await f.length() != offset) {
          throw LinkException('Arquivo parcial alterado.', 409);
        }
        await f.writeFrom(bytes);
        await f.flush();
      } finally {
        await f.close();
      }
      t.done += bytes.length;
      t.speed = bytes.length / max(watch.elapsedMicroseconds / 1000000, 0.001);
      _save(t);
      await _reply(r, {'offset': t.done});
    } finally {
      t.busy = false;
    }
  }

  Future<void> _complete(HttpRequest r, Peer peer) async {
    final j = await _readJson(r, 1024);
    final t = _owned(j['id'], peer);
    if (t.state == 'concluído') {
      await _reply(r, {'ok': true});
      return;
    }
    if (t.busy ||
        t.cancelled ||
        t.done != t.size ||
        t.state != 'transferindo') {
      throw LinkException('Transferência incompleta.', 409);
    }
    t.busy = true;
    t.state = 'verificando';
    changed();
    try {
      if (await hashFile(t.path) != t.hash) {
        t.state = 'falhou';
        t.error = 'SHA-256 divergente. O arquivo não foi aceito.';
        await File(t.path).writeAsBytes([]);
        t.done = 0;
        _save(t);
        throw LinkException(t.error!, 422);
      }
      if (t.cancelled || !peers.containsKey(peer.id)) {
        throw LinkException('Transferência cancelada.', 409);
      }
      // Each receipt has its own directory; never overwrite a user's file.
      final receipt = Directory(p.join(p.dirname(t.path), 'OmniLink-${t.id}'));
      if (await receipt.exists() ||
          await FileSystemEntity.isLink(receipt.path)) {
        throw LinkException('Destino já existe.', 409);
      }
      await receipt.create();
      final target = p.join(receipt.path, checkedName(t.name));
      await File(t.path).rename(target);
      t.path = target;
      t.state = 'concluído';
      t.speed = 0;
      _save(t);
      await _reply(r, {'ok': true});
    } finally {
      t.busy = false;
    }
  }

  static Future<String> hashFile(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
  void _save(Transfer t) {
    t.updated = DateTime.now();
    repository.saveTransfer(t);
    changed();
  }

  Future<Transfer> sendFile(Peer peer, File file) async {
    final name = checkedName(p.basename(file.path));
    final size = await file.length();
    if (size > maxFileSize) throw LinkException('Limite de 4 GiB por arquivo.');
    final hash = await hashFile(file.path);
    final id = sha256
        .convert(utf8.encode('${identity.id}|${peer.id}|$name|$hash|$size'))
        .toString();
    var t = transfers[id];
    if (t?.busy == true) {
      throw LinkException('Este arquivo já está sendo enviado.');
    }
    t ??= Transfer(
      id: id,
      peerId: peer.id,
      name: name,
      size: size,
      hash: hash,
      path: file.path,
      incoming: false,
    );
    t.path = file.path;
    transfers[id] = t;
    await resume(t);
    return t;
  }

  Future<void> resume(Transfer t) async {
    if (t.incoming || t.busy) {
      throw LinkException('Retome pelo dispositivo remetente.');
    }
    final peer = peers[t.peerId];
    if (peer == null) throw LinkException('Dispositivo não pareado.');
    t.busy = true;
    t.cancelled = false;
    t.error = null;
    t.state = 'verificando';
    _save(t);
    final client = _client(peer.fingerprint);
    _activeClients[t.id] = client;
    try {
      if (await File(t.path).length() != t.size ||
          await hashFile(t.path) != t.hash) {
        throw LinkException(
          'Arquivo de origem foi alterado. Selecione-o novamente.',
        );
      }
      if (t.cancelled) throw LinkException('Cancelado.');
      t.state = 'aguardando';
      changed();
      final offer = await requestPeer(
        peer,
        '/v1/offer',
        json: {'id': t.id, 'name': t.name, 'size': t.size, 'hash': t.hash},
        client: client,
      );
      final offset = offer['offset'];
      if (offset is! int || offset < 0 || offset > t.size) {
        throw LinkException('Offset inválido.');
      }
      t.done = offset;
      t.state = 'transferindo';
      _save(t);
      final file = await File(t.path).open();
      final watch = Stopwatch()..start();
      final initial = t.done;
      try {
        await file.setPosition(t.done);
        while (t.done < t.size) {
          if (t.cancelled || !peers.containsKey(peer.id)) {
            throw LinkException('Cancelado.');
          }
          final bytes = await file.read(min(chunkSize, t.size - t.done));
          if (bytes.isEmpty) throw LinkException('Arquivo de origem truncado.');
          final reply = await requestPeer(
            peer,
            '/v1/chunk',
            bytes: bytes,
            client: client,
            headers: {'x-transfer-id': t.id, 'x-offset': '${t.done}'},
          );
          if (reply['offset'] != t.done + bytes.length) {
            throw LinkException('Confirmação de bloco inválida.');
          }
          t.done += bytes.length;
          t.speed =
              (t.done - initial) /
              max(watch.elapsedMicroseconds / 1000000, 0.001);
          _save(t);
        }
      } finally {
        await file.close();
      }
      if (t.cancelled) throw LinkException('Cancelado.');
      t.state = 'verificando';
      changed();
      await requestPeer(
        peer,
        '/v1/complete',
        json: {'id': t.id},
        client: client,
      );
      t.state = 'concluído';
      t.speed = 0;
      _save(t);
    } catch (e) {
      t.state = t.cancelled ? 'cancelado' : 'interrompido';
      t.error = t.cancelled ? null : e.toString();
      t.speed = 0;
      _save(t);
    } finally {
      client.close(force: true);
      _activeClients.remove(t.id);
      t.busy = false;
      changed();
    }
  }

  Future<void> cancel(Transfer t) async {
    t.cancelled = true;
    t.state = 'cancelado';
    _activeClients[t.id]?.close(force: true);
    _save(t);
    final peer = peers[t.peerId];
    if (!t.incoming && peer != null) {
      try {
        await requestPeer(peer, '/v1/cancel', json: {'id': t.id});
      } catch (e) {
        report('Cancelado localmente; receptor inacessível: $e');
      }
    }
  }

  Future<void> discardPartial(Transfer t) async {
    if (!t.incoming || t.busy || t.state == 'concluído') {
      throw LinkException('Arquivo não é um parcial inativo.');
    }
    t.cancelled = true;
    if (await File(t.path).exists()) await File(t.path).delete();
    t.done = 0;
    t.state = 'cancelado';
    _save(t);
  }

  Future<void> sendText(Peer peer, String text) async {
    if (!clipboardEnabled) {
      throw LinkException('Compartilhamento de textos desativado.');
    }
    if (utf8.encode(text).length > 64 * 1024) {
      throw LinkException('Limite de 64 KiB por texto.');
    }
    await requestPeer(peer, '/v1/text', json: {'text': text});
    if (textHistory) repository.addText('Você → ${peer.name}', text);
    changed();
  }

  static Future<List<int>> _readBytes(
    Stream<List<int>> stream,
    int limit,
  ) async {
    final result = <int>[];
    await for (final bytes in stream.timeout(const Duration(seconds: 15))) {
      if (result.length + bytes.length > limit) {
        throw LinkException('Solicitação muito grande.', 413);
      }
      result.addAll(bytes);
    }
    return result;
  }

  static Future<Map<String, dynamic>> _readJson(
    Stream<List<int>> stream,
    int limit,
  ) async {
    final value = jsonDecode(utf8.decode(await _readBytes(stream, limit)));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('JSON inválido.');
    }
    return value;
  }

  static Future<void> _reply(
    HttpRequest r,
    Map<String, dynamic> body, [
    int status = 200,
  ]) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.headers.set('cache-control', 'no-store');
    r.response.write(jsonEncode(body));
    await r.response.close();
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    _closed = true;
    for (final c in _activeClients.values) {
      c.close(force: true);
    }
    await _server?.close(force: true);
    await _events.close();
    await _texts.close();
    await _errors.close();
  }
}
