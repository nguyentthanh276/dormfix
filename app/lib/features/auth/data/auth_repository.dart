import 'package:sqflite/sqflite.dart';

import '../../profile/models/user_profile.dart';

class AuthRepository {
  AuthRepository(this.database);
  final Database database;
  Future<Map<String, Object?>?> findByEmail(String email) async {
    final rows = await database.query(
      'profiles',
      where: 'lower(trim(email)) = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final rows = await database.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<UserProfile?> profile(String id) async {
    final rows = await database.rawQuery(
      'SELECT p.id,p.identity_code,p.full_name,p.email,p.phone,p.role,p.status,'
      'p.must_change_password,r.code AS room_code FROM profiles p '
      'LEFT JOIN rooms r ON r.id=p.room_id WHERE p.id=?',
      [id],
    );
    return rows.isEmpty ? null : UserProfile.fromRow(rows.single);
  }
}
