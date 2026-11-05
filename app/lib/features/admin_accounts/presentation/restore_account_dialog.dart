import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../admin_rooms/models/admin_room.dart';
import '../data/admin_accounts_repository.dart';
import '../models/managed_account.dart';

class RestoreAccountDialog extends StatefulWidget {
  const RestoreAccountDialog({
    super.key,
    required this.repository,
    required this.account,
  });

  final AdminAccountsRepository repository;
  final ManagedAccount account;

  static Future<bool?> show(
    BuildContext context, {
    required AdminAccountsRepository repository,
    required ManagedAccount account,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          RestoreAccountDialog(repository: repository, account: account),
    );
  }

  @override
  State<RestoreAccountDialog> createState() => _RestoreAccountDialogState();
}

class _RestoreAccountDialogState extends State<RestoreAccountDialog> {
  List<AdminRoom> _activeRooms = const [];
  String? _roomId;
  bool _loadingRooms = false;
  bool _submitting = false;
  String? _error;

  bool get _isStudent => widget.account.role == AppRole.student;

  @override
  void initState() {
    super.initState();
    if (_isStudent) {
      _loadingRooms = true;
      unawaited(_loadRooms());
    }
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loadingRooms = true;
      _error = null;
    });
    try {
      final rooms = await widget.repository.getActiveRooms();
      if (!mounted) return;
      setState(() {
        _activeRooms = rooms.where((room) => room.isActive).toList();
        _loadingRooms = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRooms = false;
        _error = error is AdminAccountsFailure
            ? error.message
            : 'Không thể tải phòng đang hoạt động. Vui lòng thử lại.';
      });
    }
  }

  Future<void> _submit() async {
    if (_isStudent && (_roomId == null || _roomId!.isEmpty)) {
      setState(() => _error = 'Vui lòng chọn phòng đang hoạt động.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.restoreAccount(
        identityCode: widget.account.identityCode,
        roomId: _isStudent ? _roomId : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is AdminAccountsFailure
            ? error.message
            : 'Không thể khôi phục tài khoản. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Khôi phục tài khoản'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.account.fullName} · ${widget.account.identityCode} · ${widget.account.role.label}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (_isStudent) ...[
            const Text(
              'Chọn phòng đang hoạt động. Các yêu cầu chưa kết thúc được giữ nguyên; sau khi khôi phục, Sinh viên tự xác nhận và Admin không xác nhận thay.',
            ),
            const SizedBox(height: 16),
            if (_loadingRooms)
              const Center(child: CircularProgressIndicator())
            else if (_activeRooms.isEmpty)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Không có phòng đang hoạt động. Chưa thể khôi phục Sinh viên.',
                      style: TextStyle(color: Color(0xFF92400E)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tải lại phòng',
                    onPressed: _loadRooms,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _roomId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Phòng đang hoạt động *',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _activeRooms
                    .map(
                      (room) => DropdownMenuItem(
                        value: room.id,
                        child: Text(
                          '${room.code} (${room.building})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _roomId = value),
              ),
          ] else
            const Text(
              'Tài khoản chỉ được mở lại nếu còn hợp lệ và Kỹ thuật viên không có công việc chưa hoàn tất.',
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context, false),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        onPressed:
            _submitting ||
                (_isStudent && (_loadingRooms || _activeRooms.isEmpty))
            ? null
            : _submit,
        icon: _submitting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.restore_outlined),
        label: Text(_submitting ? 'Đang khôi phục...' : 'Khôi phục'),
      ),
    ],
  );
}
