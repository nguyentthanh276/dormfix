import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_request.dart';

abstract interface class AdminRequestRepository {
  Future<AdminRequestFilterOptions> fetchFilterOptions();

  Future<List<AdminRequestOption>> fetchActiveTechnicians();

  Future<List<AdminRequestSummary>> fetchRequests({
    required AdminRequestFilters filters,
    required int offset,
    required int limit,
  });

  Future<AdminRequestDetail> fetchRequestDetail(String requestId);

  Future<Uint8List> fetchAttachment(
    String requestId,
    Map<String, dynamic> attachment,
  );

  Future<void> assignRequest(String requestId, String technicianId);

  Future<void> rejectRequest(String requestId, String reason);
}

class AdminRequestFailure implements Exception {
  const AdminRequestFailure(this.message, {this.accessDenied = false});

  final String message;
  final bool accessDenied;

  @override
  String toString() => message;
}

/// DF-043/044: all request reads and filters are checked by Admin-only RPCs.
class SupabaseAdminRequestRepository implements AdminRequestRepository {
  const SupabaseAdminRequestRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'repair-images';
  static const _denied = AdminRequestFailure(
    'Bạn không có quyền xem yêu cầu sửa chữa này. Vui lòng đăng nhập lại bằng tài khoản Admin.',
    accessDenied: true,
  );

  @override
  Future<AdminRequestFilterOptions> fetchFilterOptions() => _read(() async {
    final result = await _client.rpc('admin_request_filter_options');
    if (result is! Map) throw const FormatException('Expected filter options.');
    return AdminRequestFilterOptions.fromJson(
      Map<String, dynamic>.from(result),
    );
  }, 'Không thể tải danh sách bộ lọc. Vui lòng thử lại.');

  @override
  Future<List<AdminRequestOption>> fetchActiveTechnicians() => _read(() async {
    final result = await _client.rpc('admin_request_active_technicians');
    if (result is! List) {
      throw const FormatException('Expected active technicians.');
    }
    return List.unmodifiable(
      result.map((item) => AdminRequestOption.fromJson(_jsonObject(item))),
    );
  }, 'Không thể tải danh sách Kỹ thuật viên. Vui lòng thử lại.');

  @override
  Future<void> assignRequest(String requestId, String technicianId) => _mutate(
    'admin_assign_request',
    {'p_request_id': requestId, 'p_technician_id': technicianId},
  );

  @override
  Future<void> rejectRequest(String requestId, String reason) => _mutate(
    'admin_reject_request',
    {'p_request_id': requestId, 'p_reason': reason},
  );

  Future<void> _mutate(String function, Map<String, dynamic> params) =>
      _read(() async {
        await _client.rpc(function, params: params);
      }, 'Không thể lưu thao tác. Vui lòng tải lại yêu cầu.');

  @override
  Future<List<AdminRequestSummary>> fetchRequests({
    required AdminRequestFilters filters,
    required int offset,
    required int limit,
  }) => _read(() async {
    final result = await _client.rpc(
      'admin_list_requests',
      params: {
        'p_status': filters.status?.databaseValue,
        'p_room_id': filters.roomId,
        'p_category_id': filters.categoryId,
        'p_technician_id': filters.technicianId,
        'p_date_field': filters.hasDateRange
            ? filters.dateField!.databaseValue
            : null,
        'p_from': filters.hasDateRange
            ? filters.from!.toUtc().toIso8601String()
            : null,
        'p_to_exclusive': filters.hasDateRange
            ? filters.toExclusive!.toUtc().toIso8601String()
            : null,
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    if (result is! List) {
      throw const FormatException('Expected a request list.');
    }
    return List.unmodifiable(
      result.map((row) => AdminRequestSummary.fromJson(_jsonObject(row))),
    );
  }, 'Không thể tải danh sách yêu cầu. Vui lòng thử lại.');

  @override
  Future<AdminRequestDetail> fetchRequestDetail(String requestId) =>
      _read(() async {
        final result = await _client.rpc(
          'admin_get_request',
          params: {'p_request_id': requestId},
        );
        return AdminRequestDetail.fromJson(_jsonObject(result));
      }, 'Không thể tải chi tiết yêu cầu. Vui lòng thử lại.');

  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    Map<String, dynamic> attachment,
  ) => _read(() async {
    // Re-read detail before using a private Storage path from an earlier response.
    final detail = await fetchRequestDetail(requestId);
    if (!detail.attachments.any((item) => _sameAttachment(item, attachment))) {
      throw _denied;
    }
    final path = attachment['storage_path'];
    if (path is! String || path.isEmpty) throw _denied;
    final image = await _client.storage.from(_bucket).download(path);
    _requireSession();
    return image;
  }, 'Không thể tải ảnh. Vui lòng thử lại.');

  Future<T> _read<T>(Future<T> Function() action, String failureMessage) async {
    try {
      final userId = _requireSession();
      final result = await action();
      if (_requireSession() != userId) throw _denied;
      return result;
    } on AdminRequestFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (_isAccessError(error.code, error.message)) throw _denied;
      throw AdminRequestFailure(_workflowError(error.message, failureMessage));
    } on StorageException catch (error) {
      if (_isAccessError(error.statusCode, error.message)) throw _denied;
      throw AdminRequestFailure(failureMessage);
    } on AuthException {
      throw _denied;
    } catch (_) {
      throw AdminRequestFailure(failureMessage);
    }
  }

  String _requireSession() {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.accessToken.isEmpty ||
        session.user.id.isEmpty ||
        session.isExpired) {
      throw _denied;
    }
    return session.user.id;
  }
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, dynamic>.from(value);
}

bool _sameAttachment(Map<String, dynamic> left, Map<String, dynamic> right) =>
    left['id'] == right['id'] &&
    left['request_id'] == right['request_id'] &&
    left['storage_path'] == right['storage_path'];

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

String _workflowError(String message, String fallback) {
  if (message.startsWith('Chỉ ') ||
      message.startsWith('Yêu cầu ') ||
      message.startsWith('Không thể ') ||
      message.startsWith('Không tìm thấy ') ||
      message.startsWith('Kỹ thuật viên ') ||
      message.startsWith('Vui lòng ')) {
    return message;
  }
  return fallback;
}
