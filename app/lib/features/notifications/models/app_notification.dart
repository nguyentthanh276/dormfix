/// Các loại sự kiện thông báo tương thích với bảng notifications trong cơ sở dữ liệu.
enum NotificationEventType {
  assigned,
  transferredIn,
  transferredOut,
  cancelled,
  rejected,
  repairReported,
  reworkRequested,
  completed,
  other;

  static NotificationEventType fromDb(String value) {
    return switch (value) {
      'assigned' => NotificationEventType.assigned,
      'transferred_in' => NotificationEventType.transferredIn,
      'transferred_out' => NotificationEventType.transferredOut,
      'cancelled' => NotificationEventType.cancelled,
      'rejected' => NotificationEventType.rejected,
      'repair_reported' => NotificationEventType.repairReported,
      'rework_requested' => NotificationEventType.reworkRequested,
      'completed' => NotificationEventType.completed,
      _ => NotificationEventType.other,
    };
  }

  String toDb() {
    return switch (this) {
      NotificationEventType.assigned => 'assigned',
      NotificationEventType.transferredIn => 'transferred_in',
      NotificationEventType.transferredOut => 'transferred_out',
      NotificationEventType.cancelled => 'cancelled',
      NotificationEventType.rejected => 'rejected',
      NotificationEventType.repairReported => 'repair_reported',
      NotificationEventType.reworkRequested => 'rework_requested',
      NotificationEventType.completed => 'completed',
      NotificationEventType.other => 'other',
    };
  }

  String get label => switch (this) {
    NotificationEventType.assigned => 'Đã phân công',
    NotificationEventType.transferredIn => 'Nhận chuyển giao',
    NotificationEventType.transferredOut => 'Chuyển giao',
    NotificationEventType.cancelled => 'Đã hủy',
    NotificationEventType.rejected => 'Từ chối',
    NotificationEventType.repairReported => 'Đã sửa xong',
    NotificationEventType.reworkRequested => 'Yêu cầu sửa lại',
    NotificationEventType.completed => 'Hoàn tất',
    NotificationEventType.other => 'Thông báo',
  };
}

/// DF-017: Thực thể một thông báo gửi tới người dùng.
class AppNotification {
  final String id;
  final String recipientId;
  final String requestId;
  final NotificationEventType eventType;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.requestId,
    required this.eventType,
    required this.message,
    required this.createdAt,
    this.readAt,
  });

  bool get isRead => readAt != null;

  AppNotification copyWith({
    String? id,
    String? recipientId,
    String? requestId,
    NotificationEventType? eventType,
    String? message,
    DateTime? createdAt,
    DateTime? readAt,
    bool clearReadAt = false,
  }) {
    return AppNotification(
      id: id ?? this.id,
      recipientId: recipientId ?? this.recipientId,
      requestId: requestId ?? this.requestId,
      eventType: eventType ?? this.eventType,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
    );
  }
}
