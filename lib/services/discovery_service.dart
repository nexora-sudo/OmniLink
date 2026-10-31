import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import '../communication/link_node.dart';
import '../models/models.dart';

class NearbyDevice {
  NearbyDevice(this.id, this.name, this.host, this.port);
  final String id, name, host;
  final int port;
}

class DiscoveryService {
  DiscoveryService(this.node);
  final LinkNode node;
  final Map<String, NearbyDevice> nearby = {};
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  Future<void> start() async {
    await stop();
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'OmniLink-${node.identity.id.substring(0, 8)}',
        type: '_omnilink._tcp',
        port: node.port,
        attributes: {'id': node.identity.id, 'name': node.name, 'v': '1'},
      ),
    );
    await _broadcast!.initialize();
    await _broadcast!.start();
    final d = BonsoirDiscovery(type: '_omnilink._tcp');
    _discovery = d;
    await d.initialize();
    _subscription = d.eventStream!.listen((event) {
      if (event is BonsoirDiscoveryServiceFoundEvent) {
        event.service.resolve(d.serviceResolver);
      } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final s = event.service;
        final id = s.attributes['id'];
        if (id == null || id == node.identity.id || s.attributes['v'] != '1') {
          return;
        }
        String? address;
        for (final host in s.hostAddresses) {
          try {
            checkedEndpoint(host, s.port);
            address = host;
            break;
          } on FormatException {
            continue;
          }
        }
        if (address == null) return;
        if (nearby.length >= 64 && !nearby.containsKey(id)) return;
        nearby[id] = NearbyDevice(
          id,
          s.attributes['name'] ?? s.name,
          address,
          s.port,
        );
        final peer = node.peers[id];
        if (peer != null && (peer.host != address || peer.port != s.port)) {
          // The endpoint is only a hint. TLS pinning still validates it.
          peer.host = address;
          peer.port = s.port;
          unawaited(node.refresh(peer));
        }
        node.changed();
      } else if (event is BonsoirDiscoveryServiceLostEvent) {
        nearby.remove(event.service.attributes['id']);
        node.changed();
      }
    }, onError: (Object e) => node.report('Descoberta mDNS: $e'));
    await d.start();
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;
    await _broadcast?.stop();
    _broadcast = null;
    nearby.clear();
  }

  static Future<List<String>> addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return interfaces.expand((i) => i.addresses).map((a) => a.address).where((
      a,
    ) {
      try {
        checkedEndpoint(a, 45832);
        return true;
      } on FormatException {
        return false;
      }
    }).toList();
  }
}
