import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../data/request_repository.dart';
import '../models/repair_request.dart';
import '../models/request_filter.dart';
import 'request_detail_screen.dart';
import 'widgets/request_card.dart';

/// DF-008: màn "Yêu cầu của tôi" (loading / rỗng / lỗi + thử lại / danh sách),
/// kèm hàng nhãn lọc theo trạng thái (DF-009).
class MyRequestsScreen extends StatefulWidget {
  final RequestRepository repository;

  const MyRequestsScreen({super.key, required this.repository});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<RepairRequest> _requests = [];
  RepairStatus? _status; // null = hiện tất cả
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yêu cầu của tôi')),
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
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              itemCount: list.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) => RequestCard(
                request: list[index],
                // Truyền id sang màn chi tiết; màn đó tự tải dữ liệu theo id.
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestDetailScreen(
                      repository: widget.repository,
                      requestId: list[index].id,
                    ),
                  ),
                ),
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
