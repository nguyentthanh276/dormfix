import '../models/app_notification.dart';

/// Hợp đồng Repository cho phân hệ Thông báo (DF-017).
abstract class NotificationRepository {
  /// Lấy danh sách thông báo của người dùng hiện tại (mới nhất xếp trước).
  Future<List<AppNotification>> fetchNotifications();

  /// Đánh dấu một thông báo cụ thể là đã đọc.
  Future<void> markAsRead(String notificationId);

  /// Đánh dấu tất cả thông báo của người dùng là đã đọc.
  Future<void> markAllAsRead();

  /// Đếm số lượng thông báo chưa đọc.
  Future<int> getUnreadCount();
}
