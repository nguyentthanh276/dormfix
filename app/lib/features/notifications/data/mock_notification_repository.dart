import '../models/app_notification.dart';
import 'notification_repository.dart';

/// Triển khai Mock phục vụ phát triển độc lập và kiểm thử (DF-017).
class MockNotificationRepository implements NotificationRepository {
  final Duration delay;
  final List<AppNotification> _notifications;
  bool failFetch = false;
  bool failAction = false;

  MockNotificationRepository({
    this.delay = const Duration(milliseconds: 150),
    List<AppNotification>? notifications,
  }) : _notifications =
           notifications ??
           [
             AppNotification(
               id: 'notif-1',
               recipientId: 'current-student',
               requestId: 'mock-confirm-1',
               eventType: NotificationEventType.repairReported,
               message: 'Yêu cầu DF000004 (Bình nóng lạnh không vào điện) đã được kỹ thuật viên sửa xong. Vui lòng kiểm tra và nghiệm thu.',
               createdAt: DateTime.now().subtract(const Duration(minutes: 35)),
               readAt: null, // Chưa đọc
             ),
             AppNotification(
               id: 'notif-2',
               recipientId: 'current-student',
               requestId: 'mock-2',
               eventType: NotificationEventType.assigned,
               message: 'Yêu cầu DF000002 (Vòi nước rò rỉ) đã được phân công cho Kỹ thuật viên Lê Văn Cường.',
               createdAt: DateTime.now().subtract(const Duration(hours: 2)),
               readAt: null, // Chưa đọc
             ),
             AppNotification(
               id: 'notif-3',
               recipientId: 'current-student',
               requestId: 'mock-1',
               eventType: NotificationEventType.completed,
               message: 'Yêu cầu DF000001 (Bóng đèn phòng bị cháy) đã hoàn tất việc sửa chữa và đóng phiếu.',
               createdAt: DateTime.now().subtract(const Duration(days: 1)),
               readAt: DateTime.now().subtract(const Duration(hours: 20)),
             ),
             AppNotification(
               id: 'notif-4',
               recipientId: 'current-student',
               requestId: 'mock-3',
               eventType: NotificationEventType.rejected,
               message: 'Yêu cầu DF000003 (Cửa sổ bị kẹt chốt) bị từ chối do thông tin chưa đầy đủ.',
               createdAt: DateTime.now().subtract(const Duration(days: 3)),
               readAt: DateTime.now().subtract(const Duration(days: 2)),
             ),
           ];

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failFetch) {
      throw Exception('Không thể tải danh sách thông báo. Vui lòng thử lại.');
    }
    // Sắp xếp thông báo mới nhất lên đầu
    final sorted = List<AppNotification>.from(_notifications);
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failAction) {
      throw Exception('Không thể cập nhật trạng thái thông báo.');
    }
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1 && _notifications[index].readAt == null) {
      _notifications[index] = _notifications[index].copyWith(
        readAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> markAllAsRead() async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failAction) {
      throw Exception('Không thể đánh dấu tất cả là đã đọc.');
    }
    final now = DateTime.now();
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].readAt == null) {
        _notifications[i] = _notifications[i].copyWith(readAt: now);
      }
    }
  }

  @override
  Future<int> getUnreadCount() async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return _notifications.where((n) => !n.isRead).length;
  }
}
