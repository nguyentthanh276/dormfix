import 'dart:io';

import 'package:dormfix/core/errors/app_failure.dart';
import 'package:dormfix/core/storage/local_image_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('image copy, limits, rollback and safe relative paths', () async {
    final temp = await Directory.systemTemp.createTemp('dormfix-images-');
    addTearDown(() => temp.delete(recursive: true));
    final root = Directory(p.join(temp.path, 'app'));
    final store = LocalImageStore(root);
    final jpg = File(p.join(temp.path, 'photo'));
    await jpg.writeAsBytes([255, 216, 255, 0]);
    final copied = (await store.importImages([jpg])).single;
    expect(copied.mimeType, 'image/jpeg');
    expect(await store.resolve(copied.relativePath).readAsBytes(), [
      255,
      216,
      255,
      0,
    ]);
    expect(p.isAbsolute(copied.relativePath), isFalse);
    expect(() => store.resolve('../../escape'), throwsA(isA<AppFailure>()));
    await expectLater(
      store.importImages(List.filled(6, jpg)),
      throwsA(isA<AppFailure>()),
    );
    final invalid = File(p.join(temp.path, 'invalid.jpg'));
    await invalid.writeAsString('not an image');
    await expectLater(
      store.importImages([jpg, invalid]),
      throwsA(isA<AppFailure>()),
    );
    expect(
      await Directory(p.join(root.path, 'repair-images')).list().length,
      1,
    );
    final huge = File(p.join(temp.path, 'huge.jpg'));
    final handle = await huge.open(mode: FileMode.write);
    await handle.truncate(5242881);
    await handle.close();
    await expectLater(store.importImages([huge]), throwsA(isA<AppFailure>()));
    expect(await store.importImages([]), isEmpty);
  });
}
