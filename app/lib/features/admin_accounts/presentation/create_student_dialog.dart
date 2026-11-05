import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin_rooms/models/admin_room.dart';
import '../../profile/models/phone_rules.dart';
import '../data/admin_accounts_repository.dart';
import '../models/managed_account.dart';

/// DF-031: Hộp thoại tạo tài khoản Sinh viên và gắn phòng dành cho Admin.
class CreateStudentDialog extends StatefulWidget {
  const CreateStudentDialog({super.key, required this.repository});

  final AdminAccountsRepository repository;

  static Future<bool?> show(
    BuildContext context, {
    required AdminAccountsRepository repository,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreateStudentDialog(repository: repository),
    );
  }

  @override
  State<CreateStudentDialog> createState() => _CreateStudentDialogState();
}

class _CreateStudentDialogState extends State<CreateStudentDialog> {
  final _formKey = GlobalKey<FormState>();

  final _identityCodeCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _tempPasswordCtrl = TextEditingController();

  List<AdminRoom> _activeRooms = [];
  String? _selectedRoomId;
  bool _loadingRooms = true;
  String? _roomsError;

  bool _isSubmitting = false;
  String? _errorMessage;
  CreatedStudentResult? _createdResult;

  @override
  void initState() {
    super.initState();
    _loadActiveRooms();
  }

  @override
  void dispose() {
    _identityCodeCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _tempPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActiveRooms() async {
    setState(() {
      _loadingRooms = true;
      _roomsError = null;
    });
    try {
      final rooms = await widget.repository.getActiveRooms();
      if (!mounted) return;
      final active = rooms.where((r) => r.isActive).toList();
      setState(() {
        _activeRooms = active;
        _loadingRooms = false;
        if (active.isNotEmpty && _selectedRoomId == null) {
          _selectedRoomId = active.first.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRooms = false;
        _roomsError = 'Không thể tải danh sách phòng: $e';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoomId == null || _selectedRoomId!.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng chọn phòng đang hoạt động.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.repository.createStudent(
        identityCode: _identityCodeCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim().toLowerCase(),
        phone: _phoneCtrl.text.trim(),
        roomId: _selectedRoomId!,
        temporaryPassword: _tempPasswordCtrl.text.trim().isEmpty
            ? null
            : _tempPasswordCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _createdResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e is AdminAccountsFailure ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = _createdResult != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: isSuccess
              ? _buildSuccessView(context)
              : _buildFormView(context),
        ),
      ),
    );
  }

  Widget _buildFormView(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: AppColors.primaryDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tạo tài khoản Sinh viên',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Điền thông tin và gắn phòng ký túc xá (DF-031)',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
                tooltip: 'Đóng',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFDC2626),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mã Sinh viên
          TextFormField(
            controller: _identityCodeCtrl,
            enabled: !_isSubmitting,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Mã Sinh viên *',
              hintText: 'VD: SV005',
              helperText: 'Mã Sinh viên không thể thay đổi sau khi tạo',
              prefixIcon: const Icon(Icons.badge_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập mã Sinh viên.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Họ và tên
          TextFormField(
            controller: _fullNameCtrl,
            enabled: !_isSubmitting,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Họ và tên *',
              hintText: 'VD: Nguyễn Văn A',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập họ và tên.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Email
          TextFormField(
            controller: _emailCtrl,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email liên hệ / đăng nhập *',
              hintText: 'VD: sinhvien@example.com',
              helperText: 'Email không thể thay đổi sau khi tạo',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập email.';
              }
              final emailRegex = RegExp(
                r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
              );
              if (!emailRegex.hasMatch(value.trim())) {
                return 'Email không đúng định dạng.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Số điện thoại
          TextFormField(
            controller: _phoneCtrl,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Số điện thoại *',
              hintText: 'VD: 0912345678 hoặc +84912345678',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: PhoneRules.validatePhone,
          ),
          const SizedBox(height: 16),

          // Chọn phòng đang hoạt động
          if (_loadingRooms)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Đang tải danh sách phòng hoạt động...'),
                  ),
                ],
              ),
            )
          else if (_roomsError != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _roomsError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loadActiveRooms,
                  child: const Text('Thử lại'),
                ),
              ],
            )
          else if (_activeRooms.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'Hiện không có phòng nào đang hoạt động. Vui lòng kích hoạt phòng trước khi tạo sinh viên.',
                style: TextStyle(color: Color(0xFF92400E), fontSize: 13),
              ),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedRoomId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Gắn phòng KTX *',
                helperText: 'Chỉ hiển thị phòng đang hoạt động',
                prefixIcon: const Icon(Icons.meeting_room_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: _activeRooms.map((room) {
                return DropdownMenuItem<String>(
                  value: room.id,
                  child: Text(
                    '${room.code} (${room.building})',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _isSubmitting
                  ? null
                  : (val) => setState(() => _selectedRoomId = val),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Vui lòng chọn phòng cho Sinh viên.';
                }
                return null;
              },
            ),
          const SizedBox(height: 16),

          // Mật khẩu tạm (tùy chọn)
          TextFormField(
            controller: _tempPasswordCtrl,
            enabled: !_isSubmitting,
            decoration: InputDecoration(
              labelText: 'Mật khẩu tạm (Tùy chọn)',
              hintText: 'Để trống để hệ thống tự tạo mật khẩu',
              helperText: 'Tối thiểu 6 ký tự nếu tự nhập',
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              if (value != null &&
                  value.trim().isNotEmpty &&
                  value.trim().length < 6) {
                return 'Mật khẩu tạm phải có ít nhất 6 ký tự.';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Nút bấm
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isSubmitting || _activeRooms.isEmpty
                    ? null
                    : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSubmitting ? 'Đang tạo...' : 'Tạo tài khoản'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    final result = _createdResult!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF16A34A),
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tạo tài khoản Sinh viên thành công!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF16A34A),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tài khoản đã sẵn sàng. Hãy lưu lại mật khẩu tạm và gửi cho Sinh viên.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Khung thông tin tài khoản
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.pageBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _infoRow('Họ và tên:', result.fullName),
              const Divider(height: 18),
              _infoRow('Mã Sinh viên:', result.identityCode),
              const Divider(height: 18),
              _infoRow('Email đăng nhập:', result.email),
              const Divider(height: 18),
              _infoRow('Số điện thoại:', result.phone),
              const Divider(height: 18),
              _infoRow(
                'Phòng gắn:',
                '${result.roomCode ?? ''} (${result.roomBuilding ?? ''})',
              ),
              const Divider(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 120,
                    child: Text(
                      'Mật khẩu tạm:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        result.temporaryPassword,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.5,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Sao chép mật khẩu',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: result.temporaryPassword),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã sao chép mật khẩu tạm vào bộ nhớ tạm.',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Cảnh báo đổi mật khẩu lần đầu
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Color(0xFFD97706), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sinh viên bắt buộc phải đổi mật khẩu khi đăng nhập lần đầu tiên trước khi có thể sử dụng các chức năng của hệ thống.',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Hoàn tất và Đóng'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
