import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/app_role.dart';
import '../../admin_rooms/models/admin_room.dart';
import '../models/managed_account.dart';

abstract interface class AdminAccountsRepository {
  Future<List<ManagedAccount>> list({
    required String query,
    AppRole? role,
    AccountStatus? status,
    required int offset,
    required int limit,
  });

  /// DF-031: Tạo tài khoản Sinh viên và gắn phòng
  Future<CreatedStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    String? temporaryPassword,
  });

  /// DF-032: Tạo tài khoản Kỹ thuật viên.
  Future<CreatedTechnicianResult> createTechnician({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    String? temporaryPassword,
  });

  /// DF-033: Đọc các trường được phép chỉnh sửa của Sinh viên.
  Future<StudentAccountEditDetails> getStudentForEdit(String identityCode);

  /// DF-033: Cập nhật tên, điện thoại và phòng; không nhận email/mã định danh.
  Future<void> updateStudent({
    required String identityCode,
    required String fullName,
    required String phone,
    required String roomId,
  });

  /// DF-036: Thu hồi tài khoản; người thực hiện lấy từ phiên Admin phía server.
  Future<void> revokeAccount({
    required String identityCode,
    required String reason,
  });

  /// DF-037: Khôi phục tài khoản đã thu hồi; Sinh viên phải được gắn phòng active.
  Future<void> restoreAccount({required String identityCode, String? roomId});

  /// DF-038: Đặt mật khẩu tạm mới; mật khẩu cũ/hash không được trả về client.
  Future<ResetPasswordResult> resetPassword({required String identityCode});

  /// Lấy danh sách các phòng đang hoạt động để gán cho Sinh viên
  Future<List<AdminRoom>> getActiveRooms();
}

class SupabaseAdminAccountsRepository implements AdminAccountsRepository {
  const SupabaseAdminAccountsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ManagedAccount>> list({
    required String query,
    AppRole? role,
    AccountStatus? status,
    required int offset,
    required int limit,
  }) async {
    dynamic response;
    try {
      response = await _client.rpc(
        'admin_list_accounts',
        params: {
          'p_query': query.trim().isEmpty ? null : query.trim(),
          'p_role': role?.databaseValue,
          'p_status': status?.databaseValue,
          'p_offset': offset,
          'p_limit': limit,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend quản lý tài khoản chưa được triển khai. Hãy chạy database/009_admin_account_list.sql trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được xem danh sách tài khoản.',
        );
      }
      throw const AdminAccountsFailure(
        'Không thể tải danh sách tài khoản do lỗi dịch vụ. Vui lòng thử lại.',
      );
    }
    if (response is! List) {
      throw const FormatException('Dữ liệu danh sách không hợp lệ.');
    }
    return response
        .map(
          (row) =>
              ManagedAccount.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<CreatedStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    String? temporaryPassword,
  }) async {
    dynamic response;
    try {
      response = await _client.rpc(
        'admin_create_student',
        params: {
          'p_identity_code': identityCode.trim(),
          'p_full_name': fullName.trim(),
          'p_email': email.trim().toLowerCase(),
          'p_phone': phone.trim(),
          'p_room_id': roomId,
          'p_temporary_password':
              (temporaryPassword != null && temporaryPassword.trim().isNotEmpty)
              ? temporaryPassword.trim()
              : null,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend tạo tài khoản chưa được triển khai. Hãy chạy database/015_admin_create_student.sql trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.',
        );
      }
      if (error.code == '23505') {
        final msg = error.message.toLowerCase();
        if (msg.contains('mã') || msg.contains('identity')) {
          throw const AdminAccountsFailure(
            'Mã Sinh viên đã tồn tại trên hệ thống.',
          );
        }
        if (msg.contains('email')) {
          throw const AdminAccountsFailure('Email đã tồn tại trên hệ thống.');
        }
      }
      throw AdminAccountsFailure(error.message);
    } catch (e) {
      if (e is AdminAccountsFailure) rethrow;
      throw const AdminAccountsFailure(
        'Không thể tạo tài khoản Sinh viên do lỗi dịch vụ. Vui lòng thử lại.',
      );
    }

    if (response is! Map) {
      throw const FormatException('Dữ liệu phản hồi không hợp lệ.');
    }
    return CreatedStudentResult.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<CreatedTechnicianResult> createTechnician({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    String? temporaryPassword,
  }) async {
    dynamic response;
    try {
      response = await _client.rpc(
        'admin_create_technician',
        params: {
          'p_identity_code': identityCode.trim(),
          'p_full_name': fullName.trim(),
          'p_email': email.trim().toLowerCase(),
          'p_phone': phone.trim(),
          'p_temporary_password':
              (temporaryPassword != null && temporaryPassword.trim().isNotEmpty)
              ? temporaryPassword.trim()
              : null,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend tạo tài khoản Kỹ thuật viên chưa được triển khai. Hãy chạy database/016_admin_create_technician.sql trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.',
        );
      }
      if (error.code == '23505') {
        final message = error.message.toLowerCase();
        if (message.contains('mã') || message.contains('identity')) {
          throw const AdminAccountsFailure(
            'Mã Kỹ thuật viên đã tồn tại trên hệ thống.',
          );
        }
        if (message.contains('email')) {
          throw const AdminAccountsFailure('Email đã tồn tại trên hệ thống.');
        }
      }
      if (error.code == '22023') {
        throw AdminAccountsFailure(error.message);
      }
      throw const AdminAccountsFailure(
        'Không thể tạo tài khoản Kỹ thuật viên do lỗi dịch vụ. Vui lòng thử lại.',
      );
    } catch (error) {
      if (error is AdminAccountsFailure) rethrow;
      throw const AdminAccountsFailure(
        'Không thể tạo tài khoản Kỹ thuật viên do lỗi dịch vụ. Vui lòng thử lại.',
      );
    }

    if (response is! Map) {
      throw const FormatException('Dữ liệu phản hồi không hợp lệ.');
    }
    return CreatedTechnicianResult.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<StudentAccountEditDetails> getStudentForEdit(
    String identityCode,
  ) async {
    try {
      final response = await _client.rpc(
        'admin_get_student_edit_details',
        params: {'p_identity_code': identityCode.trim()},
      );
      if (response is! Map) {
        throw const FormatException('Dữ liệu phản hồi không hợp lệ.');
      }
      return StudentAccountEditDetails.fromJson(
        Map<String, dynamic>.from(response),
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend cập nhật Sinh viên chưa được triển khai. Hãy chạy migration 017 của DF-033 trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được xem thông tin này.',
        );
      }
      if (error.code == 'P0002') {
        throw const AdminAccountsFailure(
          'Không tìm thấy Sinh viên có thể cập nhật.',
        );
      }
      throw const AdminAccountsFailure(
        'Không thể tải thông tin Sinh viên. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<void> updateStudent({
    required String identityCode,
    required String fullName,
    required String phone,
    required String roomId,
  }) async {
    try {
      await _client.rpc(
        'admin_update_student',
        params: {
          'p_identity_code': identityCode.trim(),
          'p_full_name': fullName.trim(),
          'p_phone': phone.trim(),
          'p_room_id': roomId,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend cập nhật Sinh viên chưa được triển khai. Hãy chạy migration 017 của DF-033 trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được cập nhật Sinh viên.',
        );
      }
      if (error.code == 'P0002') {
        throw const AdminAccountsFailure(
          'Sinh viên hoặc phòng đang hoạt động không còn hợp lệ.',
        );
      }
      if (error.code == '22023') {
        throw AdminAccountsFailure(error.message);
      }
      throw const AdminAccountsFailure(
        'Không thể cập nhật Sinh viên. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<void> revokeAccount({
    required String identityCode,
    required String reason,
  }) async {
    try {
      await _client.rpc(
        'admin_revoke_account',
        params: {
          'p_identity_code': identityCode.trim(),
          'p_reason': reason.trim(),
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend thu hồi tài khoản chưa được triển khai. Hãy chạy migration 018 của DF-036 trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được thu hồi tài khoản.',
        );
      }
      if (error.code == 'P0002') {
        throw const AdminAccountsFailure('Không tìm thấy tài khoản hợp lệ.');
      }
      if (error.code == 'P0001') {
        throw AdminAccountsFailure(error.message);
      }
      if (error.code == '22023') {
        throw AdminAccountsFailure(error.message);
      }
      throw const AdminAccountsFailure(
        'Không thể thu hồi tài khoản. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<void> restoreAccount({
    required String identityCode,
    String? roomId,
  }) async {
    try {
      await _client.rpc(
        'admin_restore_account',
        params: {'p_identity_code': identityCode.trim(), 'p_room_id': roomId},
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend khôi phục tài khoản chưa được triển khai. Hãy chạy migration 019 của DF-037 trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được khôi phục tài khoản.',
        );
      }
      if (error.code == 'P0002') {
        throw const AdminAccountsFailure(
          'Tài khoản hoặc phòng hoạt động không còn hợp lệ.',
        );
      }
      if (error.code == 'P0001' || error.code == '22023') {
        throw AdminAccountsFailure(error.message);
      }
      throw const AdminAccountsFailure(
        'Không thể khôi phục tài khoản. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<ResetPasswordResult> resetPassword({
    required String identityCode,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_reset_account_password',
        params: {'p_identity_code': identityCode.trim()},
      );
      if (response is! Map) {
        throw const FormatException('Dữ liệu phản hồi không hợp lệ.');
      }
      return ResetPasswordResult.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend đặt lại mật khẩu chưa được triển khai. Hãy chạy migration 020 của DF-038 trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới được đặt lại mật khẩu.',
        );
      }
      if (error.code == 'P0002') {
        throw const AdminAccountsFailure('Không tìm thấy tài khoản hợp lệ.');
      }
      if (error.code == '22023') {
        throw AdminAccountsFailure(error.message);
      }
      throw const AdminAccountsFailure(
        'Không thể đặt lại mật khẩu. Vui lòng thử lại.',
      );
    }
  }

  @override
  Future<List<AdminRoom>> getActiveRooms() async {
    try {
      final response = await _client.rpc('admin_get_active_rooms');
      if (response is List) {
        return response
            .map((e) => AdminRoom.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      // Nếu RPC chưa được áp dụng, fallback sang truy vấn bảng rooms với RLS
    }

    try {
      final response = await _client
          .from('rooms')
          .select('id, code, building, is_active')
          .eq('is_active', true)
          .order('code', ascending: true);

      return (response as List)
          .map((e) => AdminRoom.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const AdminAccountsFailure(
          'Chỉ Admin đang hoạt động mới có quyền xem danh sách phòng.',
        );
      }
      throw AdminAccountsFailure(error.message);
    } catch (e) {
      if (e is AdminAccountsFailure) rethrow;
      throw const AdminAccountsFailure(
        'Không thể tải danh sách phòng. Vui lòng thử lại.',
      );
    }
  }
}

class AdminAccountsFailure implements Exception {
  const AdminAccountsFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
