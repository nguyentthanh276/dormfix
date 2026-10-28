import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/managed_account.dart';

abstract interface class AdminAccountsRepository {
  Future<List<ManagedAccount>> list({required String query, AppRole? role, AccountStatus? status, required int offset, required int limit});
}

class SupabaseAdminAccountsRepository implements AdminAccountsRepository {
  const SupabaseAdminAccountsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ManagedAccount>> list({required String query, AppRole? role, AccountStatus? status, required int offset, required int limit}) async {
    final response = await _client.rpc('admin_list_accounts', params: {
      'p_query': query.trim().isEmpty ? null : query.trim(),
      'p_role': role?.databaseValue,
      'p_status': status?.databaseValue,
      'p_offset': offset,
      'p_limit': limit,
    });
    if (response is! List) throw const FormatException('Dữ liệu danh sách không hợp lệ.');
    return response.map((row) => ManagedAccount.fromJson(Map<String, dynamic>.from(row as Map))).toList(growable: false);
  }
}
