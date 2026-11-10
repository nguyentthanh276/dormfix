import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/supabase_session_guard.dart';
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
      if (error.code == 'user_banned') {
        throw const AuthFailure(
          'Tài khoản đã bị khóa hoặc thu hồi. Vui lòng liên hệ Admin.',
        );
      }
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
  Future<UserProfile> changePassword({
    required String newPassword,
  }) => SupabaseSessionGuard(_client).run((accessToken) async {
    final expectedUserId = _client.auth.currentSession!.user.id;
    var samePassword = false;
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      samePassword =
          error.code == 'same_password' ||
          error.message.toLowerCase().contains('different from the old');
      if (!samePassword) {
        if (error.statusCode == '400' ||
            error.statusCode == '422' ||
            error.code == 'weak_password') {
          throw const AuthFailure('Mật khẩu mới không hợp lệ hoặc quá yếu.');
        }
        throw const AuthFailure(
          'Không thể đổi mật khẩu lúc này. Vui lòng thử lại.',
        );
      }
    } catch (_) {
      throw const AuthFailure(
        'Không thể đổi mật khẩu do lỗi kết nối. Vui lòng thử lại.',
      );
    }

    if (_client.auth.currentSession?.user.id != expectedUserId) {
      throw _sessionChangedFailure;
    }
    try {
      // The server compares the current Auth password proof with the
      // provisioning marker. A retry can finish an earlier successful write.
      await _client
          .rpc('complete_change_password')
          .setHeader('Authorization', 'Bearer $accessToken');
    } on PostgrestException catch (error) {
      if (error.code == '28000' || error.code == '42501') {
        throw _sessionChangedFailure;
      }
      if (error.code == 'P0001' && samePassword) {
        throw const AuthFailure(
          'Mật khẩu mới không được trùng với mật khẩu tạm.',
        );
      }
      // A lost acknowledgement can still be reconciled by the profile read.
    } catch (_) {
      // Reconcile below. Access is granted only by the server profile.
    }

    if (_client.auth.currentSession?.user.id != expectedUserId) {
      throw _sessionChangedFailure;
    }
    final profile = await loadProfile();
    if (profile.status == 'active' &&
        (profile.mustChangePassword || !profile.canAccess)) {
      throw const AuthFailure(
        'Máy chủ chưa xác nhận đổi mật khẩu. Vui lòng thử lại.',
      );
    }
    return profile;
  }, denied: _sessionChangedFailure);

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
