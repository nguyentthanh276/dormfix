import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/admin_request_repository.dart';
import '../models/admin_request.dart';
import '../models/admin_request_transition_rules.dart';

/// DF-043: Admin detail includes room, requester, current handler, results, photos, and audit history.
class AdminRequestDetailPage extends StatefulWidget {
  const AdminRequestDetailPage({
    super.key,
    required this.repository,
    required this.requestId,
  });

  final AdminRequestRepository repository;
  final String requestId;

  @override
  State<AdminRequestDetailPage> createState() => _AdminRequestDetailPageState();
}

class _AdminRequestDetailPageState extends State<AdminRequestDetailPage> {
  AdminRequestDetail? _detail;
  String? _error;
  bool _loading = true;
  bool _mutating = false;
  final Map<String, Future<Uint8List>> _photos = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _photos.clear();
    });
    try {
      final detail = await widget.repository.fetchRequestDetail(
        widget.requestId,
      );
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AdminRequestFailure
              ? error.message
              : 'Không thể tải chi tiết yêu cầu. Vui lòng thử lại.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.request.requestCode ?? 'Chi tiết yêu cầu'),
      ),
      body: _loading && detail == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && detail == null
          ? _loadError(context)
          : detail == null
          ? const Center(child: Text('Không tìm thấy yêu cầu.'))
          : _detailBody(context, detail),
    );
  }

  Widget _loadError(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.black45),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );

  Widget _detailBody(BuildContext context, AdminRequestDetail detail) {
    final request = detail.request;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          _adminActions(context, detail),
          _section(
            context,
            title: request.title,
            trailing: StatusChip(request.status),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _info('Mã yêu cầu', request.requestCode),
                _info('Loại sự cố', request.categoryName),
                _info('Phòng', '${request.roomCode} · ${detail.building}'),
                _info('Người tạo', request.studentName),
                _info(
                  'Trạng thái tài khoản Sinh viên',
                  _accountStatus(detail.studentStatus),
                ),
                _info(
                  'Người xử lý hiện tại',
                  request.technicianName ?? 'Chưa phân công',
                ),
                _info('Ngày tạo', _dateTime(request.createdAt)),
                _info('Cập nhật gần nhất', _dateTime(request.updatedAt)),
              ],
            ),
          ),
          _section(
            context,
            title: 'Mô tả sự cố',
            child: Text(detail.description),
          ),
          _photoSection(
            context,
            'Ảnh sự cố',
            detail.attachments
                .where(
                  (item) =>
                      item['result_id'] == null && item['feedback_id'] == null,
                )
                .toList(),
          ),
          for (final result in detail.results)
            _section(
              context,
              title: 'Kết quả sửa chữa',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _info('Người xử lý', _string(result, 'technician_name')),
                  _info('Thời gian', _dateTimeValue(result['submitted_at'])),
                  const SizedBox(height: 8),
                  Text(_string(result, 'content')),
                  const SizedBox(height: 12),
                  _photoSection(
                    context,
                    'Ảnh kết quả',
                    detail.attachments
                        .where((item) => item['result_id'] == result['id'])
                        .toList(),
                  ),
                ],
              ),
            ),
          for (final feedback in detail.feedback)
            _section(
              context,
              title: _feedbackTitle(feedback['kind']),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _info('Người gửi', _string(feedback, 'author_name')),
                  _info('Thời gian', _dateTimeValue(feedback['created_at'])),
                  const SizedBox(height: 8),
                  Text(_string(feedback, 'reason')),
                  const SizedBox(height: 12),
                  _photoSection(
                    context,
                    'Ảnh phản hồi',
                    detail.attachments
                        .where((item) => item['feedback_id'] == feedback['id'])
                        .toList(),
                  ),
                ],
              ),
            ),
          _section(
            context,
            title: 'Lịch sử phân công',
            child: detail.assignments.isEmpty
                ? const Text('Yêu cầu chưa được phân công.')
                : Column(
                    children: detail.assignments.map(_assignmentTile).toList(),
                  ),
          ),
          _section(
            context,
            title: 'Lịch sử yêu cầu',
            child: detail.history.isEmpty
                ? const Text('Chưa có lịch sử xử lý.')
                : Column(children: detail.history.map(_historyTile).toList()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  // DF-045/046/047/048: the UI hides invalid actions; RPCs recheck state and role.
  Widget _adminActions(BuildContext context, AdminRequestDetail detail) {
    final status = detail.request.status;
    bool allows(AdminRequestAdminAction action) =>
        AdminRequestTransitionRules.allows(
          action,
          status,
          studentAccountStatus: detail.studentStatus,
        );
    final actions = <Widget>[];
    if (allows(AdminRequestAdminAction.assign) &&
        allows(AdminRequestAdminAction.reject)) {
      actions
        ..add(
          OutlinedButton.icon(
            onPressed: _mutating
                ? null
                : () => _chooseTechnician(transfer: false),
            icon: const Icon(Icons.assignment_ind_outlined),
            label: const Text('Phân công Kỹ thuật viên'),
          ),
        )
        ..add(
          OutlinedButton.icon(
            onPressed: _mutating ? null : _reject,
            icon: const Icon(Icons.block_outlined),
            label: const Text('Từ chối yêu cầu'),
          ),
        );
    } else if (allows(AdminRequestAdminAction.transfer)) {
      actions.add(
        OutlinedButton.icon(
          onPressed: _mutating ? null : () => _chooseTechnician(transfer: true),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Đổi Kỹ thuật viên'),
        ),
      );
    } else if (allows(AdminRequestAdminAction.confirmForRevokedStudent) &&
        allows(AdminRequestAdminAction.requestReworkForRevokedStudent)) {
      actions
        ..add(
          FilledButton.icon(
            onPressed: _mutating ? null : _confirmForRevokedStudent,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Xác nhận hoàn tất'),
          ),
        )
        ..add(
          OutlinedButton.icon(
            onPressed: _mutating ? null : _requestReworkForRevokedStudent,
            icon: const Icon(Icons.replay),
            label: const Text('Yêu cầu sửa lại'),
          ),
        );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return _section(
      context,
      title: 'Thao tác quản lý',
      child: Wrap(spacing: 10, runSpacing: 10, children: actions),
    );
  }

  Future<void> _chooseTechnician({required bool transfer}) async {
    try {
      final technicians = await widget.repository.fetchActiveTechnicians();
      if (!mounted) return;
      if (technicians.isEmpty) {
        _showMessage('Hiện không có Kỹ thuật viên đang hoạt động.');
        return;
      }
      final eligibleTechnicians = technicians
          .where((item) => item.id != _detail?.technicianId)
          .toList(growable: false);
      if (eligibleTechnicians.isEmpty) {
        _showMessage('Không có Kỹ thuật viên đang hoạt động nào khác để chọn.');
        return;
      }
      String? selectedId;
      final reasonController = TextEditingController();
      final formKey = GlobalKey<FormState>();
      final selection = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(transfer ? 'Đổi Kỹ thuật viên' : 'Phân công yêu cầu'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kỹ thuật viên',
                    ),
                    items: eligibleTechnicians
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              item.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    validator: (value) =>
                        value == null ? 'Hãy chọn Kỹ thuật viên.' : null,
                    onChanged: (value) =>
                        setDialogState(() => selectedId = value),
                  ),
                  if (transfer) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'Lý do đổi (bắt buộc)',
                      ),
                      minLines: 2,
                      maxLines: 4,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Vui lòng nhập lý do đổi.'
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, {
                      'technicianId': selectedId!,
                      'reason': reasonController.text.trim(),
                    });
                  }
                },
                child: const Text('Lưu'),
              ),
            ],
          ),
        ),
      );
      reasonController.dispose();
      if (selection == null || !mounted) return;
      final id = selection['technicianId']!;
      final reason = selection['reason']!;
      await _runMutation(
        () => transfer
            ? widget.repository.transferRequest(widget.requestId, id, reason)
            : widget.repository.assignRequest(widget.requestId, id),
        transfer ? 'Đã đổi Kỹ thuật viên.' : 'Đã phân công Kỹ thuật viên.',
      );
    } catch (error) {
      if (mounted) _showFailure(error);
    }
  }

  Future<void> _reject() async {
    final reason = await _askRequiredText('Từ chối yêu cầu', 'Lý do từ chối');
    if (reason == null) return;
    await _runMutation(
      () => widget.repository.rejectRequest(widget.requestId, reason),
      'Đã từ chối yêu cầu.',
    );
  }

  Future<void> _confirmForRevokedStudent() async {
    final note = await _askRequiredText(
      'Xác nhận hoàn tất thay Sinh viên',
      'Ghi chú xác nhận',
    );
    if (note == null) return;
    await _runMutation(
      () => widget.repository.confirmForRevokedStudent(widget.requestId, note),
      'Đã xác nhận hoàn tất yêu cầu.',
    );
  }

  Future<void> _requestReworkForRevokedStudent() async {
    final reason = await _askRequiredText(
      'Yêu cầu sửa lại',
      'Lý do yêu cầu sửa lại',
    );
    if (reason == null) return;
    await _runMutation(
      () => widget.repository.requestReworkForRevokedStudent(
        widget.requestId,
        reason,
      ),
      'Đã chuyển yêu cầu sang Chờ xử lý lại.',
    );
  }

  Future<String?> _askRequiredText(String title, String label) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: '$label (bắt buộc)'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Vui lòng nhập $label.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _runMutation(
    Future<void> Function() action,
    String success,
  ) async {
    setState(() => _mutating = true);
    try {
      await action();
      await _load();
      if (mounted) _showMessage(success);
    } catch (error) {
      if (mounted) _showFailure(error);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _showFailure(Object error) => _showMessage(
    error is AdminRequestFailure
        ? error.message
        : 'Không thể lưu thao tác. Vui lòng thử lại.',
  );

  void _showMessage(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Widget _section(
    BuildContext context, {
    required String title,
    required Widget child,
    Widget? trailing,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFEDE5DE)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 190,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Widget _photoSection(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> attachments,
  ) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return _section(
      context,
      title: title,
      child: SizedBox(
        height: 130,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final attachment = attachments[index];
            final id = attachment['id'];
            if (id is! String) return const SizedBox.shrink();
            final future = _photos.putIfAbsent(
              id,
              () => widget.repository.fetchAttachment(
                widget.requestId,
                attachment,
              ),
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 150,
                color: AppColors.pageBg,
                child: FutureBuilder<Uint8List>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Icon(Icons.broken_image_outlined),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Image.memory(snapshot.data!, fit: BoxFit.cover);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> item) {
    final oldStatus = _statusLabel(item['old_status']);
    final newStatus = _statusLabel(item['new_status']);
    final transition = oldStatus == null
        ? newStatus ?? _string(item, 'action')
        : '$oldStatus → ${newStatus ?? oldStatus}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, color: AppColors.primary),
      title: Text(transition),
      subtitle: Text(
        [
          _string(item, 'actor_name'),
          _dateTimeValue(item['occurred_at']),
          if (item['note'] case final String note when note.isNotEmpty) note,
        ].join(' · '),
      ),
    );
  }

  Widget _assignmentTile(Map<String, dynamic> item) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.engineering_outlined, color: AppColors.primary),
    title: Text(_string(item, 'technician_name')),
    subtitle: Text(
      [
        'Phân công bởi ${_string(item, 'assigned_by_name')}',
        _dateTimeValue(item['assigned_at']),
        if (item['ended_at'] != null)
          'Kết thúc ${_dateTimeValue(item['ended_at'])}',
        if (item['transfer_reason'] is String)
          item['transfer_reason'] as String,
        if (item['end_reason'] is String) item['end_reason'] as String,
      ].join(' · '),
    ),
  );

  String _accountStatus(String status) => switch (status) {
    'active' => 'Đang hoạt động',
    'locked' => 'Bị khóa',
    'revoked' => 'Đã thu hồi',
    _ => status,
  };

  String _feedbackTitle(Object? kind) => kind == 'rework'
      ? 'Yêu cầu sửa lại'
      : kind == 'reopen'
      ? 'Mở lại yêu cầu'
      : 'Phản hồi';

  String? _statusLabel(Object? value) {
    if (value is! String) return null;
    for (final status in RepairStatus.values) {
      if (status.databaseValue == value) return status.label;
    }
    return value;
  }

  String _string(Map<String, dynamic> item, String key) =>
      item[key] is String ? item[key] as String : 'Không có thông tin';

  String _dateTimeValue(Object? value) {
    final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
    if (date == null) return 'Không có thời gian';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _dateTime(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
