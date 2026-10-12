import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/models/app_role.dart';
import '../../../core/security/password_hasher.dart';
import '../../profile/models/user_profile.dart';
import 'auth_repository.dart';

class AuthService extends ChangeNotifier {
  AuthService(this.repository, {PasswordHasher? hasher})
    : hasher = hasher ?? PasswordHasher();
  final AuthRepository repository;
  final PasswordHasher hasher;
  String? _userId;
  UserProfile? _current;
  UserProfile? get current => _current;
  int _sessionVersion = 0;

  Future<void> login(String email, String password) async {
    logout();
    final session = _sessionVersion;
    final row = await repository.findByEmail(email);
    if (row == null ||
        !await hasher.verify(
          password,
          row['password_hash'] as String,
          row['password_salt'] as String,
          row['password_iterations'] as int,
        )) {
      throw const AppFailure('Email hoặc mật khẩu không đúng.');
    }
    if (session != _sessionVersion) return;
    if (row['status'] != 'active') {
      throw const AppFailure('Tài khoản đã bị khóa hoặc thu hồi.');
    }
    final profile = await repository.profile(row['id'] as String);
    if (session != _sessionVersion) return;
    _userId = profile!.id;
    _current = profile;
    notifyListeners();
  }

  void logout() {
    _sessionVersion++;
    _userId = null;
    _current = null;
    notifyListeners();
  }

  Future<UserProfile> getMyProfile() async {
    final id = _userId;
    if (id == null) throw const AppFailure('Vui lòng đăng nhập.');
    final profile = await repository.profile(id);
    if (profile == null || profile.status != 'active' || _userId != id) {
      logout();
      throw const AppFailure('Phiên đăng nhập không còn hợp lệ.');
    }
    _current = profile;
    return profile;
  }

  /// All future business services must call this before reading/writing data.
  Future<UserProfile> requireBusinessAccess({Set<AppRole>? roles}) async {
    final profile = await getMyProfile();
    if (profile.mustChangePassword) {
      throw const AppFailure('Bạn phải đổi mật khẩu trước.');
    }
    if (roles != null && !roles.contains(profile.role)) {
      throw const AppFailure('Bạn không có quyền thực hiện thao tác này.');
    }
    return profile;
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final profile = await getMyProfile();
    final invalid = PasswordHasher.validate(newPassword);
    if (invalid != null) throw AppFailure(invalid);
    if (newPassword == currentPassword) {
      throw const AppFailure('Mật khẩu mới phải khác mật khẩu hiện tại.');
    }
    final session = _sessionVersion;
    final digest = await hasher.hash(newPassword);
    await repository.database.transaction((tx) async {
      final rows = await tx.query(
        'profiles',
        where: 'id = ?',
        whereArgs: [profile.id],
      );
      final row = rows.single;
      if (_sessionVersion != session || row['status'] != 'active') {
        throw const AppFailure('Phiên đăng nhập không còn hợp lệ.');
      }
      if (!await hasher.verify(
        currentPassword,
        row['password_hash'] as String,
        row['password_salt'] as String,
        row['password_iterations'] as int,
      )) {
        throw const AppFailure('Mật khẩu hiện tại không đúng.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'profiles',
        {
          'password_hash': digest.hash,
          'password_salt': digest.salt,
          'password_iterations': digest.iterations,
          'must_change_password': 0,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [profile.id],
      );
      await tx.insert('request_history', {
        'id': 'password-${profile.id}-$now',
        'entity_type': 'profile',
        'entity_id': profile.id,
        'action': 'password_changed',
        'actor_id': profile.id,
        'occurred_at': now,
      });
    });
    await getMyProfile();
    notifyListeners();
  }

  Future<void> updatePhone(String phone) async {
    final profile = await requireBusinessAccess(
      roles: {AppRole.student, AppRole.technician},
    );
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone.trim())) {
      throw const AppFailure('Số điện thoại cần 7 đến 15 chữ số.');
    }
    final session = _sessionVersion;
    await repository.database.transaction((tx) async {
      final rows = await tx.query(
        'profiles',
        where: 'id = ?',
        whereArgs: [profile.id],
      );
      if (rows.isEmpty ||
          rows.single['status'] != 'active' ||
          rows.single['must_change_password'] != 0 ||
          session != _sessionVersion) {
        throw const AppFailure('Phiên đăng nhập không còn hợp lệ.');
      }
      await tx.update(
        'profiles',
        {
          'phone': phone.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [profile.id],
      );
      await tx.insert('request_history', {
        'id': 'phone-${profile.id}-${DateTime.now().microsecondsSinceEpoch}',
        'entity_type': 'profile',
        'entity_id': profile.id,
        'action': 'phone_updated',
        'actor_id': profile.id,
      });
    });
    await getMyProfile();
    notifyListeners();
  }
}
