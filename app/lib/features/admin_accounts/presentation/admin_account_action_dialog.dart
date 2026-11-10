import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../admin_rooms/data/admin_room_repository.dart';
import '../../admin_rooms/models/admin_room.dart';
import '../../auth/models/password_rules.dart';
import '../data/admin_account_lifecycle_repository.dart';
import '../data/admin_account_management_repository.dart';
import '../models/account_lifecycle_action.dart';
import '../models/managed_account.dart';

enum AdminAccountActionResult { saved, refresh }

enum AdminAccountAction {
  lock('Khóa tài khoản', AccountLifecycleAction.lock),
  unlock('Mở khóa tài khoản', AccountLifecycleAction.unlock),
  revoke('Thu hồi tài khoản', AccountLifecycleAction.revoke),
  restore('Khôi phục tài khoản', AccountLifecycleAction.restore),
  resetPassword('Đặt lại mật khẩu');

  const AdminAccountAction(this.label, [this.statusAction]);
  final String label;
  final AccountLifecycleAction? statusAction;

  static List<AdminAccountAction> forStatus(AccountStatus status) =>
      switch (status) {
        AccountStatus.active => [lock, revoke, resetPassword],
        AccountStatus.locked => [unlock, revoke, resetPassword],
        AccountStatus.revoked => [restore],
      };

  bool get requiresReason => this == lock || this == revoke;

  String successMessage(String identityCode) => switch (this) {
    lock => 'Đã khóa tài khoản $identityCode.',
    unlock => 'Đã mở khóa tài khoản $identityCode.',
    revoke => 'Đã thu hồi tài khoản $identityCode.',
    restore => 'Đã khôi phục tài khoản $identityCode.',
    resetPassword =>
      'Đã đặt lại mật khẩu cho $identityCode. Người dùng phải đổi mật khẩu tạm khi đăng nhập.',
  };

  String confirmationFor(AppRole role) => switch (this) {
    lock when role == AppRole.technician => 'Tài khoản sẽ mất quyền truy cập. Kỹ thuật viên phải hoàn tất các công việc còn mở trước khi khóa.',
    lock => 'Tài khoản sẽ mất quyền truy cập. Sinh viên tự xác nhận yêu cầu sau khi được mở khóa.',
    unlock => 'Tài khoản sẽ được phép đăng nhập lại.',
    revoke when role == AppRole.technician => 'Quyền truy cập sẽ bị thu hồi và lịch sử được giữ lại. Kỹ thuật viên phải hoàn tất các công việc còn mở trước khi thu hồi.',
    revoke => 'Quyền truy cập sẽ bị thu hồi và lịch sử được giữ lại. Admin có thể xử lý thay Sinh viên với các yêu cầu còn mở.',
    restore when role == AppRole.student => 'Chọn hoặc xác nhận phòng đang sử dụng. Sau khi khôi phục, Sinh viên tự xác nhận các yêu cầu chưa kết thúc.',
    restore => 'Tài khoản sẽ được phép đăng nhập lại và giữ lịch sử công việc.',
    resetPassword => 'Người dùng phải đổi mật khẩu tạm ở lần đăng nhập sau.',
  };
}

class AdminAccountActionDialog extends StatefulWidget {
  const AdminAccountActionDialog({
    super.key,
    required this.account,
    required this.action,
    required this.managementRepository,
    required this.lifecycleRepository,
    this.roomRepository,
  });

  final ManagedAccount account;
  final AdminAccountAction action;
  final AdminAccountManagementRepository managementRepository;
  final AdminAccountLifecycleRepository lifecycleRepository;
  final AdminRoomRepository? roomRepository;

  @override
  State<AdminAccountActionDialog> createState() =>
      _AdminAccountActionDialogState();
}

class _AdminAccountActionDialogState extends State<AdminAccountActionDialog>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _password = TextEditingController();
  ManagedAccountDetails? _details;
  List<AdminRoom> _rooms = const [];
  String? _roomId;
  String? _loadError;
  String? _saveError;
  bool _loading = true;
  bool _saving = false;
  bool _refreshRequired = false;

  bool get _needsRoom =>
      widget.action == AdminAccountAction.restore &&
      widget.account.role == AppRole.student;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _password.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reason.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final details = await widget.managementRepository.fetchDetails(
        widget.account.identityCode,
      );
      if (!mounted) return;
      if (details.role != widget.account.role ||
          details.status != widget.account.status) {
        throw const AdminAccountsFailure(
          'Tài khoản đã thay đổi. Hãy tải lại danh sách.',
          conflict: true,
        );
      }
      List<AdminRoom> rooms = const [];
      if (_needsRoom) {
        final repository = widget.roomRepository;
        if (repository == null) {
          throw const AdminAccountsFailure(
            'Dịch vụ danh sách phòng chưa sẵn sàng.',
          );
        }
        rooms = (await repository.fetchRooms())
            .where((room) => room.isActive)
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _rooms = rooms;
        _roomId = rooms.any((room) => room.id == details.roomId)
            ? details.roomId
            : null;
      });
    } on AdminAccountsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadError = failure.message;
        _refreshRequired = failure.accessDenied || failure.conflict;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError = 'Không thể tải thông tin. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập mật khẩu tạm.';
    }
    if (!PasswordRules.hasMinLength(value)) {
      return 'Mật khẩu tạm cần ít nhất ${PasswordRules.minLength} ký tự.';
    }
    if (utf8.encode(value).length > 72) return 'Mật khẩu tạm vượt quá 72 byte.';
    return null;
  }

  String? _validateReason(String? value) {
    final reason = value?.trim() ?? '';
    if (reason.isEmpty) return 'Vui lòng nhập lý do.';
    if (reason.runes.length > 500) return 'Lý do tối đa 500 ký tự.';
    return null;
  }

  Future<void> _submit() async {
    final details = _details;
    if (_saving || _refreshRequired || details == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final action = widget.action.statusAction;
    final temporaryPassword = _password.text;
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      if (action == null) {
        await widget.lifecycleRepository.resetTemporaryPassword(
          accountId: details.id,
          expectedStatus: details.status,
          temporaryPassword: temporaryPassword,
        );
      } else {
        await widget.lifecycleRepository.changeAccountStatus(
          accountId: details.id,
          expectedStatus: details.status,
          action: action,
          reason: widget.action.requiresReason ? _reason.text.trim() : null,
          roomId: _needsRoom ? _roomId : null,
        );
      }
      if (mounted) Navigator.of(context).pop(AdminAccountActionResult.saved);
    } on AdminAccountsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saveError = failure.message;
        _refreshRequired =
            failure.accessDenied || failure.conflict || failure.uncertain;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveError = 'Chưa xác nhận được kết quả. Hãy tải lại danh sách trước khi thử lại.';
        _refreshRequired = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final error = _loadError ?? _saveError;
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope<AdminAccountActionResult>(
      canPop: !_saving && !_refreshRequired,
      child: AlertDialog(
        scrollable: true,
        title: Text(action.label),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.account.fullName} · ${widget.account.identityCode}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_loadError == null && !_refreshRequired) ...[
                Text(action.confirmationFor(widget.account.role)),
                if (action.requiresReason) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('admin-account-action-reason'),
                    controller: _reason,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Lý do *'),
                    validator: _validateReason,
                  ),
                ],
                if (_needsRoom) ...[
                  const SizedBox(height: 12),
                  if (_rooms.isEmpty)
                    const Text(
                      'Chưa có phòng đang sử dụng để khôi phục tài khoản.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('admin-account-restore-room'),
                      initialValue: _roomId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Phòng *'),
                      items: [
                        for (final room in _rooms)
                          DropdownMenuItem(
                            value: room.id,
                            child: Text(
                              '${room.code} · ${room.building}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _roomId = value),
                      validator: (value) =>
                          value == null ? 'Vui lòng chọn phòng.' : null,
                    ),
                ],
                if (action == AdminAccountAction.resetPassword) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('admin-account-reset-password'),
                    controller: _password,
                    enabled: !_saving,
                    obscureText: true,
                    enableSuggestions: false,
                    enableInteractiveSelection: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu tạm *',
                    ),
                    validator: _validatePassword,
                  ),
                ],
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error, style: TextStyle(color: colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          if (_refreshRequired)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(AdminAccountActionResult.refresh),
              child: const Text('Đóng và tải lại'),
            )
          else ...[
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            if (_loadError != null)
              FilledButton(onPressed: _load, child: const Text('Thử lại'))
            else
              FilledButton(
                key: const Key('admin-account-action-confirm'),
                onPressed: _loading || _saving || (_needsRoom && _rooms.isEmpty)
                    ? null
                    : _submit,
                style: action.requiresReason
                    ? FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      )
                    : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Xác nhận'),
              ),
          ],
        ],
      ),
    );
  }
}
