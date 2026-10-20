import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

abstract interface class AuthRepository {
  bool get hasSession;
  Stream<bool> get sessionChanges;

  Future<UserProfile> signIn({required String email, required String password});

  Future<UserProfile> loadProfile();

  Future<void> signOut();

  Future<UserProfile> changePassword({required String newPassword});

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  });
}

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  Stream<bool> get sessionChanges => _client.auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct()
      .map((userId) => userId != null);

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      if (error.statusCode == '400' ||
          error.statusCode == '401' ||
          error.code == 'invalid_credentials') {
        throw const AuthFailure('Email hoặc mật khẩu không chính xác.');
      }
      throw const AuthFailure('Không thể đăng nhập lúc này. Vui lòng thử lại.');
    }
    return loadProfile();
  }

  @override
  Future<UserProfile> loadProfile() async {
    try {
      final expectedUserId = _client.auth.currentSession?.user.id;
      if (expectedUserId == null || expectedUserId.isEmpty) {
        throw _sessionChangedFailure;
      }
      final result = await _client.rpc('get_my_profile');
      if (_client.auth.currentSession?.user.id != expectedUserId) {
        throw _sessionChangedFailure;
      }
      if (result is! Map) {
        throw const AuthFailure(
          'Dữ liệu hồ sơ không hợp lệ. Vui lòng liên hệ quản trị viên.',
          signOutRequired: true,
        );
      }
      final profile = UserProfile.fromJson(Map<String, dynamic>.from(result));
      if (profile.id != expectedUserId) throw _sessionChangedFailure;
      return profile;
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') {
        throw const AuthFailure(
          'Không tìm thấy hồ sơ hợp lệ cho tài khoản này.',
          signOutRequired: true,
        );
      }
      if (error.code == '28000') {
        throw const AuthFailure(
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
          signOutRequired: true,
        );
      }
      throw const AuthFailure(
        'Không thể tải hồ sơ do lỗi dịch vụ hoặc kết nối. Vui lòng thử lại.',
      );
    } on FormatException {
      throw const AuthFailure(
        'Dữ liệu hồ sơ không hợp lệ. Vui lòng liên hệ quản trị viên.',
        signOutRequired: true,
      );
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<UserProfile> changePassword({required String newPassword}) async {
    final expectedUserId = _client.auth.currentSession?.user.id;
    if (expectedUserId == null || expectedUserId.isEmpty) {
      throw _sessionChangedFailure;
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw AuthFailure(
        error.message.isNotEmpty
            ? error.message
            : 'Không thể đổi mật khẩu lúc này. Vui lòng thử lại.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Không thể đổi mật khẩu do lỗi kết nối. Vui lòng thử lại.',
      );
    }

    try {
      await _client.rpc('complete_change_password');
    } catch (_) {
      // Backend RPC might not be deployed yet in early dev/test environment
    }

    try {
      final updatedProfile = await loadProfile();
      if (!updatedProfile.mustChangePassword) {
        return updatedProfile;
      }
      return updatedProfile.copyWith(
        mustChangePassword: false,
        canAccess: true,
      );
    } catch (e) {
      if (e is AuthFailure && e.signOutRequired) rethrow;
      throw const AuthFailure(
        'Đã đổi mật khẩu nhưng không thể tải lại hồ sơ. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = _client.auth.currentSession;
    final email = session?.user.email;
    final expectedUserId = session?.user.id;
    if (session == null ||
        expectedUserId == null ||
        email == null ||
        email.isEmpty) {
      throw _sessionChangedFailure;
    }

    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException catch (error) {
      if (error.statusCode == '400' ||
          error.statusCode == '401' ||
          error.code == 'invalid_credentials') {
        throw const AuthFailure('Mật khẩu hiện tại không chính xác.');
      }
      throw const AuthFailure(
        'Không thể xác thực mật khẩu hiện tại. Vui lòng thử lại.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Không thể xác thực mật khẩu hiện tại do lỗi kết nối.',
      );
    }

    if (_client.auth.currentSession?.user.id != expectedUserId) {
      throw _sessionChangedFailure;
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw AuthFailure(
        error.message.isNotEmpty
            ? error.message
            : 'Không thể cập nhật mật khẩu lúc này. Vui lòng thử lại.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Không thể cập nhật mật khẩu do lỗi kết nối. Vui lòng thử lại.',
      );
    }
  }

  static const _sessionChangedFailure = AuthFailure(
    'Phiên đăng nhập đã kết thúc hoặc thay đổi. Vui lòng đăng nhập lại.',
    signOutRequired: true,
  );
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.signOutRequired = false});

  final String message;
  final bool signOutRequired;
}
