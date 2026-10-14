import 'package:flutter/material.dart';

import '../data/request_repository.dart';
import '../models/repair_request.dart';
import 'create_request_page.dart';
import 'status_chip.dart';

/// DF-008: màn "Yêu cầu của tôi" (loading / rỗng / lỗi + thử lại / danh sách).
class MyRequestsPage extends StatefulWidget {
  const MyRequestsPage({
    super.key,
    required this.repository,
    required this.roomCode,
    required this.onSignOut,
  });

  final RequestRepository repository;
  final String? roomCode; // phòng của tài khoản, null nếu chưa được gắn phòng
  final VoidCallback onSignOut;

  @override
  State<MyRequestsPage> createState() => _MyRequestsPageState();
}

class _MyRequestsPageState extends State<MyRequestsPage> {
  List<RepairRequest> _requests = [];
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load(); // gọi dữ liệu ở initState, KHÔNG gọi trong build()
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final result = await widget.repository.fetchMyRequests();
      if (mounted) setState(() => _requests = result); // đã đóng thì bỏ qua
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = 'Không tải được danh sách. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Mở form tạo; form trả về true khi tạo xong thì tải lại danh sách.
  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateRequestPage(
          repository: widget.repository,
          roomCode: widget.roomCode,
        ),
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Yêu cầu của tôi'),
      actions: [
        IconButton(
          tooltip: 'Đăng xuất',
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _openCreate,
      icon: const Icon(Icons.add),
      label: const Text('Tạo yêu cầu'),
    ),
    body: SafeArea(child: _body()),
  );

  Widget _body() {
    if (_loading && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return _Message(
        icon: Icons.error_outline,
        text: _errorText!,
        onRetry: _load,
      );
    }
    if (_requests.isEmpty) {
      return const _Message(
        icon: Icons.inbox_outlined,
        text: 'Bạn chưa có yêu cầu sửa chữa nào.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: _requests.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _RequestCard(request: _requests[index]),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final RepairRequest request;

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                request.requestCode,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(request.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '${request.categoryName} · Phòng ${request.roomCode} · ${_date(request.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

/// Dùng chung cho trạng thái rỗng và lỗi; có onRetry thì hiện nút "Thử lại".
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ],
      ),
    ),
  );
}
