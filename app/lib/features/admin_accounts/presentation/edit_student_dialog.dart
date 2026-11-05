import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin_rooms/models/admin_room.dart';
import '../../profile/models/phone_rules.dart';
import '../data/admin_accounts_repository.dart';

class EditStudentDialog extends StatefulWidget {
  const EditStudentDialog({
    super.key,
    required this.repository,
    required this.identityCode,
  });

  final AdminAccountsRepository repository;
  final String identityCode;

  static Future<bool?> show(
    BuildContext context, {
    required AdminAccountsRepository repository,
    required String identityCode,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          EditStudentDialog(repository: repository, identityCode: identityCode),
    );
  }

  @override
  State<EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends State<EditStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();

  List<AdminRoom> _activeRooms = const [];
  String? _roomId;
  String? _currentRoomCode;
  String? _currentRoomBuilding;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.repository.getStudentForEdit(
        widget.identityCode,
      );
      final rooms = await widget.repository.getActiveRooms();
      if (!mounted) return;
      final activeRooms = rooms.where((room) => room.isActive).toList();
      setState(() {
        _fullName.text = details.fullName;
        _phone.text = details.phone;
        _activeRooms = activeRooms;
        _roomId = activeRooms.any((room) => room.id == details.roomId)
            ? details.roomId
            : null;
        _currentRoomCode = details.roomCode;
        _currentRoomBuilding = details.roomBuilding;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is AdminAccountsFailure
            ? error.message
            : 'Không thể tải thông tin Sinh viên. Vui lòng thử lại.';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final roomId = _roomId;
    if (roomId == null || roomId.isEmpty) {
      setState(() => _error = 'Vui lòng chọn phòng đang hoạt động.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateStudent(
        identityCode: widget.identityCode,
        fullName: _fullName.text.trim(),
        phone: _phone.text.trim(),
        roomId: roomId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is AdminAccountsFailure
            ? error.message
            : 'Không thể cập nhật Sinh viên. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _loading ? _loadingView() : _formView(context),
      ),
    ),
  );

  Widget _loadingView() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Center(child: CircularProgressIndicator()),
  );

  Widget _formView(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.edit_outlined, color: AppColors.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cập nhật Sinh viên',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Đóng',
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Mã Sinh viên',
            helperText: 'Mã định danh không thể thay đổi',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
          ),
          child: Text(widget.identityCode),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _fullName,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Họ và tên *',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Vui lòng nhập họ và tên.'
              : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _phone,
          enabled: !_saving,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Số điện thoại *',
            hintText: '0912345678 hoặc +84912345678',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
          ),
          validator: PhoneRules.validatePhone,
        ),
        const SizedBox(height: 14),
        if (_currentRoomCode != null && _roomId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Phòng hiện tại $_currentRoomCode (${_currentRoomBuilding ?? ''}) không còn hoạt động. Hãy chọn phòng đang hoạt động để lưu.',
              style: const TextStyle(color: Color(0xFF92400E)),
            ),
          ),
        if (_activeRooms.isEmpty)
          const Text(
            'Hiện không có phòng nào đang hoạt động. Không thể lưu cập nhật.',
            style: TextStyle(color: Color(0xFF92400E)),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _roomId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Phòng hiện tại *',
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
            onChanged: _saving
                ? null
                : (value) => setState(() => _roomId = value),
            validator: (value) => value == null || value.isEmpty
                ? 'Vui lòng chọn phòng đang hoạt động.'
                : null,
          ),
        const SizedBox(height: 16),
        const Text(
          'Email đăng nhập không thể thay đổi.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving || _activeRooms.isEmpty ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Đang lưu...' : 'Lưu thay đổi'),
            ),
          ],
        ),
      ],
    ),
  );
}
