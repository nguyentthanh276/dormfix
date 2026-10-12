import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_failure.dart';

class StoredImage {
  const StoredImage(this.relativePath, this.mimeType, this.sizeBytes);
  final String relativePath, mimeType;
  final int sizeBytes;
}

/// File-copy utility only. Business services must check request ownership/status
/// and the existing attachment count before using it and saving metadata.
class LocalImageStore {
  LocalImageStore(this.root);
  final Directory root;
  static Future<LocalImageStore> create() async =>
      LocalImageStore(await getApplicationDocumentsDirectory());
  Future<List<StoredImage>> importImages(List<File> files) async {
    if (files.isEmpty) return [];
    if (files.length > 5) throw const AppFailure('Tối đa 5 ảnh mỗi lần gửi.');
    final folder = Directory(
      p.join(
        root.path,
        'repair-images',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await folder.create(recursive: true);
    final result = <StoredImage>[];
    try {
      for (var i = 0; i < files.length; i++) {
        final size = await files[i].length();
        if (size == 0 || size > 5242880) {
          throw const AppFailure('Mỗi ảnh phải lớn hơn 0 và không quá 5 MB.');
        }
        final bytes = await files[i]
            .openRead(0, size < 12 ? size : 12)
            .expand((b) => b)
            .toList();
        String? mime, extension;
        if (bytes.length >= 3 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255) {
          mime = 'image/jpeg';
          extension = 'jpg';
        } else if (bytes.length >= 8 &&
            [
              137,
              80,
              78,
              71,
              13,
              10,
              26,
              10,
            ].asMap().entries.every((e) => bytes[e.key] == e.value)) {
          mime = 'image/png';
          extension = 'png';
        } else if (bytes.length >= 12 &&
            String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
            String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
          mime = 'image/webp';
          extension = 'webp';
        }
        if (mime == null) {
          throw const AppFailure('Chỉ hỗ trợ ảnh JPEG, PNG hoặc WebP.');
        }
        final target = p.join(folder.path, '$i.$extension');
        await files[i].copy(target);
        result.add(
          StoredImage(p.relative(target, from: root.path), mime, size),
        );
      }
      return result;
    } catch (_) {
      await folder.delete(recursive: true);
      rethrow;
    }
  }

  File resolve(String relativePath) {
    final target = p.normalize(p.join(root.path, relativePath));
    if (p.isAbsolute(relativePath) || !p.isWithin(root.path, target)) {
      throw const AppFailure('Đường dẫn ảnh không hợp lệ.');
    }
    return File(target);
  }
}
