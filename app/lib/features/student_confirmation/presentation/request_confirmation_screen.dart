import 'package:flutter/material.dart';

import '../../../core/widgets/dormfix_app_bar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../student_requests/models/request_detail.dart';
import '../../student_requests/presentation/widgets/category_icon.dart';
import '../../student_requests/presentation/request_detail_screen.dart';
import '../data/confirmation_repository.dart';

/// Compatibility route for old notification links. Live data uses the shared
/// detail screen; the legacy mock preview is read-only.
class RequestConfirmationScreen extends StatefulWidget {
  final String requestId;
  final ConfirmationRepository repository;
  final VoidCallback? onConfirmed;

  const RequestConfirmationScreen({
    super.key,
    required this.requestId,
    required this.repository,
    this.onConfirmed,
  });

  @override
  State<RequestConfirmationScreen> createState() =>
      _RequestConfirmationScreenState();
}

class _RequestConfirmationScreenState extends State<RequestConfirmationScreen> {
  RequestDetail? _detail;
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    if (widget.repository is! AdapterConfirmationRepository) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final d = await widget.repository.fetchConfirmationDetail(
        widget.requestId,
      );
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'Không tải được thông tin xác nhận.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository is AdapterConfirmationRepository) {
      return RequestDetailScreen(
        repository: repository.requestRepository,
        requestId: widget.requestId,
        onRequestChanged: widget.onConfirmed,
      );
    }
    return Scaffold(
      appBar: const DormFixAppBar(title: 'Xác nhận hoàn tất'),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return ErrorView(message: _errorText!, onRetry: _load);
    }
    if (_detail == null) {
      return const SizedBox.shrink();
    }

    final d = _detail!;
    final r = d.request;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Banner thông báo mục đích màn hình
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200, width: 0.8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_outlined,
                color: Colors.orange.shade800,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Đây là màn hình xác nhận nghiệm thu kết quả sửa chữa. Hãy kiểm tra thực tế tại phòng trước khi xác nhận.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Thông tin yêu cầu
        SectionCard(
          title: 'Thông tin sự cố',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      r.requestCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  StatusChip(r.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                r.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    categoryIcon(r.categoryName),
                    size: 16,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    r.categoryName,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.meeting_room_outlined,
                    size: 16,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Phòng ${r.roomCode}',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                d.description,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Báo cáo hoàn tất của kỹ thuật viên
        SectionCard(
          title: 'Báo cáo kỹ thuật viên',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.build_circle,
                  color: Colors.green.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.technicianName != null
                          ? 'Kỹ thuật viên: ${d.technicianName}'
                          : 'Kỹ thuật viên đã xử lý sự cố',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d.latestResult?.content ?? 'Thiết bị đã được kiểm tra và sửa xong. Vui lòng kiểm tra và xác nhận hoàn tất hoặc gửi yêu cầu sửa lại nếu chưa đạt.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
