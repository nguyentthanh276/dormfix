import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/error_view.dart';
import '../../admin_rooms/data/admin_room_repository.dart';
import '../../admin_rooms/models/admin_room.dart';
import '../../auth/models/password_rules.dart';
import '../../profile/models/phone_rules.dart';
import '../data/admin_account_management_repository.dart';
import '../models/managed_account.dart';
import '../models/managed_account_input.dart';

/// DF-031–034: account provisioning and profile updates in the Admin navigator.
class AdminAccountFormPage extends StatefulWidget {
  const AdminAccountFormPage({
    super.key,
    required this.repository,
    this.roomRepository,
    this.identityCode,
  });

  final AdminAccountManagementRepository repository;
  final AdminRoomRepository? roomRepository;
  final String? identityCode;

  @override
  State<AdminAccountFormPage> createState() => _AdminAccountFormPageState();
}

class _AdminAccountFormPageState extends State<AdminAccountFormPage>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  ManagedAccountDetails? _details;
  List<AdminRoom>? _rooms;
  String? _roomId;
  AppRole _role = AppRole.student;
  String? _detailError;
  String? _roomError;
  String? _saveError;
  bool _loadingRooms = false;
  bool _saving = false;
  bool _reviewRequired = false;

  bool get _editing => widget.identityCode != null;
  bool get _student => _role == AppRole.student;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_editing) {
      unawaited(_loadDetails());
    } else {
      unawaited(_loadRooms());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _password.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _identity.dispose();
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _detailError = null);
    try {
      final details = await widget.repository.fetchDetails(
        widget.identityCode!,
      );
      if (!mounted) return;
      _identity.text = details.identityCode;
      _fullName.text = details.fullName;
      _email.text = details.email;
      _phone.text = details.phone;
      setState(() {
        _details = details;
        _role = details.role;
        _roomId = details.roomId;
      });
      if (_student) await _loadRooms();
    } on AdminAccountsFailure catch (failure) {
      if (mounted) setState(() => _detailError = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _detailError =
              'Không thể tải thông tin tài khoản. Vui lòng thử lại.',
        );
      }
    }
  }

  Future<void> _loadRooms() async {
    if (_loadingRooms) return;
    final repository = widget.roomRepository;
    if (repository == null) {
      setState(() => _roomError = 'Dịch vụ danh sách phòng chưa sẵn sàng.');
      return;
    }
    setState(() {
      _loadingRooms = true;
      _roomError = null;
    });
    try {
      final rooms = await repository.fetchRooms();
      if (!mounted) return;
      final details = _details;
      final selectable = rooms
          .where(
            (room) =>
                room.isActive ||
                (details?.status == AccountStatus.revoked &&
                    room.id == details?.roomId),
          )
          .toList();
      setState(() {
        _rooms = selectable;
        if (!selectable.any((room) => room.id == _roomId)) _roomId = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _roomError = 'Không thể tải phòng. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Vui lòng nhập email.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Email không hợp lệ.';
    }
    return null;
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

  Future<void> _submit() async {
    if (_saving || _reviewRequired || (_student && (_rooms?.isEmpty ?? true))) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _fullName.text.trim();
    final phone = _phone.text.trim();
    final roomId = _student ? _roomId : null;
    final original = _details;
    final createInput = original == null
        ? CreateManagedAccount(
            role: _role,
            identityCode: _identity.text.trim(),
            fullName: name,
            email: _email.text.trim(),
            phone: phone,
            temporaryPassword: _password.text,
            roomId: roomId,
          )
        : null;
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = createInput != null
          ? await widget.repository.createAccount(createInput)
          : await widget.repository.updateAccount(
              UpdateManagedAccount(
                id: original!.id,
                fullName: name,
                phone: phone,
                roomId: roomId,
              ),
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on AdminAccountsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _reviewRequired =
            failure.accessDenied || failure.conflict || failure.uncertain;
        _saveError = failure.message;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _reviewRequired = true;
          _saveError = 'Chưa xác nhận được kết quả. Hãy kiểm tra danh sách tài khoản trước khi thử lại.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<ManagedAccountDetails>(
    canPop: !_saving,
    child: Scaffold(
      appBar: DormFixAppBar(
        title: _editing ? 'Cập nhật tài khoản' : 'Tạo tài khoản',
        roleLabel: 'Admin',
      ),
      body: SafeArea(top: false, child: _body()),
    ),
  );

  Widget _body() {
    final detailError = _detailError;
    if (detailError != null) {
      return ErrorView(message: detailError, onRetry: _loadDetails);
    }
    if (_editing && _details == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reviewRequired) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _saveError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Về danh sách để kiểm tra'),
          ),
        ],
      );
    }
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_editing)
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Vai trò'),
                child: Text(_role.label),
              )
            else
              DropdownButtonFormField<AppRole>(
                key: const Key('admin-account-role'),
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vai trò'),
                items: [
                  for (final role in [AppRole.student, AppRole.technician])
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: _saving
                    ? null
                    : (role) {
                        if (role == null) return;
                        setState(() => _role = role);
                        if (_student && _rooms == null) unawaited(_loadRooms());
                      },
              ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('admin-account-identity'),
              controller: _identity,
              enabled: !_saving && !_editing,
              decoration: const InputDecoration(labelText: 'Mã định danh *'),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Vui lòng nhập mã định danh.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('admin-account-name'),
              controller: _fullName,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Họ và tên *'),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Vui lòng nhập họ và tên.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('admin-account-email'),
              controller: _email,
              enabled: !_saving && !_editing,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email *'),
              validator: _editing ? null : _validateEmail,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('admin-account-phone'),
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Số điện thoại *'),
              validator: PhoneRules.validatePhone,
            ),
            if (_student) ...[const SizedBox(height: 16), _roomPicker()],
            if (!_editing) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('admin-account-temporary-password'),
                controller: _password,
                enabled: !_saving,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Mật khẩu tạm *'),
                validator: _validatePassword,
              ),
              const SizedBox(height: 8),
              const Text('Tài khoản phải đổi mật khẩu khi đăng nhập lần đầu.'),
            ],
            if (_saveError != null) ...[
              const SizedBox(height: 12),
              Text(
                _saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('admin-account-save'),
              onPressed:
                  _saving ||
                      (_student &&
                          (_loadingRooms ||
                              _roomError != null ||
                              (_rooms?.isEmpty ?? true)))
                  ? null
                  : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_editing ? 'Lưu thay đổi' : 'Tạo tài khoản'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roomPicker() {
    if (_loadingRooms) return const LinearProgressIndicator();
    final error = _roomError;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error),
          if (widget.roomRepository != null)
            TextButton(
              onPressed: _loadRooms,
              child: const Text('Tải lại phòng'),
            ),
        ],
      );
    }
    final rooms = _rooms ?? const [];
    if (rooms.isEmpty) {
      return const Text('Chưa có phòng đang hoạt động để gắn.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('admin-account-room'),
          initialValue: _roomId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Phòng *'),
          items: [
            for (final room in rooms)
              DropdownMenuItem(
                value: room.id,
                child: Text(
                  room.isActive
                      ? '${room.code} · ${room.building}'
                      : '${room.code} · Phòng hiện tại đã ngừng sử dụng',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() => _roomId = value),
          validator: (value) =>
              value == null ? 'Vui lòng chọn phòng đang hoạt động.' : null,
        ),
        if (_editing) ...[
          const SizedBox(height: 8),
          const Text('Đổi phòng áp dụng cho các yêu cầu tạo sau khi lưu.'),
        ],
      ],
    );
  }
}
