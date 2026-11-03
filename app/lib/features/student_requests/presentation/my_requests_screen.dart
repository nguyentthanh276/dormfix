import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../notifications/data/mock_notification_repository.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/presentation/student_notifications_screen.dart';
import '../../student_confirmation/data/confirmation_repository.dart';
import '../../student_confirmation/presentation/awaiting_confirmation_screen.dart';
import '../../student_confirmation/presentation/request_confirmation_screen.dart';
import '../data/request_repository.dart';
import '../models/repair_request.dart';
import '../models/request_filter.dart';
import 'request_detail_screen.dart';
import 'widgets/request_card.dart';

/// DF-008: màn "Yêu cầu của tôi" (loading / rỗng / lỗi + thử lại / danh sách),
/// kèm hàng nhãn lọc theo trạng thái (DF-009) và biểu tượng Thông báo (DF-017).
class MyRequestsScreen extends StatefulWidget {
  final RequestRepository repository;
  final NotificationRepository? notificationRepository;

  const MyRequestsScreen({
    super.key,
    required this.repository,
    this.notificationRepository,
  });

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<RepairRequest> _requests = [];
  RepairStatus? _status; // null = hiện tất cả
  bool _loading = false;
  String? _errorText;
  int _unreadNotifications = 0;

  late NotificationRepository _effectiveNotificationRepo;
  int _notificationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _effectiveNotificationRepo =
        widget.notificationRepository ?? MockNotificationRepository();
    _load(); // gọi dữ liệu ở initState, KHÔNG gọi trong build()
    _loadUnreadNotifications();
  }

  @override
  void didUpdateWidget(covariant MyRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationRepository != widget.notificationRepository) {
      _effectiveNotificationRepo =
          widget.notificationRepository ?? MockNotificationRepository();
      _unreadNotifications = 0;
      _loadUnreadNotifications();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final result = await widget.repository.fetchMyRequests();
      if (mounted) {
        setState(() {
          _requests = result;
          // Ghi nhận việc về Tất cả để trạng thái cũ không tự được chọn lại.
          _status = RequestFilter.validSelection(result, _status);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = 'Không tải được danh sách. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUnreadNotifications() async {
    final generation = ++_notificationGeneration;
    try {
      final count = await _effectiveNotificationRepo.getUnreadCount();
      if (mounted && generation == _notificationGeneration) {
        setState(() => _unreadNotifications = count);
      }
    } catch (_) {
      if (mounted && generation == _notificationGeneration) {
        setState(() => _unreadNotifications = 0);
      }
    }
  }

  Future<void> _openDetail(RepairRequest item) async {
    if (item.status == RepairStatus.awaitingConfirmation) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RequestConfirmationScreen(
            requestId: item.id,
            repository: AdapterConfirmationRepository(widget.repository),
            onConfirmed: _load,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RequestDetailScreen(
            repository: widget.repository,
            requestId: item.id,
          ),
        ),
      );
    }
    if (mounted) {
      await _load();
      await _loadUnreadNotifications();
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StudentNotificationsScreen(
          notificationRepository: _effectiveNotificationRepo,
          requestRepository: widget.repository,
        ),
      ),
    );
    if (mounted) {
      await _load();
      await _loadUnreadNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yêu cầu của tôi'),
        actions: [
          IconButton(
            tooltip: 'Chờ xác nhận',
            icon: const Icon(Icons.assignment_turned_in_outlined),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => AwaitingConfirmationScreen(
                    repository: AdapterConfirmationRepository(
                      widget.repository,
                    ),
                  ),
                ),
              );
              if (mounted) await _load();
            },
          ),
          IconButton(
            tooltip: 'Thông báo',
            icon: _unreadNotifications > 0
                ? Badge.count(
                    count: _unreadNotifications,
                    child: const Icon(Icons.notifications_outlined),
                  )
                : const Icon(Icons.notifications_outlined),
            onPressed: _openNotifications,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return ErrorView(message: _errorText!, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return const EmptyView('Bạn chưa có yêu cầu sửa chữa nào');
    }

    // Chỉ hiện nhãn của những trạng thái đang có trong danh sách.
    final statuses = RequestFilter.availableStatuses(_requests);
    // Trạng thái đang chọn có thể đã biến mất sau khi tải lại -> coi như "Tất cả".
    final selected = RequestFilter.validSelection(_requests, _status);
    final list = RequestFilter.byStatus(_requests, selected);

    return Column(
      children: [
        if (statuses.length > 1)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                _chip(null, 'Tất cả (${_requests.length})', selected),
                for (final s in statuses)
                  _chip(
                    s,
                    '${s.label} (${RequestFilter.count(_requests, s)})',
                    selected,
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _load();
              await _loadUnreadNotifications();
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              itemCount: list.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) => RequestCard(
                request: list[index],
                // Mở màn hình xác nhận riêng nếu là awaitingConfirmation, ngược lại mở chi tiết tiến độ
                onTap: () => _openDetail(list[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // [selected] là trạng thái đang chọn THỰC SỰ (đã qua validSelection), để nhãn sáng đúng.
  Widget _chip(RepairStatus? status, String label, RepairStatus? selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected == status,
        onSelected: (_) => setState(() => _status = status),
      ),
    );
  }
}
