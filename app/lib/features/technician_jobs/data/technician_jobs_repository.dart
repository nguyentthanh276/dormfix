// Nguyễn Tiến Thành — DF-020, DF-022: Đọc công việc và ảnh đính kèm.
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/technician_job.dart';

abstract interface class TechnicianJobsRepository {
  Future<List<TechnicianJob>> fetchJobs();

  Future<TechnicianJobDetail> fetchJobDetail(String requestId);

  Future<Uint8List> fetchAttachment(String requestId, JobAttachment attachment);
}

class TechnicianJobsFailure implements Exception {
  const TechnicianJobsFailure(this.message, {this.accessDenied = false});

  final String message;
  final bool accessDenied;

  @override
  String toString() => message;
}

/// All job reads are authorized by the server for the current technician.
class SupabaseTechnicianJobsRepository implements TechnicianJobsRepository {
  const SupabaseTechnicianJobsRepository(this._client);

  final SupabaseClient _client;

  static const _accessFailure = TechnicianJobsFailure(
    'Bạn không còn quyền truy cập công việc này. Vui lòng tải lại danh sách hoặc đăng nhập lại.',
    accessDenied: true,
  );

  // DF-020: Gọi RPC lấy danh sách được giao và chuyển JSON thành model.
  @override
  Future<List<TechnicianJob>> fetchJobs() => _read(() async {
    final result = await _client.rpc('technician_list_jobs');
    if (result is! List) throw const FormatException('Expected a job list.');
    return List<TechnicianJob>.unmodifiable(
      result.map((item) => TechnicianJob.fromJson(_jsonObject(item))),
    );
  }, 'Không thể tải danh sách công việc. Vui lòng thử lại.');

  @override
  Future<TechnicianJobDetail> fetchJobDetail(String requestId) => _read(
    () => _loadDetail(requestId),
    'Không thể tải chi tiết công việc. Vui lòng thử lại.',
  );

  // DF-022: Gửi ID yêu cầu và kiểm tra kết quả trả về đúng công việc.
  Future<TechnicianJobDetail> _loadDetail(String requestId) async {
    if (requestId.trim().isEmpty) throw _accessFailure;
    final result = await _client.rpc(
      'technician_get_job',
      params: {'p_request_id': requestId},
    );
    final detail = TechnicianJobDetail.fromJson(_jsonObject(result));
    if (detail.job.id != requestId) throw _accessFailure;
    return detail;
  }

  // DF-022: Đối chiếu ảnh với yêu cầu trước khi tải từ kho riêng tư.
  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    JobAttachment attachment,
  ) => _read(() async {
    // Recheck role and current assignment on every read, including a stale UI.
    final detail = await _loadDetail(requestId);
    if (!detail.attachments.any((item) => _sameAttachment(item, attachment))) {
      throw _accessFailure;
    }

    final result = await _client
        .from('request_attachments')
        .select(
          'id,request_id,storage_path,mime_type,size_bytes,result_id,feedback_id',
        )
        .eq('id', attachment.id)
        .eq('request_id', requestId)
        .eq('storage_path', attachment.storagePath)
        .maybeSingle();
    if (result == null || result['request_id'] != requestId) {
      throw _accessFailure;
    }
    final storedAttachment = JobAttachment.fromJson(result);
    if (!_sameAttachment(storedAttachment, attachment)) throw _accessFailure;

    _requireSession();
    // Private Storage authorizes the JWT again. Never return a reusable URL.
    final bytes = await _client.storage
        .from('repair-images')
        .download(storedAttachment.storagePath);
    _requireSession();
    return bytes;
  }, 'Không thể tải ảnh. Vui lòng thử lại.');

  String _requireSession() {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.accessToken.isEmpty ||
        session.user.id.isEmpty ||
        session.isExpired) {
      throw const TechnicianJobsFailure(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        accessDenied: true,
      );
    }
    return session.user.id;
  }

  Future<T> _read<T>(
    Future<T> Function() operation,
    String failureMessage,
  ) async {
    try {
      final userId = _requireSession();
      final result = await operation();
      if (_requireSession() != userId) throw _accessFailure;
      return result;
    } on TechnicianJobsFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (_isAccessError(error.code, error.message)) throw _accessFailure;
      throw TechnicianJobsFailure(failureMessage);
    } on StorageException catch (error) {
      if (_isAccessError(error.statusCode, error.message)) throw _accessFailure;
      throw TechnicianJobsFailure(failureMessage);
    } on AuthException catch (error) {
      if (error is AuthSessionMissingException ||
          _isAccessError(error.statusCode, error.message) ||
          _isAccessError(error.code, error.message)) {
        throw _accessFailure;
      }
      throw TechnicianJobsFailure(failureMessage);
    } catch (_) {
      // Parsing and transport details can contain private payloads and paths.
      throw TechnicianJobsFailure(failureMessage);
    }
  }
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, dynamic>.from(value);
}

bool _sameAttachment(JobAttachment left, JobAttachment right) =>
    left.id == right.id &&
    left.storagePath == right.storagePath &&
    left.mimeType == right.mimeType &&
    left.sizeBytes == right.sizeBytes &&
    left.resultId == right.resultId &&
    left.feedbackId == right.feedbackId;

bool _isAccessError(String? code, String message) {
  if (const {
    '28000',
    '42501',
    'P0002',
    'PGRST301',
    'PGRST302',
    'PGRST303',
    '401',
    '403',
    'invalid_jwt',
    'session_not_found',
    'session_expired',
  }.contains(code)) {
    return true;
  }
  final lowerMessage = message.toLowerCase();
  return lowerMessage.contains('jwt') && lowerMessage.contains('expired');
}
