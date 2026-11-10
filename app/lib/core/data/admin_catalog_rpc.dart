import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_catalog_failure.dart';
import 'supabase_session_guard.dart';

/// Shared session and error handling for the two Admin catalogs.
class AdminCatalogRpc {
  const AdminCatalogRpc(this._client);

  final SupabaseClient _client;

  Future<T> call<T>(
    String function,
    T Function(Object?) parse, {
    Map<String, dynamic>? params,
    required String readError,
    bool write = false,
  }) => SupabaseSessionGuard(_client).run((token) async {
    try {
      final value = await _client
          .rpc(function, params: params)
          .setHeader('Authorization', 'Bearer $token');
      return parse(value);
    } on PostgrestException catch (error) {
      throw _serverFailure(error) ?? _requestFailure(readError, write);
    } on AuthException {
      throw _denied;
    } on AdminCatalogFailure {
      rethrow;
    } catch (_) {
      throw _requestFailure(readError, write);
    }
  }, denied: _denied);

  static const _denied = AdminCatalogFailure(
    'Bạn không có quyền quản lý dữ liệu này. Vui lòng đăng nhập lại bằng tài khoản Admin.',
    accessDenied: true,
  );

  static AdminCatalogFailure _requestFailure(String readError, bool write) =>
      write
      ? const AdminCatalogFailure(
          'Chưa xác định được thay đổi đã lưu hay chưa. Vui lòng tải lại danh sách để kiểm tra.',
          uncertain: true,
        )
      : AdminCatalogFailure(readError);

  static AdminCatalogFailure? _serverFailure(PostgrestException error) =>
      switch ((error.code, error.message)) {
        (
          '28000' ||
              '42501' ||
              'PGRST301' ||
              'PGRST302' ||
              'PGRST303' ||
              '401' ||
              '403' ||
              'invalid_jwt' ||
              'session_not_found' ||
              'session_expired',
          _,
        ) =>
          _denied,
        ('PGRST202', _) => AdminCatalogFailure.unavailable,
        ('22023', 'INVALID_ROOM_INPUT') => const AdminCatalogFailure(
          'Mã phòng và tòa nhà không hợp lệ.',
        ),
        ('22023', 'INVALID_CATEGORY_INPUT') => const AdminCatalogFailure(
          'Tên loại sự cố không hợp lệ.',
        ),
        ('23505', 'ROOM_CODE_ALREADY_EXISTS') => const AdminCatalogFailure(
          'Mã phòng đã tồn tại.',
        ),
        ('23505', 'CATEGORY_NAME_ALREADY_EXISTS') => const AdminCatalogFailure(
          'Tên loại sự cố đã tồn tại.',
        ),
        ('P0002', 'ROOM_NOT_FOUND') => const AdminCatalogFailure(
          'Không tìm thấy phòng. Vui lòng tải lại danh sách.',
          conflict: true,
        ),
        ('P0002', 'CATEGORY_NOT_FOUND') => const AdminCatalogFailure(
          'Không tìm thấy loại sự cố. Vui lòng tải lại danh sách.',
          conflict: true,
        ),
        ('P0001', 'ROOM_HAS_STUDENTS') => const AdminCatalogFailure(
          'Phòng vẫn còn sinh viên. Vui lòng chuyển sinh viên sang phòng khác trước.',
          conflict: true,
        ),
        _ => null,
      };
}
