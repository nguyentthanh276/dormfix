// Người đóng góp: Nguyễn Tiến Thành | UC: DF-022, DF-023, DF-024, DF-025, DF-026.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../data/technician_jobs_repository.dart';
import '../data/technician_workflow_repository.dart';
import '../models/technician_job.dart';
import '../models/technician_workflow.dart';
import 'technician_job_photo.dart';
import 'technician_job_widgets.dart';
import 'technician_result_form.dart';

/// Belongs to the authenticated Home's local page state, including its draft.
class TechnicianJobDetailPage extends StatefulWidget {
  const TechnicianJobDetailPage({
    super.key,
    required this.requestId,
    required this.repository,
    required this.onAccessDenied,
    this.workflowRepository,
    this.onJobChanged,
    this.pickResultImages,
  });

  final String requestId;
  final TechnicianJobsRepository repository;
  final VoidCallback onAccessDenied;
  final TechnicianWorkflowRepository? workflowRepository;
  final VoidCallback? onJobChanged;
  final TechnicianResultImagePicker? pickResultImages;

  @override
  State<TechnicianJobDetailPage> createState() =>
      TechnicianJobDetailPageState();
}

class TechnicianJobDetailPageState extends State<TechnicianJobDetailPage>
    with WidgetsBindingObserver {
  TechnicianJobDetail? _detail;
  String? _error;
  bool _loading = false;
  bool _inFlight = false;
  bool _refreshQueued = false;
  bool _foreground = true;
  bool _denied = false;
  bool _writing = false;
  bool _showResultForm = false;
  String? _actionMessage;
  TechnicianResultSubmission? _uncertainSubmission;
  final _scrollController = ScrollController();
  bool _returnToTop = false;
  bool _pickingImages = false;
  bool _preservePickerDraft = false;
  bool _resumeChecking = false;
  int _generation = 0;
  int _photoRevision = 0;
  Timer? _refreshTimer;

  /// Home asks before discarding the inline result form. In-flight mutations
  /// keep their existing completion/identity guards when the user leaves.
  Future<bool> confirmLeave() async {
    if (!_showResultForm || _writing) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bỏ kết quả đang nhập?'),
            content: const Text(
              'Nội dung và ảnh chưa gửi sẽ bị bỏ khi quay lại danh sách.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Tiếp tục nhập'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Bỏ thay đổi'),
              ),
            ],
          ),
        ) ??
        false;
  }

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
        if (!_preservePickerDraft) {
          _detail = null;
          _clearDraft();
        }
        _resumeChecking = _preservePickerDraft;
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
        // The system gallery backgrounds the app. Keep its draft mounted but
        // hidden; the resumed server check decides whether it can reappear.
        _preservePickerDraft = _preservePickerDraft || _pickingImages;
        _resumeChecking = _preservePickerDraft;
        if (!_preservePickerDraft) {
          _detail = null;
          _clearDraft();
        }
        _photoRevision++;
      });
    }
  }

  @override
  void didUpdateWidget(covariant TechnicianJobDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId ||
        oldWidget.repository != widget.repository ||
        oldWidget.workflowRepository != widget.workflowRepository) {
      _generation++;
      _detail = null;
      _error = null;
      _denied = false;
      _clearDraft();
      _actionMessage = null;
      _resumeChecking = false;
      _preservePickerDraft = false;
      _photoRevision++;
      unawaited(_load());
    }
  }

  // DF-022: Tải chi tiết theo ID yêu cầu và bỏ phản hồi đã cũ.
  Future<void> _load() async {
    if (!_foreground) return;
    if (_inFlight || _writing) {
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
        final previous = _detail;
        final uncertain = _uncertainSubmission;
        if (uncertain != null &&
            detail.results.any((result) => result.id == uncertain.resultId)) {
          _clearDraft();
          _actionMessage = 'Đã gửi kết quả. Đang chờ sinh viên xác nhận.';
          _returnToTop = true;
          widget.onJobChanged?.call();
        } else if (_showResultForm &&
            (!_canSubmit(detail) ||
                (previous != null &&
                    detail.job.version != previous.job.version))) {
          _clearDraft();
          _actionMessage =
              'Công việc đã thay đổi. Vui lòng kiểm tra trạng thái mới.';
          _returnToTop = true;
        }
        _detail = detail;
        _denied = false;
        _resumeChecking = false;
        _preservePickerDraft = false;
      });
      if (_returnToTop) {
        _returnToTop = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
    } on TechnicianJobsFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      if (failure.accessDenied) {
        _denyAccess();
      } else {
        setState(() {
          if (_uncertainSubmission == null) {
            _detail = null;
            _clearDraft();
            _photoRevision++;
          }
          _error = failure.message;
          _resumeChecking = false;
          _preservePickerDraft = false;
        });
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_uncertainSubmission == null) {
          _detail = null;
          _clearDraft();
          _photoRevision++;
        }
        _error = 'Không tải được chi tiết công việc. Vui lòng thử lại.';
        _resumeChecking = false;
        _preservePickerDraft = false;
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
      _clearDraft();
      _actionMessage = null;
      _photoRevision++;
      _loading = false;
      _denied = true;
      _resumeChecking = false;
      _preservePickerDraft = false;
      _error =
          'Bạn không còn quyền xem công việc này. '
          'Công việc có thể đã được chuyển cho kỹ thuật viên khác.';
    });
    widget.onAccessDenied();
  }

  bool _canStart(TechnicianJobDetail detail) =>
      widget.workflowRepository != null &&
      detail.job.status == RepairStatus.assigned &&
      detail.workflow.canStart;

  bool _canContinue(TechnicianJobDetail detail) =>
      widget.workflowRepository != null &&
      detail.job.status == RepairStatus.awaitingRework &&
      detail.workflow.canContinue;

  bool _canConfirmTransfer(TechnicianJobDetail detail) =>
      widget.workflowRepository != null &&
      detail.job.status == RepairStatus.inProgress &&
      detail.workflow.canConfirmTransfer;

  bool _canSubmit(TechnicianJobDetail detail) =>
      widget.workflowRepository != null &&
      detail.job.status == RepairStatus.inProgress &&
      detail.workflow.canSubmitResult;

  void _clearDraft() {
    _showResultForm = false;
    _uncertainSubmission = null;
    _pickingImages = false;
  }

  // DF-023: Gửi ID và phiên bản để bắt đầu xử lý.
  Future<void> _startJob() async {
    final detail = _detail;
    if (detail == null || !_canStart(detail)) return;
    await _write(
      () => widget.workflowRepository!.startJob(
        requestId: detail.job.id,
        expectedVersion: detail.job.version,
      ),
    );
  }

  // DF-024: Tiếp tục công việc đang Chờ xử lý lại khi có quyền.
  Future<void> _continueJob() async {
    final detail = _detail;
    if (detail == null || !_canContinue(detail)) return;
    await _write(
      () => widget.workflowRepository!.continueJob(
        requestId: detail.job.id,
        expectedVersion: detail.job.version,
      ),
      successMessage: 'Đã tiếp tục xử lý công việc.',
    );
  }

  // DF-025: Xác nhận tiếp tục sau lần chuyển giao hiện tại.
  Future<void> _confirmTransfer() async {
    final detail = _detail;
    if (detail == null || !_canConfirmTransfer(detail)) return;
    await _write(
      () => widget.workflowRepository!.confirmTransfer(
        requestId: detail.job.id,
        expectedVersion: detail.job.version,
      ),
      successMessage: 'Đã xác nhận tiếp tục công việc.',
    );
  }

  // DF-026: Kiểm tra ID và phiên bản trước khi gửi kết quả.
  Future<void> _submitResult(TechnicianResultSubmission submission) async {
    final detail = _detail;
    if (detail == null ||
        !_canSubmit(detail) ||
        detail.job.id != submission.requestId ||
        detail.job.version != submission.expectedVersion) {
      return;
    }
    await _write(
      () => widget.workflowRepository!.submitResult(submission),
      submission: submission,
    );
  }

  // DF-023–DF-026: Chặn thao tác chồng nhau và tải lại chi tiết nếu còn quyền.
  Future<void> _write(
    Future<TechnicianWriteReceipt> Function() operation, {
    TechnicianResultSubmission? submission,
    String successMessage = 'Đã bắt đầu xử lý công việc.',
  }) async {
    if (_writing || _inFlight || !_foreground || _denied) return;
    // Home can remain visible after this detail is closed during the write.
    // Capture its session-scoped callback before awaiting or being disposed.
    final onWriteFinished = widget.onJobChanged;
    final generation = ++_generation;
    setState(() {
      _writing = true;
      _actionMessage = null;
    });
    try {
      await operation();
      if (!mounted || generation != _generation) return;
      setState(() {
        _clearDraft();
        _detail = null;
        _photoRevision++;
        _returnToTop = true;
        _actionMessage = submission == null
            ? successMessage
            : 'Đã gửi kết quả. Đang chờ sinh viên xác nhận.';
      });
    } on TechnicianWorkflowFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      if (failure.accessDenied) {
        _denyAccess();
      } else {
        setState(() {
          _actionMessage = failure.message;
          if (failure.conflict) {
            _clearDraft();
            _detail = null;
            _photoRevision++;
            _returnToTop = true;
          } else if (failure.uncertain && submission != null) {
            _uncertainSubmission = submission;
          }
        });
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _actionMessage = 'Chưa xác nhận được thao tác. Vui lòng kiểm tra trạng thái và thử lại.';
        if (submission != null) _uncertainSubmission = submission;
      });
    } finally {
      onWriteFinished?.call();
      if (mounted) {
        setState(() => _writing = false);
        // Revalidate after every outcome, including a lost network response.
        _refreshQueued = false;
        if (_foreground && !_denied) await _load();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _detail = null;
    _clearDraft();
    _refreshTimer?.cancel();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Offstage(
          offstage: !_foreground || _resumeChecking,
          child: _buildDetail(context),
        ),
        if (_foreground && _resumeChecking)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    final detail = _detail;
    if (_loading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final currentRework =
        detail != null && detail.job.status == RepairStatus.awaitingRework
        ? detail.history.reversed
              .where(
                (event) =>
                    event.newStatus ==
                        RepairStatus.awaitingRework.databaseValue &&
                    event.oldStatus != event.newStatus,
              )
              .firstOrNull
        : null;
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
              controller: _scrollController,
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
                      : _canStart(detail) ||
                            _canContinue(detail) ||
                            _canConfirmTransfer(detail) ||
                            _canSubmit(detail)
                      ? 'Chi tiết công việc'
                      : 'Chi tiết công việc · Chỉ xem',
                ),
                if (_actionMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _actionMessage!,
                      key: const Key('technician-action-message'),
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (currentRework != null &&
                    currentRework.action == _adminReworkAction &&
                    currentRework.note != null)
                  _section('Admin yêu cầu xử lý lại', [
                    Text(
                      '${currentRework.actorName} · ${technicianDate(currentRework.occurredAt)}',
                    ),
                    const SizedBox(height: 8),
                    _field('Lý do', currentRework.note!),
                  ]),
                // DF-023–DF-026: Hiện nút theo trạng thái và quyền từ máy chủ.
                if (_canStart(detail))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      key: const Key('technician-start-job'),
                      onPressed: _loading || _writing ? null : _startJob,
                      icon: _writing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _writing ? 'Đang bắt đầu...' : 'Bắt đầu xử lý',
                      ),
                    ),
                  ),
                if (_canContinue(detail))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      key: const Key('technician-continue-job'),
                      onPressed: _loading || _writing ? null : _continueJob,
                      icon: _writing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _writing ? 'Đang tiếp tục...' : 'Tiếp tục xử lý',
                      ),
                    ),
                  ),
                if (_canConfirmTransfer(detail))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      key: const Key('technician-confirm-transfer'),
                      onPressed: _loading || _writing ? null : _confirmTransfer,
                      icon: _writing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.task_alt),
                      label: Text(
                        _writing ? 'Đang xác nhận...' : 'Xác nhận tiếp tục',
                      ),
                    ),
                  ),
                if (_canSubmit(detail) && !_showResultForm)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      key: const Key('technician-open-result-form'),
                      onPressed: _loading || _writing
                          ? null
                          : () {
                              setState(() {
                                _showResultForm = true;
                                _actionMessage = null;
                              });
                            },
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Nhập kết quả sửa chữa'),
                    ),
                  ),
                if (_showResultForm && _canSubmit(detail))
                  TechnicianResultForm(
                    key: ValueKey(
                      'result-form-${detail.job.id}-${detail.job.version}',
                    ),
                    job: detail.job,
                    busy: _writing || _loading,
                    retryOnly: _uncertainSubmission != null,
                    pickImages: widget.pickResultImages,
                    onPickingChanged: (picking) => _pickingImages = picking,
                    onSubmit: _submitResult,
                    onCancel: () => setState(_clearDraft),
                  ),
                if (widget.workflowRepository != null &&
                    !_canStart(detail) &&
                    !_canContinue(detail) &&
                    !_canConfirmTransfer(detail) &&
                    !_canSubmit(detail))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_blockedMessage(detail.workflow.blockedReason)),
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

String _blockedMessage(String? reason) => switch (reason) {
  'START_REQUIRED' => 'Cần bắt đầu xử lý trước khi gửi kết quả.',
  'CONTINUE_REQUIRED' =>
    'Cần xác nhận tiếp tục xử lý trước khi gửi kết quả mới.',
  'TRANSFER_CONFIRMATION_REQUIRED' =>
    'Cần xác nhận công việc được chuyển đến trước khi gửi kết quả.',
  'ASSIGNMENT_NOT_READY' =>
    'Phân công chưa sẵn sàng để xử lý. Vui lòng tải lại hoặc liên hệ Admin.',
  _ => 'Hiện tại công việc chỉ có thể xem.',
};

String _statusLabel(String? value) {
  if (value == null) return '—';
  for (final status in RepairStatus.values) {
    if (status.databaseValue == value) return status.label;
  }
  return 'Đã cập nhật';
}

const _adminReworkAction = 'admin_rework_for_revoked_student';

String _actionLabel(String action) => switch (action) {
  'created' || 'create' => 'Tạo yêu cầu',
  'student_edited' => 'Sinh viên chỉnh sửa yêu cầu',
  'assigned' || 'assign' => 'Phân công kỹ thuật viên',
  'started' || 'start' || 'in_progress' => 'Bắt đầu xử lý',
  'continued' => 'Tiếp tục xử lý',
  'transfer_confirmed' => 'Xác nhận tiếp tục',
  'repair_reported' ||
  'result_submitted' ||
  'reported' => 'Báo cáo kết quả sửa chữa',
  'rework_requested' ||
  'student_rework_requested' ||
  'rework' => 'Yêu cầu xử lý lại',
  _adminReworkAction => 'Admin yêu cầu xử lý lại thay Sinh viên',
  'admin_confirmed_revoked_student' => 'Admin xác nhận hoàn tất thay Sinh viên',
  'reopened' || 'reopen' || 'student_reopened' => 'Mở lại yêu cầu',
  'completed' || 'complete' || 'confirmed' || 'student_confirmed' => 'Hoàn tất',
  'cancelled' || 'cancel' || 'student_cancelled' => 'Hủy yêu cầu',
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
