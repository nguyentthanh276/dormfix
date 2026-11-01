import 'package:supabase_flutter/supabase_flutter.dart';

class StudentConfirmationRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// [DF-014] Xác nhận đã khắc phục (Hoàn tất)
  Future<void> confirmFixed({required String requestId, String? note}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Chưa đăng nhập.');
    }

    final res = await _client
        .from('repair_requests')
        .update({
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .match({
          'id': requestId,
          'status': 'awaiting_confirmation',
          'student_id': userId,
        })
        .select('id');

    if ((res as List).isEmpty) {
      throw Exception(
        'Không thể xác nhận: Đơn không ở trạng thái Chờ xác nhận hoặc không chính chủ.',
      );
    }

    await _client.from('request_history').insert({
      'request_id': requestId,
      'entity_type': 'request',
      'entity_id': requestId,
      'action': 'completed',
      'actor_id': userId,
      'old_status': 'awaiting_confirmation',
      'new_status': 'completed',
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
    });
  }
}
