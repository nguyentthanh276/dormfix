import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../student_confirmation/data/confirmation_repository.dart';
import '../../student_confirmation/presentation/request_confirmation_screen.dart';
import '../../student_requests/data/request_repository.dart';
import '../../student_requests/presentation/request_detail_screen.dart';
import '../data/notification_repository.dart';
import '../models/app_notification.dart';

/// DF-017: Màn hình Xem & đọc thông báo của Sinh viên.
class StudentNotificationsScreen extends StatefulWidget {
  final NotificationRepository notificationRepository;
  final RequestRepository requestRepository;

  const StudentNotificationsScreen({
    super.key,
    required this.notificationRepository,
    required this.requestRepository,
  });

  @override
  State<StudentNotificationsScreen> createState() =>
      _StudentNotificationsScreenState();
}

class _StudentNotificationsScreenState
    extends State<StudentNotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _loading = false;
  String? _errorText;
  bool _opening = false;
  bool _markingAll = false;
  int _generation = 0;
  int _identityGeneration = 0;
  final Map<String, DateTime> _acknowledgedReads = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudentNotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationRepository != widget.notificationRepository ||
        oldWidget.requestRepository != widget.requestRepository) {
      _identityGeneration++;
      _notifications = [];
      _acknowledgedReads.clear();
      _opening = false;
      _markingAll = false;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _identityGeneration++;
    _notifications = [];
    _acknowledgedReads.clear();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final list = await widget.notificationRepository.fetchNotifications();
      if (!mounted || generation != _generation) return;
      setState(() {
        _notifications = list.map((item) {
          final readAt = _acknowledgedReads[item.id];
          return !item.isRead && readAt != null
              ? item.copyWith(readAt: readAt)
              : item;
        }).toList();
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _identityGeneration++;
          _notifications = [];
          _acknowledgedReads.clear();
          _opening = false;
          _markingAll = false;
          _errorText = 'Không thể tải thông báo. Hãy thử lại.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _markAllAsRead() async {
    if (_opening || _markingAll) return;
    final identityGeneration = _identityGeneration;
    final unreadIds = _notifications
        .where((item) => !item.isRead)
        .map((item) => item.id)
        .toSet();
    setState(() => _markingAll = true);
    try {
      await widget.notificationRepository.markAllAsRead();
      if (!mounted || identityGeneration != _identityGeneration) return;
      setState(() {
        final now = DateTime.now();
        for (final id in unreadIds) {
          _acknowledgedReads[id] = now;
        }
        _notifications = [
          for (final n in _notifications)
            n.isRead || !unreadIds.contains(n.id) ? n : n.copyWith(readAt: now),
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đánh dấu tất cả là đã đọc')),
      );
    } catch (_) {
      if (!mounted || identityGeneration != _identityGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thao tác thất bại. Vui lòng thử lại.')),
      );
    } finally {
      if (mounted && identityGeneration == _identityGeneration) {
        setState(() => _markingAll = false);
      }
    }
  }

  Future<void> _openNotification(AppNotification item) async {
    if (_opening || _markingAll) return;
    final identityGeneration = _identityGeneration;
    setState(() => _opening = true);
    try {
      // 1. Đánh dấu đã đọc
      if (!item.isRead) {
        await widget.notificationRepository.markAsRead(item.id);
        if (!mounted || identityGeneration != _identityGeneration) return;
        setState(() {
          _acknowledgedReads[item.id] = DateTime.now();
          final index = _notifications.indexWhere((n) => n.id == item.id);
          if (index != -1) {
            _notifications[index] = item.copyWith(
              readAt: _acknowledgedReads[item.id],
            );
          }
        });
      }
      if (!mounted || identityGeneration != _identityGeneration) return;

      // 2. Mở đúng màn hình tương ứng với trạng thái yêu cầu
      if (item.eventType == NotificationEventType.repairReported) {
        // Trường hợp kỹ thuật viên đã sửa xong: mở màn hình xác nhận nghiệm thu (DF-013)
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RequestConfirmationScreen(
              requestId: item.requestId,
              repository: AdapterConfirmationRepository(
                widget.requestRepository,
              ),
            ),
          ),
        );
      } else {
        // Các trường hợp khác: mở màn hình chi tiết yêu cầu (DF-010)
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RequestDetailScreen(
              repository: widget.requestRepository,
              requestId: item.requestId,
            ),
          ),
        );
      }

      if (mounted && identityGeneration == _identityGeneration) {
        await _load();
      }
    } catch (_) {
      if (mounted && identityGeneration == _identityGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở thông báo. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted && identityGeneration == _identityGeneration) {
        setState(() => _opening = false);
      }
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} $h:$min';
  }

  IconData _eventIcon(NotificationEventType type) => switch (type) {
    NotificationEventType.assigned => Icons.engineering_outlined,
    NotificationEventType.repairReported => Icons.assignment_turned_in_outlined,
    NotificationEventType.completed => Icons.check_circle_outline,
    NotificationEventType.rejected => Icons.cancel_outlined,
    NotificationEventType.cancelled => Icons.highlight_off_outlined,
    NotificationEventType.transferredIn ||
    NotificationEventType.transferredOut => Icons.swap_horiz_outlined,
    NotificationEventType.reworkRequested => Icons.replay_outlined,
    NotificationEventType.other => Icons.notifications_none_outlined,
  };

  Color _eventColor(NotificationEventType type) => switch (type) {
    NotificationEventType.assigned => Colors.blue.shade700,
    NotificationEventType.repairReported => AppColors.primary,
    NotificationEventType.completed => Colors.green.shade700,
    NotificationEventType.rejected => Colors.red.shade700,
    NotificationEventType.cancelled => Colors.grey.shade700,
    NotificationEventType.transferredIn ||
    NotificationEventType.transferredOut => Colors.purple.shade700,
    NotificationEventType.reworkRequested => Colors.amber.shade900,
    NotificationEventType.other => AppColors.primaryDark,
  };

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          if (hasUnread)
            IconButton(
              tooltip: 'Đánh dấu tất cả đã đọc',
              icon: const Icon(Icons.done_all_rounded),
              onPressed: _opening || _markingAll ? null : _markAllAsRead,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return ErrorView(message: _errorText!, onRetry: _load);
    }
    if (_notifications.isEmpty) {
      return const EmptyView('Bạn chưa có thông báo nào');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: _notifications.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _notifications[index];
          return _buildNotificationCard(item);
        },
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification item) {
    final color = _eventColor(item.eventType);
    final icon = _eventIcon(item.eventType);

    return Material(
      color: item.isRead ? Colors.white : AppColors.fieldBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: item.isRead
              ? Colors.black.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.35),
          width: item.isRead ? 0.8 : 1.2,
        ),
      ),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _opening || _markingAll ? null : () => _openNotification(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon biểu thị loại sự kiện
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              // Nội dung thông báo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.eventType.label,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatTime(item.createdAt),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                        if (!item.isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.message,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: item.isRead
                            ? FontWeight.normal
                            : FontWeight.w600,
                        color: Colors.grey.shade900,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
