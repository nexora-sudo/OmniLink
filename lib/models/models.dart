import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

String randomSecret([int bytes = 32]) => base64UrlEncode(
  List<int>.generate(bytes, (_) => Random.secure().nextInt(256)),
);

bool secretEquals(String a, String b) {
  final x = sha256.convert(utf8.encode(a)).bytes;
  final y = sha256.convert(utf8.encode(b)).bytes;
  var diff = 0;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

String checkedName(String name) {
  if (name.isEmpty ||
      name.length > 180 ||
      name.trim() != name ||
      name.endsWith('.') ||
      name == '.' ||
      name == '..' ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)',
        caseSensitive: false,
      ).hasMatch(name)) {
    throw const FormatException('Nome de arquivo inválido.');
  }
  return name;
}

void checkedId(String id) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
    throw const FormatException('Identificador inválido.');
  }
}

void checkedEndpoint(String host, int port) {
  final ip = InternetAddress.tryParse(host);
  if (ip == null ||
      ip.type != InternetAddressType.IPv4 ||
      port < 1 ||
      port > 65535) {
    throw const FormatException('Informe um IPv4 local e uma porta válida.');
  }
  final b = ip.rawAddress;
  if (!(b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 169 && b[1] == 254))) {
    throw const FormatException(
      'Somente endereços de rede local são permitidos.',
    );
  }
}

class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.token,
    this.lastSeen,
  });
  final String id, fingerprint, token;
  String name, host;
  int port;
  DateTime? lastSeen;
  String status = 'desconectado';
  Map<String, dynamic> info = {};
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'token': token,
    'lastSeen': lastSeen?.toIso8601String(),
  };
  factory Peer.fromJson(Map<String, dynamic> j) => Peer(
    id: j['id'],
    name: j['name'],
    host: j['host'],
    port: j['port'],
    fingerprint: j['fingerprint'],
    token: j['token'],
    lastSeen: DateTime.tryParse(j['lastSeen'] ?? ''),
  );
}

class Invite {
  Invite(this.host, this.port, this.fingerprint, this.secret);
  final String host, fingerprint, secret;
  final int port;
  String encode() =>
      'omnilink:${base64UrlEncode(utf8.encode(jsonEncode({'v': 1, 'host': host, 'port': port, 'fingerprint': fingerprint, 'secret': secret})))}';
  factory Invite.parse(String value) {
    if (!value.startsWith('omnilink:') || value.length > 4096) {
      throw const FormatException('Convite OmniLink inválido.');
    }
    final j = jsonDecode(utf8.decode(base64Url.decode(value.substring(9))));
    if (j['v'] != 1) {
      throw const FormatException('Versão de protocolo incompatível.');
    }
    final invite = Invite(j['host'], j['port'], j['fingerprint'], j['secret']);
    checkedEndpoint(invite.host, invite.port);
    checkedId(invite.fingerprint);
    if (invite.secret.length != 44) {
      throw const FormatException('Convite inválido.');
    }
    return invite;
  }
}

class Transfer {
  Transfer({
    required this.id,
    required this.peerId,
    required this.name,
    required this.size,
    required this.hash,
    required this.path,
    required this.incoming,
  });
  final String id, peerId, name, hash;
  final int size;
  String path;
  final bool incoming;
  int done = 0;
  String state = 'aguardando';
  String? error;
  bool cancelled = false;
  bool busy = false;
  DateTime updated = DateTime.now();
  double speed = 0;
  double get progress =>
      size == 0 ? (state == 'concluído' ? 1 : 0) : done / size;
  int? get eta => speed > 0 ? ((size - done) / speed).ceil() : null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'peerId': peerId,
    'name': name,
    'size': size,
    'hash': hash,
    'path': path,
    'incoming': incoming,
    'done': done,
    'state': state,
    'updated': updated.toIso8601String(),
    'error': error,
  };
  factory Transfer.fromJson(Map<String, dynamic> j) {
    final t = Transfer(
      id: j['id'],
      peerId: j['peerId'],
      name: j['name'],
      size: j['size'],
      hash: j['hash'],
      path: j['path'],
      incoming: j['incoming'],
    );
    t.done = j['done'];
    t.state = j['state'];
    t.error = j['error'];
    t.updated = DateTime.parse(j['updated']);
    if (t.state == 'transferindo' || t.state == 'verificando') {
      t.state = 'interrompido';
    }
    return t;
  }
}
