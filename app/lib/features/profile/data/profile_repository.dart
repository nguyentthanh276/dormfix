import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/models/user_profile.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> getProfile();
  Future<UserProfile> updatePhone({required String phone});
}

class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile> getProfile() async {
    final expectedUserId = _client.auth.currentSession?.user.id;
    if (expectedUserId == null || expectedUserId.isEmpty) {
      throw _sessionChangedFailure;
    }

    try {
      final result = await _client.rpc('get_my_profile');
      if (_client.auth.currentSession?.user.id != expectedUserId) {
        throw _sessionChangedFailure;
      }
      if (result is! Map) {
        throw const ProfileFailure(
          'Dữ liệu hồ sơ không hợp lệ. Vui lòng liên hệ quản trị viên.',
          signOutRequired: true,
        );
      }
      final profile = UserProfile.fromJson(Map<String, dynamic>.from(result));
      if (profile.id != expectedUserId) throw _sessionChangedFailure;
      return profile;
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') {
        throw const ProfileFailure(
          'Không tìm thấy hồ sơ hợp lệ cho tài khoản này.',
          signOutRequired: true,
        );
      }
      if (error.code == '28000') {
        throw const ProfileFailure(
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
          signOutRequired: true,
        );
      }
      throw const ProfileFailure(
        'Không thể tải hồ sơ do lỗi kết nối. Vui lòng thử lại.',
      );
    } catch (_) {
      throw const ProfileFailure(
        'Không thể tải hồ sơ do lỗi kết nối. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<UserProfile> updatePhone({required String phone}) async {
    final expectedUserId = _client.auth.currentSession?.user.id;
    if (expectedUserId == null || expectedUserId.isEmpty) {
      throw _sessionChangedFailure;
    }

    final trimmedPhone = phone.trim();

    try {
      final result = await _client.rpc(
        'update_my_phone',
        params: {'p_phone': trimmedPhone},
      );

      if (_client.auth.currentSession?.user.id != expectedUserId) {
        throw _sessionChangedFailure;
      }

      if (result is Map) {
        return UserProfile.fromJson(Map<String, dynamic>.from(result));
      }

      // Trường hợp RPC trả về void hoặc định dạng khác, tải lại profile đầy đủ
      final refreshed = await getProfile();
      return refreshed;
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') {
        throw const ProfileFailure(
          'Không tìm thấy hồ sơ hợp lệ cho tài khoản này.',
          signOutRequired: true,
        );
      }
      if (error.code == '28000') {
        throw const ProfileFailure(
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
          signOutRequired: true,
        );
      }
      if (error.code == '22023') {
        throw const ProfileFailure('Vui lòng nhập số điện thoại hợp lệ.');
      }
      throw ProfileFailure(
        error.message.isNotEmpty
            ? error.message
            : 'Không thể cập nhật số điện thoại lúc này. Vui lòng thử lại.',
      );
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure(
        'Không thể cập nhật số điện thoại do lỗi kết nối. Vui lòng thử lại.',
      );
    }
  }

  static const _sessionChangedFailure = ProfileFailure(
    'Phiên đăng nhập đã kết thúc hoặc thay đổi. Vui lòng đăng nhập lại.',
    signOutRequired: true,
  );
}

class ProfileFailure implements Exception {
  const ProfileFailure(this.message, {this.signOutRequired = false});

  final String message;
  final bool signOutRequired;

  @override
  String toString() =>
      'ProfileFailure($message, signOutRequired: $signOutRequired)';
}
