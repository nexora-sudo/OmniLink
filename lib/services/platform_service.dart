import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'discovery_service.dart';

class PlatformService {
  static const channel = MethodChannel('org.omnilink/platform');
  static Future<Map<String, dynamic>> info(String destination) async {
    int? battery, free;
    try {
      battery = await Battery().batteryLevel;
    } on Exception {
      battery = null;
    }
    try {
      free = await channel.invokeMethod<int>('freeBytes', {
        'path': destination,
      });
    } on PlatformException {
      free = null;
    } on MissingPluginException {
      free = null;
    }
    return {
      'os': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'ip': await DiscoveryService.addresses(),
      'battery': battery,
      'freeBytes': free,
    };
  }

  static Future<bool> startupEnabled() async {
    if (!Platform.isWindows) return false;
    final r = await Process.run('reg.exe', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
      '/v',
      'OmniLink',
    ]);
    return r.exitCode == 0;
  }

  static Future<void> setStartup(bool enabled) async {
    if (!Platform.isWindows) return;
    final args = enabled
        ? [
            'add',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
            '/v',
            'OmniLink',
            '/t',
            'REG_SZ',
            '/d',
            '"${Platform.resolvedExecutable}"',
            '/f',
          ]
        : [
            'delete',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
            '/v',
            'OmniLink',
            '/f',
          ];
    final r = await Process.run('reg.exe', args);
    if (r.exitCode != 0) {
      throw FileSystemException(
        'Não foi possível alterar a inicialização: ${r.stderr}',
      );
    }
  }

  static Future<void> exportFile(String path) async {
    await channel.invokeMethod<void>('exportFile', {'path': path});
  }
}
