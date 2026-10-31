import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnilink/services/save_service.dart';

void main() {
  test('cópia para Downloads preserva conteúdo e nomes existentes', () async {
    final temp = await Directory.systemTemp.createTemp('omnilink-save-');
    try {
      final source = await File(
        '${temp.path}/foto.jpg',
      ).writeAsBytes([1, 2, 3]);
      final downloads = Directory('${temp.path}/Downloads');
      final first = await SaveService.copyToDownloads(source, downloads);
      final second = await SaveService.copyToDownloads(source, downloads);
      expect(first, isNot(second));
      expect(await File(first).readAsBytes(), [1, 2, 3]);
      expect(await File(second).readAsBytes(), [1, 2, 3]);
      expect(await SaveService.copyToDownloads(File(first), downloads), first);
      expect(await source.exists(), isTrue);
    } finally {
      await temp.delete(recursive: true);
    }
  });
  test('galeria oferece fotos e vídeos, mas não documentos', () {
    expect(SaveService.isGalleryMedia('FOTO.JPG'), isTrue);
    expect(SaveService.isGalleryMedia('video.mp4'), isTrue);
    expect(SaveService.isGalleryMedia('relatorio.pdf'), isFalse);
  });
}
