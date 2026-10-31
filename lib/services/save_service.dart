import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'platform_service.dart';

class SaveService {
  static bool isGalleryMedia(String path) => const {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.heic',
    '.heif',
    '.bmp',
    '.mp4',
    '.m4v',
    '.mov',
    '.webm',
    '.3gp',
    '.mkv',
  }.contains(p.extension(path).toLowerCase());

  static Future<String> save(String path, {required bool gallery}) async {
    if (Platform.isAndroid) {
      return (await PlatformService.channel.invokeMethod<String>('savePublic', {
        'path': path,
        'gallery': gallery,
      }))!;
    }
    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw const FileSystemException('Pasta Downloads indisponível.');
    }
    return copyToDownloads(File(path), downloads);
  }

  // An exclusive receipt directory prevents overwriting existing user files.
  static Future<String> copyToDownloads(
    File source,
    Directory downloads,
  ) async {
    if (!await source.exists()) {
      throw const FileSystemException('Arquivo recebido não encontrado.');
    }
    final root = Directory(p.join(downloads.path, 'OmniLink'));
    await root.create(recursive: true);
    final sourcePath = p.normalize(p.absolute(source.path));
    if (p.isWithin(p.normalize(p.absolute(root.path)), sourcePath)) {
      return source.path;
    }
    final receipt = await root.createTemp('recebido-');
    try {
      return (await source.copy(
        p.join(receipt.path, p.basename(source.path)),
      )).path;
    } catch (_) {
      await receipt.delete(recursive: true);
      rethrow;
    }
  }
}
