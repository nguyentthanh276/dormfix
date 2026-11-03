import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/technician_tracking.dart';

abstract interface class TechnicianTrackingRepository {
  Future<List<TechnicianWorkHistoryEntry>> fetchWorkHistory();

  Future<List<TechnicianNotification>> fetchNotifications();

  Future<DateTime> markNotificationRead(String notificationId);
}

class TechnicianTrackingFailure implements Exception {
  const TechnicianTrackingFailure(this.message, {this.accessDenied = false});

  final String message;
  final bool accessDenied;

  @override
  String toString() => message;
}

class SupabaseTechnicianTrackingRepository
    implements TechnicianTrackingRepository {
  const SupabaseTechnicianTrackingRepository(this._client);

  final SupabaseClient _client;

  static const _accessFailure = TechnicianTrackingFailure(
    'Bạn không còn quyền xem thông tin này. Vui lòng đăng nhập lại.',
    accessDenied: true,
  );

  @override
  Future<List<TechnicianWorkHistoryEntry>> fetchWorkHistory() =>
      _request(() async {
        final result = await _client.rpc('technician_list_work_history');
        if (result is! List) throw const FormatException('Expected history.');
        return List<TechnicianWorkHistoryEntry>.unmodifiable(
          result.map(
            (item) => TechnicianWorkHistoryEntry.fromJson(_object(item)),
          ),
        );
      }, 'Không thể tải lịch sử công việc. Vui lòng thử lại.');

  @override
  Future<List<TechnicianNotification>> fetchNotifications() =>
      _request(() async {
        final result = await _client.rpc('technician_list_notifications');
        if (result is! List) {
          throw const FormatException('Expected notifications.');
        }
        return List<TechnicianNotification>.unmodifiable(
          result.map((item) => TechnicianNotification.fromJson(_object(item))),
        );
      }, 'Không thể tải thông báo. Vui lòng thử lại.');

  @override
  Future<DateTime> markNotificationRead(String notificationId) =>
      _request(() async {
        if (notificationId.trim().isEmpty) throw _accessFailure;
        final result = _object(
          await _client.rpc(
            'technician_mark_notification_read',
            params: {'p_notification_id': notificationId},
          ),
        );
        if (result['id'] != notificationId) throw _accessFailure;
        return trackingTimestamp(result, 'read_at');
      }, 'Không thể đánh dấu đã đọc. Vui lòng thử lại.');

  String _requireSession() {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.accessToken.isEmpty ||
        session.user.id.isEmpty ||
        session.isExpired) {
      throw _accessFailure;
    }
    return session.user.id;
  }

  Future<T> _request<T>(
    Future<T> Function() operation,
    String failureMessage,
  ) async {
    try {
      final identity = _requireSession();
      final result = await operation();
      if (_requireSession() != identity) throw _accessFailure;
      return result;
    } on TechnicianTrackingFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (_isAccessError(error.code, error.message)) throw _accessFailure;
      throw TechnicianTrackingFailure(failureMessage);
    } on AuthException catch (error) {
      if (error is AuthSessionMissingException ||
          _isAccessError(error.code, error.message) ||
          _isAccessError(error.statusCode, error.message)) {
        throw _accessFailure;
      }
      throw TechnicianTrackingFailure(failureMessage);
    } catch (_) {
      // Never expose private response fields, SQL messages, or transport data.
      throw TechnicianTrackingFailure(failureMessage);
    }
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected an object.');
  }
  return Map<String, dynamic>.from(value);
}

bool _isAccessError(String? code, String message) =>
    const {
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
    }.contains(code) ||
    (message.toLowerCase().contains('jwt') &&
        message.toLowerCase().contains('expired'));
