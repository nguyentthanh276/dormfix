import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import 'notification_repository.dart';

class NotificationFailure implements Exception {
  const NotificationFailure(this.message, {this.accessDenied = false});

  final String message;
  final bool accessDenied;

  @override
  String toString() => message;
}

/// Supabase adapter for DF-017. Writes go through guarded student RPCs.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _accessFailure = NotificationFailure(
    'Bạn không còn quyền xem thông báo. Vui lòng đăng nhập lại.',
    accessDenied: true,
  );

  @override
  Future<List<AppNotification>> fetchNotifications() =>
      _request((userId) async {
        final data = await _client
            .from('notifications')
            .select()
            .eq('recipient_id', userId)
            .order('created_at', ascending: false)
            .order('id', ascending: false);

        return data.map((row) {
          final map = _object(row);
          if (map['recipient_id'] != userId) throw _accessFailure;
          if (!map.containsKey('read_at')) {
            throw const FormatException('Missing read state.');
          }
          return AppNotification(
            id: _text(map, 'id'),
            recipientId: userId,
            requestId: _text(map, 'request_id'),
            eventType: NotificationEventType.fromDb(_text(map, 'event_type')),
            message: _text(map, 'message'),
            createdAt: _timestamp(map, 'created_at'),
            readAt: map['read_at'] == null ? null : _timestamp(map, 'read_at'),
          );
        }).toList();
      }, 'Không thể tải thông báo. Vui lòng thử lại.');

  @override
  Future<void> markAsRead(String notificationId) => _request((_) async {
    if (notificationId.trim().isEmpty) throw _accessFailure;
    final receipt = _object(
      await _client.rpc(
        'student_mark_notification_read',
        params: {'p_notification_id': notificationId},
      ),
    );
    if (receipt.length != 2 || receipt['id'] != notificationId) {
      throw const FormatException('Invalid notification receipt.');
    }
    _timestamp(receipt, 'read_at');
  }, 'Không thể đánh dấu đã đọc. Vui lòng thử lại.');

  @override
  Future<void> markAllAsRead() => _request((_) async {
    final receipt = _object(
      await _client.rpc('student_mark_all_notifications_read'),
    );
    final count = receipt['updated_count'];
    if (receipt.length != 2 || count is! int || count < 0) {
      throw const FormatException('Invalid notification receipt.');
    }
    _timestamp(receipt, 'read_at');
  }, 'Không thể đánh dấu tất cả đã đọc. Vui lòng thử lại.');

  @override
  Future<int> getUnreadCount() => _request((userId) async {
    return await _client
        .from('notifications')
        .count(CountOption.exact)
        .eq('recipient_id', userId)
        .isFilter('read_at', null);
  }, 'Không thể tải số thông báo chưa đọc. Vui lòng thử lại.');

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
    Future<T> Function(String userId) operation,
    String failureMessage,
  ) async {
    try {
      final identity = _requireSession();
      var identityChanged = false;
      // Remember logout/account changes even if the original user signs back in
      // before a slow response arrives. Token refresh for the same user is safe.
      final subscription = _client.auth.onAuthStateChange.listen((state) {
        if (state.session?.user.id != identity) identityChanged = true;
      }, onError: (Object _) => identityChanged = true);
      try {
        final result = await operation(identity);
        if (identityChanged || _requireSession() != identity) {
          throw _accessFailure;
        }
        return result;
      } finally {
        await subscription.cancel();
      }
    } on NotificationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (_isAccessError(error.code)) throw _accessFailure;
      throw NotificationFailure(failureMessage);
    } on AuthException catch (error) {
      if (error is AuthSessionMissingException ||
          _isAccessError(error.code) ||
          _isAccessError(error.statusCode)) {
        throw _accessFailure;
      }
      throw NotificationFailure(failureMessage);
    } catch (_) {
      // Do not expose server messages, SQL details, response data or tokens.
      throw NotificationFailure(failureMessage);
    }
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected an object.');
  }
  return Map<String, dynamic>.from(value);
}

String _text(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected text.');
  }
  return value;
}

DateTime _timestamp(Map<String, dynamic> object, String key) {
  final value = _text(object, key);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Expected timestamp with timezone.');
  }
  return DateTime.parse(value).toUtc();
}

bool _isAccessError(String? code) => const {
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
}.contains(code);
