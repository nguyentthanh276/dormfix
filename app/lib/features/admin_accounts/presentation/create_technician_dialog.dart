import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../profile/models/phone_rules.dart';
import '../data/admin_accounts_repository.dart';
import '../models/managed_account.dart';

class CreateTechnicianDialog extends StatefulWidget {
  const CreateTechnicianDialog({super.key, required this.repository});

  final AdminAccountsRepository repository;

  static Future<bool?> show(
    BuildContext context, {
    required AdminAccountsRepository repository,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreateTechnicianDialog(repository: repository),
    );
  }

  @override
  State<CreateTechnicianDialog> createState() => _CreateTechnicianDialogState();
}

class _CreateTechnicianDialogState extends State<CreateTechnicianDialog> {
  final _formKey = GlobalKey<FormState>();
  final _identityCode = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _temporaryPassword = TextEditingController();

  bool _submitting = false;
  String? _error;
  CreatedTechnicianResult? _created;

  @override
  void dispose() {
    _identityCode.dispose();
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _temporaryPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.createTechnician(
        identityCode: _identityCode.text.trim(),
        fullName: _fullName.text.trim(),
        email: _email.text.trim().toLowerCase(),
        phone: _phone.text.trim(),
        temporaryPassword: _temporaryPassword.text.trim().isEmpty
            ? null
            : _temporaryPassword.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _created = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is AdminAccountsFailure
            ? error.message
            : 'Không thể tạo tài khoản Kỹ thuật viên. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: _created == null ? _buildForm(context) : _buildSuccess(context),
      ),
    ),
  );

  Widget _buildForm(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.engineering_outlined,
              color: AppColors.primaryDark,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tạo tài khoản Kỹ thuật viên',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Đóng',
              onPressed: _submitting
                  ? null
                  : () => Navigator.pop(context, false),
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
        _textField(
          controller: _identityCode,
          label: 'Mã Kỹ thuật viên *',
          hint: 'VD: KTV004',
          icon: Icons.badge_outlined,
          capitalization: TextCapitalization.characters,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Vui lòng nhập mã Kỹ thuật viên.'
              : null,
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _fullName,
          label: 'Họ và tên *',
          hint: 'VD: Nguyễn Văn A',
          icon: Icons.person_outline,
          capitalization: TextCapitalization.words,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Vui lòng nhập họ và tên.'
              : null,
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _email,
          label: 'Email liên hệ / đăng nhập *',
          hint: 'kythuat@example.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Vui lòng nhập email.';
            }
            if (!RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
                .hasMatch(value.trim())) {
              return 'Email không đúng định dạng.';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _phone,
          label: 'Số điện thoại *',
          hint: '0912345678 hoặc +84912345678',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          validator: PhoneRules.validatePhone,
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _temporaryPassword,
          label: 'Mật khẩu tạm (tùy chọn)',
          hint: 'Để trống để hệ thống tự tạo',
          icon: Icons.lock_outline,
          validator: (value) =>
              value != null &&
                  value.trim().isNotEmpty &&
                  value.trim().length < 6
              ? 'Mật khẩu tạm phải có ít nhất 6 ký tự.'
              : null,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(_submitting ? 'Đang tạo...' : 'Tạo tài khoản'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextCapitalization capitalization = TextCapitalization.none,
    TextInputType? keyboardType,
  }) => TextFormField(
    controller: controller,
    enabled: !_submitting,
    textCapitalization: capitalization,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    validator: validator,
  );

  Widget _buildSuccess(BuildContext context) {
    final result = _created!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF16A34A),
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          'Tạo tài khoản Kỹ thuật viên thành công!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF16A34A),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _infoRow('Họ và tên:', result.fullName),
        _infoRow('Mã Kỹ thuật viên:', result.identityCode),
        _infoRow('Email đăng nhập:', result.email),
        _infoRow('Số điện thoại:', result.phone),
        const Divider(height: 24),
        Row(
          children: [
            const Text(
              'Mật khẩu tạm:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                result.temporaryPassword,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Sao chép mật khẩu',
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: result.temporaryPassword),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép mật khẩu tạm.')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Kỹ thuật viên phải đổi mật khẩu khi đăng nhập lần đầu trước khi sử dụng hệ thống.',
          style: TextStyle(color: Color(0xFF92400E)),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Hoàn tất và Đóng'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
