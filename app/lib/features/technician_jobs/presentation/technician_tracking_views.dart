// Nguyễn Tiến Thành — DF-027
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/technician_tracking_repository.dart';
import '../models/technician_tracking.dart';
import 'technician_job_widgets.dart';

class TechnicianWorkHistoryView extends StatefulWidget {
  const TechnicianWorkHistoryView({
    super.key,
    required this.repository,
    required this.onOpenDetail,
    this.refreshRevision = 0,
  });

  final TechnicianTrackingRepository? repository;
  final ValueChanged<String> onOpenDetail;
  final int refreshRevision;

  @override
  State<TechnicianWorkHistoryView> createState() =>
      _TechnicianWorkHistoryViewState();
}

class _TechnicianWorkHistoryViewState extends State<TechnicianWorkHistoryView>
    with WidgetsBindingObserver {
  List<TechnicianWorkHistoryEntry> _entries = [];
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TechnicianWorkHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _entries = [];
      unawaited(_load());
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // DF-027: Tải lịch sử theo từng lần phân công.
      final entries = await repository.fetchWorkHistory();
      if (!mounted || generation != _generation) return;
      setState(() => _entries = entries);
    } on TechnicianTrackingFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = [];
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = [];
        _error = 'Không thể tải lịch sử công việc. Vui lòng thử lại.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _entries = [];
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const TechnicianJobsMessage(
        icon: Icons.cloud_off_outlined,
        message:
            'Lịch sử công việc chưa sẵn sàng. Vui lòng liên hệ quản trị viên.',
      );
    }
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _entries.isEmpty) {
      return _TrackingEmptyState(
        message: _error ?? 'Bạn chưa có lịch sử phân công công việc.',
        hasError: _error != null,
        onRefresh: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('technician-work-history-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return Card(
            key: ValueKey('history-${entry.assignmentId}'),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: entry.canOpenDetail
                  ? () => widget.onOpenDetail(entry.requestId!)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.requestCode,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Phòng ${entry.roomCode}'),
                    Text('Được giao: ${technicianDate(entry.assignedAt)}'),
                    if (entry.endedAt case final endedAt?)
                      Text('Kết thúc phân công: ${technicianDate(endedAt)}'),
                    const SizedBox(height: 8),
                    if (entry.canOpenDetail) ...[
                      TechnicianStatusBadge(status: entry.status!),
                      const SizedBox(height: 8),
                      const Text('Xem chi tiết công việc'),
                    ] else
                      const Text('Đã kết thúc phân công · Chỉ xem tóm tắt'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class TechnicianNotificationsView extends StatefulWidget {
  const TechnicianNotificationsView({
    super.key,
    required this.repository,
    required this.onOpenDetail,
    this.refreshRevision = 0,
  });

  final TechnicianTrackingRepository? repository;
  final ValueChanged<String> onOpenDetail;
  final int refreshRevision;

  @override
  State<TechnicianNotificationsView> createState() =>
      _TechnicianNotificationsViewState();
}

class _TechnicianNotificationsViewState
    extends State<TechnicianNotificationsView>
    with WidgetsBindingObserver {
  List<TechnicianNotification> _notifications = [];
  final Set<String> _markingRead = {};
  final Map<String, DateTime> _acknowledgedReads = {};
  String? _error;
  bool _loading = true;
  int _generation = 0;
  int _identityGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TechnicianNotificationsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _identityGeneration++;
      _notifications = [];
      _markingRead.clear();
      _acknowledgedReads.clear();
      unawaited(_load());
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // DF-027: Tải thông báo và giữ mốc đọc đã được xác nhận.
      final notifications = await repository.fetchNotifications();
      if (!mounted || generation != _generation) return;
      setState(() {
        _notifications = notifications
            .map((notification) {
              final readAt = _acknowledgedReads[notification.id];
              return notification.readAt == null && readAt != null
                  ? notification.copyWithReadAt(readAt)
                  : notification;
            })
            .toList(growable: false);
      });
    } on TechnicianTrackingFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (failure.accessDenied) {
          _identityGeneration++;
          _markingRead.clear();
          _acknowledgedReads.clear();
        }
        _notifications = [];
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _notifications = [];
        _error = 'Không thể tải thông báo. Vui lòng thử lại.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  // DF-027: Dùng mốc thời gian từ server để cập nhật trạng thái đã đọc.
  Future<bool> _markRead(TechnicianNotification notification) async {
    final repository = widget.repository;
    if (repository == null || _markingRead.contains(notification.id)) {
      return false;
    }
    if (notification.readAt != null) return true;
    final identityGeneration = _identityGeneration;
    setState(() => _markingRead.add(notification.id));
    try {
      final readAt = await repository.markNotificationRead(notification.id);
      if (!mounted || identityGeneration != _identityGeneration) return false;
      setState(() {
        _acknowledgedReads[notification.id] = readAt;
        _notifications = _notifications
            .map(
              (item) => item.id == notification.id
                  ? item.copyWithReadAt(readAt)
                  : item,
            )
            .toList(growable: false);
      });
      return true;
    } on TechnicianTrackingFailure catch (failure) {
      if (!mounted || identityGeneration != _identityGeneration) return false;
      if (failure.accessDenied) {
        setState(() {
          _generation++;
          _identityGeneration++;
          _markingRead.clear();
          _acknowledgedReads.clear();
          _notifications = [];
          _error = failure.message;
          _loading = false;
        });
      } else {
        _showMessage(failure.message);
      }
      return false;
    } catch (_) {
      if (mounted && identityGeneration == _identityGeneration) {
        _showMessage('Không thể đánh dấu đã đọc. Vui lòng thử lại.');
      }
      return false;
    } finally {
      if (mounted && identityGeneration == _identityGeneration) {
        setState(() => _markingRead.remove(notification.id));
      }
    }
  }

  // DF-027: Đánh dấu đã đọc rồi mở chi tiết nếu thông báo còn quyền truy cập.
  Future<void> _open(TechnicianNotification notification) async {
    final identityGeneration = _identityGeneration;
    if (!await _markRead(notification) ||
        !mounted ||
        identityGeneration != _identityGeneration) {
      return;
    }
    if (notification.canOpenDetail) {
      // The detail RPC checks assignment again after this list response.
      widget.onOpenDetail(notification.requestId!);
    } else {
      _showMessage('Bạn không còn quyền mở chi tiết công việc này.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _generation++;
    _identityGeneration++;
    _notifications = [];
    _acknowledgedReads.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const TechnicianJobsMessage(
        icon: Icons.cloud_off_outlined,
        message: 'Thông báo chưa sẵn sàng. Vui lòng liên hệ quản trị viên.',
      );
    }
    if (_loading && _notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _notifications.isEmpty) {
      return _TrackingEmptyState(
        message: _error ?? 'Bạn chưa có thông báo nào.',
        hasError: _error != null,
        onRefresh: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('technician-notifications-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          final unread = notification.readAt == null;
          final marking = _markingRead.contains(notification.id);
          return Card(
            key: ValueKey('notification-${notification.id}'),
            child: ListTile(
              leading: Icon(
                unread ? Icons.notifications_active : Icons.notifications_none,
                color: unread ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(
                notification.message,
                style: TextStyle(
                  fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                '${technicianDate(notification.createdAt)} · '
                '${unread ? 'Chưa đọc' : 'Đã đọc'}',
              ),
              isThreeLine: true,
              onTap: marking ? null : () => unawaited(_open(notification)),
              trailing: marking
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : unread
                  ? IconButton(
                      tooltip: 'Đánh dấu đã đọc',
                      icon: const Icon(Icons.mark_email_read_outlined),
                      onPressed: () => unawaited(_markRead(notification)),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _TrackingEmptyState extends StatelessWidget {
  const _TrackingEmptyState({
    required this.message,
    required this.hasError,
    required this.onRefresh,
  });

  final String message;
  final bool hasError;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: TechnicianJobsMessage(
              icon: hasError ? Icons.cloud_off_outlined : Icons.history,
              message: message,
              actionLabel: 'Thử lại',
              onAction: () => unawaited(onRefresh()),
            ),
          ),
        ],
      ),
    ),
  );
}
