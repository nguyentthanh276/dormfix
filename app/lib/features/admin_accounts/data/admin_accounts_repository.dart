import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/create_student_result.dart';
import '../models/room_summary.dart';

// ─── Domain failure ───────────────────────────────────────────────────────────

/// Business-level failure returned by [AdminAccountsRepository] operations.
class AdminAccountsFailure implements Exception {
  const AdminAccountsFailure(this.message);
  final String message;
}

// ─── Repository interface ─────────────────────────────────────────────────────

abstract interface class AdminAccountsRepository {
  /// Fetches active rooms available for assigning to a new student.
  Future<List<RoomSummary>> fetchActiveRooms();

  /// Creates a student Auth user and profile (DF-031).
  ///
  /// Throws [AdminAccountsFailure] with a user-facing message on failure.
  Future<CreateStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    required String tempPassword,
  });
}

// ─── Supabase implementation ──────────────────────────────────────────────────

class SupabaseAdminAccountsRepository implements AdminAccountsRepository {
  const SupabaseAdminAccountsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<RoomSummary>> fetchActiveRooms() async {
    try {
      final rows = await _client
          .from('rooms')
          .select('id, code, building')
          .eq('is_active', true)
          .order('code');
      return (rows as List)
          .map(
            (row) =>
                RoomSummary.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AdminAccountsFailure(
        'Không thể tải danh sách phòng: ${_pgMessage(e)}',
      );
    } catch (_) {
      throw const AdminAccountsFailure(
        'Không thể tải danh sách phòng. Vui lòng kiểm tra kết nối và thử lại.',
      );
    }
  }

  @override
  Future<CreateStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    required String tempPassword,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_create_student',
        params: {
          'p_identity_code': identityCode.trim(),
          'p_full_name': fullName.trim(),
          'p_email': email.trim().toLowerCase(),
          'p_phone': phone.trim(),
          'p_room_id': roomId,
          'p_temp_password': tempPassword,
        },
      );

      if (result is! Map || result['id'] is! String) {
        throw const AdminAccountsFailure(
          'Phản hồi không hợp lệ từ máy chủ. Vui lòng liên hệ quản trị viên.',
        );
      }
      return CreateStudentResult(profileId: result['id'] as String);
    } on AdminAccountsFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw AdminAccountsFailure(_translateRpcError(e));
    } catch (_) {
      throw const AdminAccountsFailure(
        'Không thể tạo tài khoản. Vui lòng kiểm tra kết nối và thử lại.',
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _pgMessage(PostgrestException e) =>
      e.message.isNotEmpty ? e.message : 'lỗi máy chủ';

  String _translateRpcError(PostgrestException e) {
    // Map our custom SQLSTATE codes from the RPC to user-facing messages.
    return switch (e.code) {
      '28000' => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      '42501' => 'Bạn không có quyền thực hiện thao tác này.',
      'DF001' => 'Mã Sinh viên không được để trống.',
      'DF002' => 'Họ tên không được để trống.',
      'DF003' => 'Địa chỉ email không hợp lệ.',
      'DF004' => 'Số điện thoại không được để trống.',
      'DF005' => 'Vui lòng chọn phòng.',
      'DF006' => 'Mật khẩu tạm phải có ít nhất 8 ký tự.',
      'DF007' => 'Mã Sinh viên đã tồn tại trong hệ thống.',
      'DF008' => 'Email đã được sử dụng trong hệ thống.',
      'DF009' =>
        'Phòng được chọn không còn hoạt động. Vui lòng chọn phòng khác.',
      'DF010' =>
        'Thông tin bị trùng. Vui lòng kiểm tra lại mã Sinh viên và email.',
      _ =>
        'Không thể tạo tài khoản: ${e.message.isNotEmpty ? e.message : 'lỗi máy chủ'}.',
    };
  }
}
