import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/app_role.dart';
import '../models/managed_account.dart';

abstract interface class AdminAccountsRepository {
  Future<List<ManagedAccount>> list({required String query, AppRole? role, AccountStatus? status, required int offset, required int limit});
}

class SupabaseAdminAccountsRepository implements AdminAccountsRepository {
  const SupabaseAdminAccountsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ManagedAccount>> list({required String query, AppRole? role, AccountStatus? status, required int offset, required int limit}) async {
    dynamic response;
    try {
      response = await _client.rpc('admin_list_accounts', params: {
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_role': role?.databaseValue,
        'p_status': status?.databaseValue,
        'p_offset': offset,
        'p_limit': limit,
      });
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AdminAccountsFailure(
          'Backend quản lý tài khoản chưa được triển khai. Hãy chạy database/009_admin_account_list.sql trên Supabase.',
        );
      }
      if (error.code == '42501') {
        throw const AdminAccountsFailure('Chỉ Admin đang hoạt động mới được xem danh sách tài khoản.');
      }
      throw const AdminAccountsFailure('Không thể tải danh sách tài khoản do lỗi dịch vụ. Vui lòng thử lại.');
    }
    if (response is! List) throw const FormatException('Dữ liệu danh sách không hợp lệ.');
    return response.map((row) => ManagedAccount.fromJson(Map<String, dynamic>.from(row as Map))).toList(growable: false);
  }
}

class AdminAccountsFailure implements Exception {
  const AdminAccountsFailure(this.message);
  final String message;
}
