import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/dormfix_app_bar.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../student_confirmation/models/student_confirmation_submission.dart';
import '../../student_confirmation/presentation/student_result_action_form.dart';
import '../data/request_repository.dart';
import '../models/request_detail.dart';
import 'edit_request_screen.dart';
import 'widgets/category_icon.dart';
import 'widgets/status_timeline.dart';
import 'widgets/request_photo.dart';

/// DF-010: Màn hình chi tiết yêu cầu sửa chữa.
/// DF-011: Hỗ trợ nút Chỉnh sửa yêu cầu khi ở trạng thái Chờ tiếp nhận (pending).
class RequestDetailScreen extends StatefulWidget {
  final RequestRepository repository;
  final String requestId;
  final VoidCallback? onRequestChanged;

  const RequestDetailScreen({
    super.key,
    required this.repository,
    required this.requestId,
    this.onRequestChanged,
  });

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  RequestDetail? _detail;
  bool _loading = false;
  bool _cancelling = false;
  bool _cancelDialogOpen = false;
  bool _openingAction = false;
  String? _errorText;
  int _generation = 0;
  StreamSubscription<void>? _accessSubscription;
  Route<void>? _photoRoute;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _load();
  }

  void _subscribe() {
    _accessSubscription = widget.repository.accessChanges.listen(
      (_) => _denyAccess(),
      onError: (Object _) => _denyAccess(),
    );
  }

  @override
  void didUpdateWidget(covariant RequestDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.requestId != widget.requestId) {
      _accessSubscription?.cancel();
      _detail = null;
      _openingAction = false;
      _closePhoto();
      _subscribe();
      _load();
    }
  }

  void _closePhoto() {
    final route = _photoRoute;
    _photoRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  void _denyAccess() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _detail = null;
      _loading = false;
      _openingAction = false;
      _errorText =
          'Bạn không còn quyền xem yêu cầu này. Vui lòng đăng nhập lại.';
    });
    _closePhoto();
  }

  @override
  void dispose() {
    _generation++;
    _accessSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final result = await widget.repository.fetchRequestDetail(
        widget.requestId,
      );
      if (mounted && generation == _generation) {
        setState(() => _detail = result);
      }
    } on RequestFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      if (failure.accessDenied) {
        _denyAccess();
      } else {
        setState(() {
          _detail = null;
          _errorText = failure.message;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _detail = null;
          _errorText = 'Không tải được chi tiết. Hãy thử lại.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _navigateToEdit() async {
    final detail = _detail;
    if (_openingAction || _loading || detail == null || !_canEdit(detail)) {
      return;
    }
    final generation = _generation;
    setState(() => _openingAction = true);
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EditRequestScreen(repository: widget.repository, detail: detail),
      ),
    );
    if (!mounted || generation != _generation) return;
    setState(() => _openingAction = false);
    if (updated == true) widget.onRequestChanged?.call();
    if (updated == true || widget.repository.supportsVersionedMutations) {
      await _load();
    }
  }

  Future<void> _openResultAction(StudentResultAction action) async {
    final detail = _detail;
    if (_openingAction ||
        _loading ||
        detail == null ||
        !widget.repository.supportsConfirmationActions ||
        detail.request.status != RepairStatus.awaitingConfirmation) {
      return;
    }
    await _openActionForm(
      StudentResultActionForm(
        repository: widget.repository,
        detail: detail,
        action: action,
      ),
      success: action == StudentResultAction.confirmFixed
          ? 'Đã xác nhận sự cố được khắc phục.'
          : 'Đã gửi yêu cầu sửa lại.',
    );
  }

  Future<void> _openReopenForm() async {
    final detail = _detail;
    if (_openingAction || _loading || detail == null || !_canReopen(detail)) {
      return;
    }
    await _openActionForm(
      StudentResultActionForm.reopen(
        repository: widget.repository,
        detail: detail,
      ),
      success: 'Đã mở lại yêu cầu sửa chữa.',
    );
  }

  Future<void> _openActionForm(
    StudentResultActionForm form, {
    required String success,
  }) async {
    final generation = _generation;
    setState(() => _openingAction = true);
    final receipt = await Navigator.of(
      context,
    ).push<StudentConfirmationReceipt>(MaterialPageRoute(builder: (_) => form));
    if (!mounted || generation != _generation) return;
    setState(() => _openingAction = false);
    if (receipt != null) {
      widget.onRequestChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    }
    await _load();
  }

  /// DF-012: Hiển thị dialog xác nhận hủy yêu cầu, yêu cầu nhập lý do.
  Future<void> _showCancelDialog() async {
    final detail = _detail;
    if (!mounted ||
        _loading ||
        _cancelling ||
        _cancelDialogOpen ||
        detail == null ||
        _openingAction ||
        !_canCancel(detail)) {
      return;
    }
    if (widget.repository.supportsVersionedMutations) {
      await _openActionForm(
        StudentResultActionForm.cancel(
          repository: widget.repository,
          detail: detail,
        ),
        success: 'Đã hủy yêu cầu sửa chữa',
      );
      return;
    }
    String reason = '';
    String? reasonError;
    bool dialogClosed = false;

    _cancelDialogOpen = true;
    String? confirmedReason;
    try {
      confirmedReason = await showDialog<String>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Hủy yêu cầu'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Vui lòng cho biết lý do bạn muốn hủy yêu cầu này.'),
                const SizedBox(height: 12),
                TextField(
                  maxLines: 3,
                  onChanged: (v) => reason = v,
                  decoration: InputDecoration(
                    hintText: 'Nhập lý do hủy...',
                    errorText: reasonError,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (dialogClosed) return;
                  dialogClosed = true;
                  Navigator.pop(ctx);
                },
                child: const Text('Quay lại'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (dialogClosed) return;
                  final trimmed = reason.trim();
                  if (trimmed.isEmpty) {
                    setStateDialog(() => reasonError = 'Vui lòng nhập lý do');
                    return;
                  }
                  dialogClosed = true;
                  Navigator.pop(ctx, trimmed);
                },
                child: const Text('Xác nhận hủy'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _cancelDialogOpen = false;
    }
    if (!mounted || confirmedReason == null) return;
    await _doCancel(confirmedReason);
  }

  bool _canEdit(RequestDetail detail) =>
      widget.repository.supportsEditing &&
      detail.request.status == RepairStatus.pending &&
      (!widget.repository.supportsVersionedMutations || detail.canEdit);

  bool _canCancel(RequestDetail detail) =>
      widget.repository.supportsCancellation &&
      (detail.request.status == RepairStatus.pending ||
          detail.request.status == RepairStatus.assigned) &&
      (!widget.repository.supportsVersionedMutations || detail.canCancel);

  bool _canReopen(RequestDetail detail) =>
      widget.repository.supportsReopening &&
      detail.request.status == RepairStatus.completed &&
      detail.canReopen;

  Future<void> _doCancel(String reason) async {
    final detail = _detail;
    if (!mounted ||
        _loading ||
        _cancelling ||
        detail == null ||
        !_canCancel(detail)) {
      return;
    }
    setState(() {
      _cancelling = true;
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.repository.cancelRequest(
        requestId: widget.requestId,
        reason: reason,
      );
      if (!mounted) return;
      widget.onRequestChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã hủy yêu cầu sửa chữa')));
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime value) {
    final d = value.toLocal();
    return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final canEdit = d != null && _canEdit(d);
    final canCancel = d != null && _canCancel(d);
    final actionBusy = _loading || _cancelling || _openingAction;

    return PopScope(
      canPop: !_cancelling,
      child: Scaffold(
        appBar: DormFixAppBar(
          title: d?.request.requestCode ?? 'Chi tiết',
          actions: [
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Chỉnh sửa yêu cầu',
                onPressed: actionBusy ? null : _navigateToEdit,
              ),
            if (canCancel)
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Hủy yêu cầu',
                onPressed: actionBusy ? null : _showCancelDialog,
              ),
          ],
        ),
        body: _body(),
      ),
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
      padding: const EdgeInsets.all(16),
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
        if (_canEdit(d))
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: OutlinedButton.icon(
              onPressed: _openingAction ? null : _navigateToEdit,
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

        // DF-012: Nút hủy yêu cầu khi ở trạng thái pending hoặc assigned
        if (_canCancel(d))
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: OutlinedButton.icon(
              onPressed: _cancelling || _openingAction
                  ? null
                  : _showCancelDialog,
              icon: Icon(Icons.cancel_outlined, color: Colors.red.shade600),
              label: Text(
                'Hủy yêu cầu này',
                style: TextStyle(color: Colors.red.shade600),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.shade400),
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
                Expanded(
                  child: Text(
                    widget.repository.supportsConfirmationActions
                        ? 'Kỹ thuật viên đã báo cáo kết quả sửa chữa. Hãy kiểm tra kết quả bên dưới để xác nhận.'
                        : 'Kỹ thuật viên đã gửi kết quả sửa chữa. Kết quả và lịch sử được hiển thị bên dưới.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
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

        if (d.feedback.isNotEmpty)
          SectionCard(
            title: 'Phản hồi và mở lại yêu cầu',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final feedback in d.feedback) ...[
                  Text(
                    feedback.kind == 'reopen'
                        ? 'Mở lại yêu cầu'
                        : 'Yêu cầu sửa lại',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(feedback.reason),
                  const SizedBox(height: 4),
                  Text(
                    '${feedback.authorName} · ${_formatDate(feedback.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (feedback.photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final photo in feedback.photos)
                          _photoThumbnail(photo, isResult: false),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  res.technicianName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
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
        if (widget.repository.supportsConfirmationActions &&
            r.status == RepairStatus.awaitingConfirmation) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('student-confirm-fixed'),
            onPressed: _openingAction
                ? null
                : () => _openResultAction(StudentResultAction.confirmFixed),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Xác nhận đã khắc phục'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('student-request-rework'),
            onPressed: _openingAction
                ? null
                : () => _openResultAction(StudentResultAction.requestRework),
            icon: const Icon(Icons.replay),
            label: const Text('Yêu cầu sửa lại'),
          ),
        ],
        if (_canReopen(d)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('student-reopen-request'),
            onPressed: _openingAction ? null : _openReopenForm,
            icon: const Icon(Icons.replay),
            label: const Text('Mở lại yêu cầu'),
          ),
        ],
      ],
    );
  }

  Widget _photoThumbnail(String photo, {required bool isResult}) {
    final attachments = _detail?.attachments.where(
      (attachment) => attachment.storagePath == photo,
    );
    if (attachments != null && attachments.isNotEmpty) {
      final attachment = attachments.first;
      return RequestPhoto(
        repository: widget.repository,
        requestId: widget.requestId,
        attachment: attachment,
        onAccessDenied: _denyAccess,
        onTap: () => _viewPrivatePhoto(attachment),
      );
    }
    if (!widget.repository.allowsDemoFallback) {
      return const Text('Ảnh không khả dụng');
    }
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

  Future<void> _viewPrivatePhoto(RequestAttachment attachment) async {
    if (_photoRoute != null || _detail == null) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: const DormFixAppBar(title: 'Ảnh đính kèm'),
        body: SafeArea(
          child: RequestPhoto(
            repository: widget.repository,
            requestId: widget.requestId,
            attachment: attachment,
            expanded: true,
            onAccessDenied: _denyAccess,
          ),
        ),
      ),
    );
    _photoRoute = route;
    await Navigator.of(context).push<void>(route);
    if (_photoRoute == route) _photoRoute = null;
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
