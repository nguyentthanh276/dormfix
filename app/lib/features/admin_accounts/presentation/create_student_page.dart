import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/app_role.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/admin_accounts_repository.dart';
import '../models/room_summary.dart';
import 'create_student_controller.dart';

/// Screen for an Admin to create a new Student account (DF-031).
///
/// Navigated to from [AdminHomePage]. Pushes a new route so the Admin can
/// stay on the home page after the dialog is dismissed.
class CreateStudentPage extends StatefulWidget {
  const CreateStudentPage({
    super.key,
    required this.authController,
    this.repository,
  });

  final AuthController authController;

  /// Injectable for testing; defaults to [SupabaseAdminAccountsRepository].
  final AdminAccountsRepository? repository;

  @override
  State<CreateStudentPage> createState() => _CreateStudentPageState();
}

class _CreateStudentPageState extends State<CreateStudentPage> {
  final _formKey = GlobalKey<FormState>();
  late final CreateStudentController _controller;

  // Form field controllers
  final _identityCodeCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final repo =
        widget.repository ??
        SupabaseAdminAccountsRepository(Supabase.instance.client);
    _controller = CreateStudentController(repository: repo);
    unawaited(_controller.loadRooms());
  }

  @override
  void dispose() {
    _controller.dispose();
    _identityCodeCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Sync text fields → controller fields before submit
    _controller
      ..identityCode = _identityCodeCtrl.text
      ..fullName = _fullNameCtrl.text
      ..email = _emailCtrl.text
      ..phone = _phoneCtrl.text
      ..tempPassword = _passwordCtrl.text;

    final success = await _controller.submit();
    if (success && mounted) {
      // Show success dialog, then pop back to Admin home
      await _showSuccessDialog();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _showSuccessDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.check_circle_outline,
          color: Theme.of(ctx).colorScheme.primary,
          size: 48,
        ),
        title: const Text('Tạo tài khoản thành công'),
        content: const Text(
          'Tài khoản Sinh viên đã được tạo.\n'
          'Sinh viên sẽ được yêu cầu đổi mật khẩu khi đăng nhập lần đầu.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tạo tài khoản Sinh viên')),
    body: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => switch (_controller.state) {
        CreateStudentState.loadingRooms => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang tải danh sách phòng…'),
            ],
          ),
        ),
        CreateStudentState.roomLoadError => _ErrorBody(
          message: _controller.error ?? 'Không thể tải danh sách phòng.',
          onRetry: _controller.loadRooms,
        ),
        _ => _FormBody(
          formKey: _formKey,
          controller: _controller,
          identityCodeCtrl: _identityCodeCtrl,
          fullNameCtrl: _fullNameCtrl,
          emailCtrl: _emailCtrl,
          phoneCtrl: _phoneCtrl,
          passwordCtrl: _passwordCtrl,
          obscurePassword: _obscurePassword,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          onSubmit: _submit,
        ),
      },
    ),
  );
}

// ── Form body ─────────────────────────────────────────────────────────────────

class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.formKey,
    required this.controller,
    required this.identityCodeCtrl,
    required this.fullNameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final CreateStudentController controller;
  final TextEditingController identityCodeCtrl;
  final TextEditingController fullNameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final isSubmitting = controller.state == CreateStudentState.submitting;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Icon(
                  Icons.person_add_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Thêm Sinh viên mới',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sinh viên sẽ nhận mật khẩu tạm và phải đổi khi đăng nhập lần đầu.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // ── Mã Sinh viên ─────────────────────────────────────────────
                TextFormField(
                  key: const Key('field-identity-code'),
                  controller: identityCodeCtrl,
                  enabled: !isSubmitting,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Mã Sinh viên *',
                    hintText: 'Ví dụ: SV00123',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: controller.validateIdentityCode,
                ),
                const SizedBox(height: 16),

                // ── Họ tên ───────────────────────────────────────────────────
                TextFormField(
                  key: const Key('field-full-name'),
                  controller: fullNameCtrl,
                  enabled: !isSubmitting,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên *',
                    hintText: 'Ví dụ: Nguyễn Văn A',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: controller.validateFullName,
                ),
                const SizedBox(height: 16),

                // ── Email ────────────────────────────────────────────────────
                TextFormField(
                  key: const Key('field-email'),
                  controller: emailCtrl,
                  enabled: !isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email đăng nhập *',
                    hintText: 'Ví dụ: sv001@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: controller.validateEmail,
                ),
                const SizedBox(height: 16),

                // ── SĐT ─────────────────────────────────────────────────────
                TextFormField(
                  key: const Key('field-phone'),
                  controller: phoneCtrl,
                  enabled: !isSubmitting,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại *',
                    hintText: 'Ví dụ: 0901234567',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: controller.validatePhone,
                ),
                const SizedBox(height: 16),

                // ── Phòng ────────────────────────────────────────────────────
                DropdownButtonFormField<RoomSummary>(
                  key: const Key('field-room'),
                  value: controller.selectedRoom,
                  items: controller.rooms
                      .map(
                        (room) => DropdownMenuItem(
                          value: room,
                          child: Text(room.label),
                        ),
                      )
                      .toList(),
                  onChanged: isSubmitting ? null : controller.selectRoom,
                  decoration: const InputDecoration(
                    labelText: 'Phòng *',
                    prefixIcon: Icon(Icons.meeting_room_outlined),
                  ),
                  validator: (_) =>
                      controller.validateRoom(controller.selectedRoom),
                ),
                const SizedBox(height: 16),

                // ── Mật khẩu tạm ─────────────────────────────────────────────
                TextFormField(
                  key: const Key('field-temp-password'),
                  controller: passwordCtrl,
                  enabled: !isSubmitting,
                  obscureText: obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu tạm *',
                    hintText: 'Ít nhất 8 ký tự',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: obscurePassword
                          ? 'Hiện mật khẩu'
                          : 'Ẩn mật khẩu',
                      onPressed: isSubmitting ? null : onToggleObscure,
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: controller.validateTempPassword,
                ),

                // ── Error banner ─────────────────────────────────────────────
                if (controller.error case final err?) ...[
                  const SizedBox(height: 16),
                  Text(
                    err,
                    key: const Key('create-student-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 28),

                // ── Submit ───────────────────────────────────────────────────
                FilledButton.icon(
                  key: const Key('btn-create-student'),
                  onPressed: isSubmitting ? null : onSubmit,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_outlined),
                  label: Text(isSubmitting ? 'Đang tạo…' : 'Tạo tài khoản'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('btn-retry-rooms'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}

// ─── Helper: navigate to CreateStudentPage ────────────────────────────────────

/// Push the Create Student route from any Admin context.
Future<bool?> pushCreateStudentPage(
  BuildContext context, {
  required AuthController authController,
  AdminAccountsRepository? repository,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute<bool>(
    builder: (_) => CreateStudentPage(
      authController: authController,
      repository: repository,
    ),
  ),
);
