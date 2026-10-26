import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/request_repository.dart';
import '../models/request_detail.dart';
import 'edit_request_screen.dart';
import 'widgets/category_icon.dart';
import 'widgets/status_timeline.dart';

/// DF-010: Màn hình chi tiết yêu cầu sửa chữa.
/// DF-011: Hỗ trợ nút Chỉnh sửa yêu cầu khi ở trạng thái Chờ tiếp nhận (pending).
class RequestDetailScreen extends StatefulWidget {
  final RequestRepository repository;
  final String requestId;

  const RequestDetailScreen({
    super.key,
    required this.repository,
    required this.requestId,
  });

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  RequestDetail? _detail;
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
      final result = await widget.repository.fetchRequestDetail(
        widget.requestId,
      );
      if (mounted) setState(() => _detail = result);
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = 'Không tải được chi tiết. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _navigateToEdit() async {
    if (_detail == null) return;
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditRequestScreen(
          repository: widget.repository,
          detail: _detail!,
          onUpdated: _load,
        ),
      ),
    );
    if (updated == true) {
      _load();
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final canEdit = d?.request.status == RepairStatus.pending;

    return Scaffold(
      appBar: AppBar(
        title: Text(d?.request.requestCode ?? 'Chi tiết'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Chỉnh sửa yêu cầu',
              onPressed: _navigateToEdit,
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_errorText != null) {
      return ErrorView(message: _errorText!, onRetry: _load);
    }
    final d = _detail;
    if (_loading || d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = d.request;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Thẻ tiêu đề & trạng thái
        SectionCard(
          child: Row(
            children: [
              Icon(
                categoryIcon(r.categoryName),
                size: 32,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    StatusChip(r.status),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Nút chỉnh sửa nổi bật khi ở trạng thái Chờ tiếp nhận (DF-011)
        if (r.status == RepairStatus.pending)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: OutlinedButton.icon(
              onPressed: _navigateToEdit,
              icon: const Icon(Icons.edit_note, color: AppColors.primary),
              label: const Text(
                'Chỉnh sửa yêu cầu này',
                style: TextStyle(color: AppColors.primary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

        // Thông báo đặc biệt khi chờ sinh viên xác nhận (DF-013)
        if (r.status == RepairStatus.awaitingConfirmation)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Kỹ thuật viên đã báo cáo kết quả sửa chữa. Hãy kiểm tra kết quả bên dưới để xác nhận.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

        // Thông tin chung
        SectionCard(
          title: 'Thông tin',
          child: Column(
            children: [
              InfoRow('Loại sự cố', r.categoryName),
              InfoRow('Phòng', r.roomCode),
              InfoRow(
                'Kỹ thuật viên',
                d.technicianName == null
                    ? 'Chưa phân công'
                    : '${d.technicianName} (${d.technicianPhone ?? '-'})',
              ),
            ],
          ),
        ),

        // Mô tả sự cố
        SectionCard(title: 'Mô tả', child: Text(d.description)),

        // Tiến trình xử lý (Timeline)
        SectionCard(
          title: 'Tiến trình xử lý',
          child: StatusTimeline(entries: d.history),
        ),

        // Ảnh đính kèm từ sinh viên (DF-007 / DF-010)
        SectionCard(
          title: 'Ảnh đính kèm từ sinh viên',
          child: d.studentPhotos.isEmpty
              ? Text(
                  'Không có ảnh đính kèm.',
                  style: TextStyle(color: Colors.grey.shade600),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final photo in d.studentPhotos)
                      _photoThumbnail(photo, isResult: false),
                  ],
                ),
        ),

        // Kết quả sửa chữa từ Kỹ thuật viên (DF-026 / DF-010)
        SectionCard(
          title: 'Kết quả sửa chữa',
          child: d.results.isEmpty
              ? Text(
                  d.technicianName == null
                      ? 'Chưa có kết quả sửa chữa (chưa phân công kỹ thuật viên).'
                      : 'Kỹ thuật viên đang xử lý, chưa gửi kết quả.',
                  style: TextStyle(color: Colors.grey.shade600),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final res in d.results) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    res.technicianName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDate(res.submittedAt),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Text(
                              res.content,
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (res.photos.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Ảnh nghiệm thu kết quả:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final p in res.photos)
                                    _photoThumbnail(p, isResult: true),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _photoThumbnail(String photo, {required bool isResult}) {
    return InkWell(
      onTap: () => _viewPhotoDialog(photo, isResult: isResult),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isResult ? Colors.green.shade50 : AppColors.fieldBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isResult
                ? Colors.green.shade200
                : AppColors.accent.withAlpha(100),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isResult
                  ? Icons.assignment_turned_in_outlined
                  : Icons.image_outlined,
              size: 18,
              color: isResult ? Colors.green.shade700 : AppColors.primary,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                photo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isResult ? Colors.green.shade900 : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _viewPhotoDialog(String photo, {required bool isResult}) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text(isResult ? 'Ảnh nghiệm thu kết quả' : 'Ảnh đính kèm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image,
                      size: 48,
                      color: isResult ? Colors.green : AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      photo,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tệp: $photo',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
