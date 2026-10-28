import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../student_requests/models/repair_request.dart';
import '../../student_requests/presentation/widgets/category_icon.dart';
import '../data/confirmation_repository.dart';
import 'request_confirmation_screen.dart';

/// DF-013: Màn hình danh sách các yêu cầu đang chờ sinh viên xác nhận kết quả sửa chữa.
/// Chỉ hiển thị các yêu cầu của chính sinh viên đang đăng nhập và có trạng thái Chờ xác nhận.
class AwaitingConfirmationScreen extends StatefulWidget {
  final ConfirmationRepository repository;
  final void Function(RepairRequest request)? onSelectRequest;

  const AwaitingConfirmationScreen({
    super.key,
    required this.repository,
    this.onSelectRequest,
  });

  @override
  State<AwaitingConfirmationScreen> createState() =>
      _AwaitingConfirmationScreenState();
}

class _AwaitingConfirmationScreenState
    extends State<AwaitingConfirmationScreen> {
  List<RepairRequest> _requests = [];
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final list = await widget.repository.fetchAwaitingConfirmationRequests();
      if (mounted) setState(() => _requests = list);
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = 'Không tải được danh sách. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openConfirmation(RepairRequest request) {
    if (widget.onSelectRequest != null) {
      widget.onSelectRequest!(request);
      return;
    }
    // Mở màn hình xác nhận riêng biệt (tách bạch với chi tiết tiến độ)
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RequestConfirmationScreen(
          requestId: request.id,
          repository: widget.repository,
          onConfirmed: () {
            Navigator.of(context).pop();
            _load();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chờ xác nhận')),
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
      return const EmptyView('Không có yêu cầu nào chờ xác nhận');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _requests.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (ctx, index) => _itemCard(_requests[index]),
      ),
    );
  }

  Widget _itemCard(RepairRequest item) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade300, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openConfirmation(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    categoryIcon(item.categoryName),
                    size: 24,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  StatusChip(item.status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    item.requestCode,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.roomCode,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
              const Divider(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Kỹ thuật viên đã báo cáo hoàn tất. Nhấn để mở màn hình xác nhận.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
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
