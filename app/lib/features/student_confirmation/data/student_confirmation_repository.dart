import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';


class StudentConfirmationRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Helper: Tải ảnh lên Supabase Storage và lưu vào bảng request_attachments
  Future<void> _uploadAttachments({
    required String requestId,
    required String feedbackId,
    required List<String> imagePaths,
    required String userId,
  }) async {
    for (final path in imagePaths) {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final size = bytes.length;
      if (size > 5 * 1024 * 1024) {
        throw Exception('File ảnh vượt quá giới hạn 5 MB.');
      }

      final ext = path.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
      final fileName = '${requestId}_${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}.$ext';
      final storagePath = 'requests/$requestId/$fileName';

      // 1. Tải lên Storage Bucket 'repair_images'
      await _client.storage.from('repair_images').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: mimeType),
      );

      // 2. Thêm bản ghi vào bảng request_attachments
      await _client.from('request_attachments').insert({
        'request_id': requestId,
        'feedback_id': feedbackId,
        'storage_path': storagePath,
        'mime_type': mimeType,
        'size_bytes': size,
        'uploaded_by': userId,
      });
    }
  }

  /// [DF-014] Xác nhận đã khắc phục (Hoàn tất)
  Future<void> confirmFixed({
    required String requestId,
    String? note,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Chưa đăng nhập.');

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
      throw Exception('Không thể xác nhận: Đơn không ở trạng thái Chờ xác nhận hoặc không chính chủ.');
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

  /// [DF-015] Yêu cầu sửa lại và đính kèm ảnh (Sprint 3)
  Future<void> requestRework({
    required String requestId,
    required String reason,
    List<String> imagePaths = const [],
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Chưa đăng nhập.');

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) throw Exception('Lý do sửa lại không được để trống.');
    if (imagePaths.length > 5) throw Exception('Tối đa 5 hình ảnh.');

    // 1. Chuyển trạng thái sang awaiting_rework (giữ nguyên KTV phụ trách)
    final res = await _client
        .from('repair_requests')
        .update({
          'status': 'awaiting_rework',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .match({
          'id': requestId,
          'status': 'awaiting_confirmation',
          'student_id': userId,
        })
        .select('id');

    if ((res as List).isEmpty) {
      throw Exception('Đơn không ở trạng thái Chờ xác nhận hoặc không chính chủ.');
    }

    // 2. Lưu phản hồi vào request_feedback (kind: 'rework')
    final feedbackRes = await _client
        .from('request_feedback')
        .insert({
          'request_id': requestId,
          'kind': 'rework',
          'reason': trimmedReason,
          'submitted_by': userId,
        })
        .select('id')
        .single();

    final feedbackId = feedbackRes['id'] as String;

    // 3. Tải ảnh đính kèm (nếu có)
    if (imagePaths.isNotEmpty) {
      await _uploadAttachments(
        requestId: requestId,
        feedbackId: feedbackId,
        imagePaths: imagePaths,
        userId: userId,
      );
    }

    // 4. Lưu vết lịch sử
    await _client.from('request_history').insert({
      'request_id': requestId,
      'entity_type': 'request',
      'entity_id': requestId,
      'action': 'request_rework',
      'actor_id': userId,
      'old_status': 'awaiting_confirmation',
      'new_status': 'awaiting_rework',
      'note': trimmedReason,
    });
  }

  /// [DF-016] Mở lại yêu cầu Hoàn tất (Sprint 4)
  Future<void> reopenRequest({
    required String requestId,
    required String requestRoomId,
    required String currentStudentRoomId,
    required String reason,
    List<String> imagePaths = const [],
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Chưa đăng nhập.');

    // Ràng buộc: Phòng của đơn phải trùng phòng hiện tại của SV
    if (requestRoomId != currentStudentRoomId) {
      throw Exception('Chỉ được mở lại yêu cầu thuộc phòng bạn đang ở hiện tại.');
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) throw Exception('Lý do mở lại không được để trống.');
    if (imagePaths.length > 5) throw Exception('Tối đa 5 hình ảnh.');

    // 1. Chuyển trạng thái sang pending, BỎ phân công hiện tại (assigned_technician_id = null)
    final res = await _client
        .from('repair_requests')
        .update({
          'status': 'pending',
          'assigned_technician_id': null,
          'completed_at': null,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .match({
          'id': requestId,
          'status': 'completed',
          'student_id': userId,
        })
        .select('id');

    if ((res as List).isEmpty) {
      throw Exception('Không thể mở lại: Đơn không ở trạng thái Hoàn tất hoặc bạn không có quyền.');
    }

    // 2. Thêm bản ghi phản hồi (kind: 'reopen')
    final feedbackRes = await _client
        .from('request_feedback')
        .insert({
          'request_id': requestId,
          'kind': 'reopen',
          'reason': trimmedReason,
          'submitted_by': userId,
        })
        .select('id')
        .single();

    final feedbackId = feedbackRes['id'] as String;

    // 3. Tải ảnh (nếu có)
    if (imagePaths.isNotEmpty) {
      await _uploadAttachments(
        requestId: requestId,
        feedbackId: feedbackId,
        imagePaths: imagePaths,
        userId: userId,
      );
    }

    // 4. Lưu vết lịch sử
    await _client.from('request_history').insert({
      'request_id': requestId,
      'entity_type': 'request',
      'entity_id': requestId,
      'action': 'reopen',
      'actor_id': userId,
      'old_status': 'completed',
      'new_status': 'pending',
      'note': trimmedReason,
    });
  }
}