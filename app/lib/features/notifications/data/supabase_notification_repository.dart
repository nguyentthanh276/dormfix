import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import 'notification_repository.dart';

/// Triển khai kết nối Supabase thật cho phân hệ Thông báo (DF-017).
class SupabaseNotificationRepository implements NotificationRepository {
  final SupabaseClient _client;

  SupabaseNotificationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Chưa đăng nhập.');
    }

    final data = await _client
        .from('notifications')
        .select()
        .eq('recipient_id', userId)
        .order('created_at', ascending: false);

    return (data as List<dynamic>).map((row) {
      final map = row as Map<String, dynamic>;
      return AppNotification(
        id: map['id'] as String,
        recipientId: map['recipient_id'] as String,
        requestId: map['request_id'] as String,
        eventType: NotificationEventType.fromDb(map['event_type'] as String),
        message: map['message'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        readAt: map['read_at'] != null
            ? DateTime.parse(map['read_at'] as String)
            : null,
      );
    }).toList();
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Chưa đăng nhập.');
    }

    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .match({'id': notificationId, 'recipient_id': userId});
  }

  @override
  Future<void> markAllAsRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Chưa đăng nhập.');
    }

    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('recipient_id', userId)
        .filter('read_at', 'is', null);
  }

  @override
  Future<int> getUnreadCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    final count = await _client
        .from('notifications')
        .count(CountOption.exact)
        .eq('recipient_id', userId)
        .filter('read_at', 'is', null);

    return count;
  }
}
