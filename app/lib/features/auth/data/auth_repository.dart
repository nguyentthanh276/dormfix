import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

abstract interface class AuthRepository {
  bool get hasSession;
  Stream<bool> get sessionChanges;

  Future<UserProfile> signIn({required String email, required String password});

  Future<UserProfile> loadProfile();

  Future<void> signOut();
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
