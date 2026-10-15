import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../data/technician_jobs_repository.dart';
import '../models/technician_job.dart';
import 'technician_job_photo.dart';
import 'technician_job_widgets.dart';

/// Read-only job view. It belongs to the authenticated Home's local page state.
class TechnicianJobDetailPage extends StatefulWidget {
  const TechnicianJobDetailPage({
    super.key,
    required this.requestId,
    required this.repository,
    required this.onAccessDenied,
  });

  final String requestId;
  final TechnicianJobsRepository repository;
  final VoidCallback onAccessDenied;

  @override
  State<TechnicianJobDetailPage> createState() =>
      _TechnicianJobDetailPageState();
}

class _TechnicianJobDetailPageState extends State<TechnicianJobDetailPage>
    with WidgetsBindingObserver {
  TechnicianJobDetail? _detail;
  String? _error;
  bool _loading = false;
  bool _inFlight = false;
  bool _refreshQueued = false;
  bool _foreground = true;
  bool _denied = false;
  int _generation = 0;
  int _photoRevision = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    unawaited(_load());
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_load());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Do not redisplay cached personal data before the resumed check.
      _foreground = true;
      _generation++;
      setState(() {
        _detail = null;
        _photoRevision++;
      });
      _startTimer();
      unawaited(_load());
    } else {
      _foreground = false;
      _refreshTimer?.cancel();
      _generation++;
      _refreshQueued = false;
      setState(() {
        _detail = null;
        _photoRevision++;
      });
    }
  }

  @override
  void didUpdateWidget(covariant TechnicianJobDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId ||
        oldWidget.repository != widget.repository) {
      _generation++;
      _detail = null;
      _error = null;
      _denied = false;
      _photoRevision++;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!_foreground) return;
    if (_inFlight) {
      _refreshQueued = true;
      return;
    }
    _inFlight = true;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.fetchJobDetail(widget.requestId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _detail = detail;
        _denied = false;
      });
    } on TechnicianJobsFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      if (failure.accessDenied) {
        _denyAccess();
      } else {
        setState(() {
          _detail = null;
          _photoRevision++;
          _error = failure.message;
        });
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _detail = null;
        _photoRevision++;
        _error = 'Không tải được chi tiết công việc. Vui lòng thử lại.';
      });
    } finally {
      _inFlight = false;
      if (mounted) {
        setState(() => _loading = false);
        if (_refreshQueued && _foreground) {
          _refreshQueued = false;
          unawaited(_load());
        }
      }
    }
  }

  void _denyAccess() {
    if (!mounted) return;
    // One denied image invalidates the whole detail, not just that thumbnail.
    // Invalidate an overlapping detail response so it cannot restore the data.
    _generation++;
    setState(() {
      _detail = null;
      _photoRevision++;
      _loading = false;
      _denied = true;
      _error =
          'Bạn không còn quyền xem công việc này. '
          'Công việc có thể đã được chuyển cho kỹ thuật viên khác.';
    });
    widget.onAccessDenied();
  }

  @override
  void dispose() {
    _generation++;
    _detail = null;
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (_loading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: detail == null
          ? LayoutBuilder(
              builder: (context, constraints) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: TechnicianJobsMessage(
                      icon: _denied
                          ? Icons.lock_outline
                          : Icons.cloud_off_outlined,
                      message: _error ?? 'Đang kiểm tra quyền xem công việc...',
                      actionLabel: 'Thử lại',
                      onAction: _loading ? null : () => unawaited(_load()),
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              key: const Key('technician-job-detail'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading) const LinearProgressIndicator(),
                Text(
                  detail.job.requestCode,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  detail.job.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TechnicianStatusBadge(status: detail.job.status),
                ),
                const SizedBox(height: 12),
                Text(
                  detail.job.status == RepairStatus.completed
                      ? 'Công việc đã hoàn tất. Thông tin chỉ để xem.'
                      : detail.job.status == RepairStatus.cancelled
                      ? 'Công việc đã hủy. Thông tin chỉ để xem.'
                      : 'Chi tiết công việc · Chỉ xem',
                ),
                _section('Thông tin yêu cầu', [
                  _field('Phòng', detail.job.roomCode),
                  _field('Tòa nhà', detail.job.building),
                  _field('Loại sự cố', detail.job.categoryName),
                  _field('Ngày tạo', technicianDate(detail.job.createdAt)),
                  _field('Cập nhật', technicianDate(detail.job.updatedAt)),
                  _field('Mô tả', detail.job.description),
                ]),
                _section('Sinh viên liên hệ', [
                  _field('Họ tên', detail.studentName),
                  _field('Điện thoại', detail.studentPhone),
                ]),
                _section('Ảnh sự cố', [
                  _photos(
                    detail.attachments.where(
                      (photo) =>
                          photo.resultId == null && photo.feedbackId == null,
                    ),
                  ),
                ]),
                _section('Kết quả sửa chữa', [
                  if (detail.results.isEmpty)
                    const Text('Chưa có kết quả sửa chữa.'),
                  for (final result in detail.results)
                    _entry([
                      Text(
                        result.technicianName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(technicianDate(result.submittedAt)),
                      const SizedBox(height: 8),
                      Text(result.content),
                      const SizedBox(height: 8),
                      _photos(
                        detail.attachments.where(
                          (photo) => photo.resultId == result.id,
                        ),
                      ),
                    ]),
                ]),
                _section('Phản hồi của sinh viên', [
                  if (detail.feedback.isEmpty) const Text('Chưa có phản hồi.'),
                  for (final feedback in detail.feedback)
                    _entry([
                      Text(
                        feedback.kind == 'rework'
                            ? 'Yêu cầu xử lý lại'
                            : 'Mở lại yêu cầu',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${feedback.authorName} · ${technicianDate(feedback.createdAt)}',
                      ),
                      const SizedBox(height: 8),
                      Text(feedback.reason),
                      const SizedBox(height: 8),
                      _photos(
                        detail.attachments.where(
                          (photo) => photo.feedbackId == feedback.id,
                        ),
                      ),
                    ]),
                ]),
                _section('Lịch sử xử lý', [
                  if (detail.history.isEmpty)
                    const Text('Chưa có lịch sử xử lý.'),
                  for (final event in detail.history)
                    _entry([
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.history,
                            size: 18,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _actionLabel(event.action),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${event.actorName} · ${technicianDate(event.occurredAt)}',
                      ),
                      if (event.oldStatus != null || event.newStatus != null)
                        Text(
                          '${_statusLabel(event.oldStatus)} → ${_statusLabel(event.newStatus)}',
                        ),
                      if (event.note case final note?) Text(note),
                    ]),
                ]),
                _section('Lịch sử phân công', [
                  if (detail.assignments.isEmpty)
                    const Text('Chưa có lịch sử phân công.'),
                  for (final assignment in detail.assignments)
                    _entry([
                      Text(
                        assignment.technicianName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      _field('Người phân công', assignment.assignedByName),
                      _field(
                        'Phân công lúc',
                        technicianDate(assignment.assignedAt),
                      ),
                      _field(
                        'Kết thúc lúc',
                        assignment.endedAt == null
                            ? 'Đang được phân công'
                            : technicianDate(assignment.endedAt!),
                      ),
                      if (assignment.transferReason case final reason?)
                        _field('Lý do chuyển', reason),
                      if (assignment.endReason case final reason?)
                        _field('Lý do kết thúc', _assignmentEndLabel(reason)),
                    ]),
                ]),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _entry(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text('$label: $value'),
  );

  Widget _photos(Iterable<JobAttachment> attachments) {
    final photos = attachments.toList(growable: false);
    if (photos.isEmpty) return const Text('Không có ảnh đính kèm.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final photo in photos)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TechnicianJobPhoto(
              key: ValueKey('$_photoRevision:${photo.id}'),
              requestId: widget.requestId,
              attachment: photo,
              repository: widget.repository,
              onAccessDenied: _denyAccess,
            ),
          ),
      ],
    );
  }
}

String _statusLabel(String? value) {
  if (value == null) return '—';
  for (final status in RepairStatus.values) {
    if (status.databaseValue == value) return status.label;
  }
  return 'Đã cập nhật';
}

String _actionLabel(String action) => switch (action) {
  'created' || 'create' => 'Tạo yêu cầu',
  'assigned' || 'assign' => 'Phân công kỹ thuật viên',
  'started' || 'start' || 'in_progress' => 'Bắt đầu xử lý',
  'repair_reported' ||
  'result_submitted' ||
  'reported' => 'Báo cáo kết quả sửa chữa',
  'rework_requested' || 'rework' => 'Yêu cầu xử lý lại',
  'reopened' || 'reopen' => 'Mở lại yêu cầu',
  'completed' || 'complete' || 'confirmed' => 'Hoàn tất',
  'cancelled' || 'cancel' => 'Hủy yêu cầu',
  'rejected' || 'reject' => 'Từ chối yêu cầu',
  'transferred' || 'transfer' || 'transferred_out' => 'Chuyển công việc',
  _ => 'Cập nhật yêu cầu',
};

String _assignmentEndLabel(String reason) => switch (reason) {
  'transferred' => 'Đã chuyển cho kỹ thuật viên khác',
  'completed' => 'Đã hoàn tất',
  'cancelled' => 'Yêu cầu đã hủy',
  'revoked' => 'Đã thu hồi phân công',
  _ => reason,
};
