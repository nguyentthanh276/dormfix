import 'package:flutter/material.dart';

import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/request_repository.dart';
import '../models/request_detail.dart';
import 'widgets/category_icon.dart';
import 'widgets/status_timeline.dart';

/// DF-010: chi tiết một yêu cầu. Nhận requestId từ danh sách, tự tải dữ liệu ở initState.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_detail?.request.requestCode ?? 'Chi tiết')),
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
        SectionCard(
          child: Row(
            children: [
              Icon(categoryIcon(r.categoryName), size: 32),
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
        SectionCard(title: 'Mô tả', child: Text(d.description)),
        SectionCard(
          title: 'Tiến trình xử lý',
          child: StatusTimeline(entries: d.history),
        ),
      ],
    );
  }
}
