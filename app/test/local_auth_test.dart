import 'dart:io';

import 'package:dormfix/core/database/local_database.dart';
import 'package:dormfix/core/errors/app_failure.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/data/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late Database db;
  late AuthService auth;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dormfix-test-');
    db = await LocalDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'test.db'),
    );
    auth = AuthService(AuthRepository(db));
  });
  tearDown(() async {
    auth.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  test('ten tables, foreign keys, unique identities, first-run seed', () async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    expect(rows.length, 10);
    expect((await db.rawQuery('PRAGMA foreign_keys')).single.values.single, 1);
    expect((await db.query('profiles')).length, 3);
    expect((await db.query('incident_categories')).length, 4);
    final category = (await db.query('incident_categories')).first['id'];
    final requestId = await db.insert('repair_requests', {
      'student_id': 'demo-student',
      'room_id': 'demo-room',
      'room_code_snapshot': 'DEMO-A101',
      'building_snapshot': 'Tòa demo',
      'category_id': category,
      'category_name_snapshot': 'Điện',
      'title': 'Đèn hỏng',
      'description': 'Đèn không sáng',
    });
    expect(
      (await db.query('repair_requests')).single['request_code'],
      'DF000001',
    );
    await expectLater(
      db.insert('request_assignments', {
        'id': 'invalid',
        'request_id': requestId + 100,
        'technician_id': 'demo-technician',
        'assigned_by': 'demo-admin',
        'request_code_snapshot': 'DF000001',
        'title_snapshot': 'Đèn hỏng',
        'room_code_snapshot': 'DEMO-A101',
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.insert('rooms', {
        'id': 'another',
        'code': 'demo-a101',
        'building': 'X',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.update(
        'profiles',
        {'email': 'other@example.com'},
        where: 'id=?',
        whereArgs: ['demo-student'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });
  test('all demo passwords verify, role gate and logout', () async {
    await expectLater(
      auth.login('admin@example.com', 'wrong'),
      throwsA(isA<AppFailure>()),
    );
    expect(auth.current, isNull);
    await auth.login(' ADMIN@example.com ', 'Dormfix393');
    expect(
      (await auth.requireBusinessAccess(roles: {AppRole.admin})).role,
      AppRole.admin,
    );
    await expectLater(
      auth.requireBusinessAccess(roles: {AppRole.student}),
      throwsA(isA<AppFailure>()),
    );
    auth.logout();
    await expectLater(auth.getMyProfile(), throwsA(isA<AppFailure>()));
    await auth.login('student@example.com', 'Dormfix393');
    expect((await auth.getMyProfile()).roomCode, 'DEMO-A101');
    await expectLater(auth.requireBusinessAccess(), throwsA(isA<AppFailure>()));
    await auth.login('technican@example.com', 'Dormfix393');
    expect(auth.current!.role, AppRole.technician);
    await expectLater(auth.requireBusinessAccess(), throwsA(isA<AppFailure>()));
  });
  test(
    'password change is validated, persisted, not reset by reopening',
    () async {
      await auth.login('student@example.com', 'Dormfix393');
      await expectLater(
        auth.changePassword('wrong', 'Newpass393'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        auth.changePassword('Dormfix393', 'short'),
        throwsA(isA<AppFailure>()),
      );
      expect((await auth.getMyProfile()).mustChangePassword, isTrue);
      await auth.changePassword('Dormfix393', 'Newpass393');
      expect((await auth.requireBusinessAccess()).mustChangePassword, isFalse);
      await auth.updatePhone('0123456789');
      await db.close();
      db = await LocalDatabase.open(
        factory: databaseFactoryFfi,
        path: p.join(dir.path, 'test.db'),
      );
      auth.dispose();
      auth = AuthService(AuthRepository(db));
      await expectLater(
        auth.login('student@example.com', 'Dormfix393'),
        throwsA(isA<AppFailure>()),
      );
      await auth.login('student@example.com', 'Newpass393');
      expect(auth.current!.mustChangePassword, isFalse);
      expect(auth.current!.phone, '0123456789');
      expect((await db.query('profiles')).length, 3);
      final stored = (await db.query(
        'profiles',
        where: 'id=?',
        whereArgs: ['demo-student'],
      )).single;
      expect(stored['password_hash'], isNot('Newpass393'));
      expect((await db.query('request_history')).length, 2);
    },
  );
  test('lock/revoke blocks existing and future sessions', () async {
    await auth.login('admin@example.com', 'Dormfix393');
    await db.update(
      'profiles',
      {'status': 'locked'},
      where: 'id=?',
      whereArgs: ['demo-admin'],
    );
    await expectLater(auth.requireBusinessAccess(), throwsA(isA<AppFailure>()));
    expect(auth.current, isNull);
    await expectLater(
      auth.login('admin@example.com', 'Dormfix393'),
      throwsA(isA<AppFailure>()),
    );
    await db.update(
      'profiles',
      {'status': 'revoked'},
      where: 'id=?',
      whereArgs: ['demo-admin'],
    );
    await expectLater(
      auth.login('admin@example.com', 'Dormfix393'),
      throwsA(isA<AppFailure>()),
    );
  });
}
