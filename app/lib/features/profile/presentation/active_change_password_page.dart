import 'package:flutter/material.dart';

import '../../auth/models/password_rules.dart';
import '../../auth/presentation/auth_controller.dart';

/// DF-004: Màn hình chủ động đổi mật khẩu dành cho Sinh viên và Kỹ thuật viên.
class ActiveChangePasswordPage extends StatefulWidget {
  const ActiveChangePasswordPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ActiveChangePasswordPage> createState() =>
      _ActiveChangePasswordPageState();
}

class _ActiveChangePasswordPageState extends State<ActiveChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate() || widget.controller.isLoading) {
      return;
    }
    final success = await widget.controller.updatePassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;
    if (success) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _formKey.currentState?.reset();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đổi mật khẩu thành công.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đổi mật khẩu')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_reset_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Đổi mật khẩu',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nhập mật khẩu hiện tại và mật khẩu mới để tăng cường bảo mật tài khoản.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('current-password-input'),
                    controller: _currentPasswordController,
                    enabled: !widget.controller.isLoading,
                    obscureText: _obscureCurrentPassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) {
                      if (widget.controller.error != null) {
                        widget.controller.clearError();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu hiện tại',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscureCurrentPassword
                            ? 'Hiện mật khẩu'
                            : 'Ẩn mật khẩu',
                        onPressed: widget.controller.isLoading
                            ? null
                            : () => setState(
                                () => _obscureCurrentPassword =
                                    !_obscureCurrentPassword,
                              ),
                        icon: Icon(
                          _obscureCurrentPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: PasswordRules.validateCurrentPassword,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('new-password-input'),
                    controller: _newPasswordController,
                    enabled: !widget.controller.isLoading,
                    obscureText: _obscureNewPassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: (_) {
                      if (widget.controller.error != null) {
                        widget.controller.clearError();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu mới',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscureNewPassword
                            ? 'Hiện mật khẩu'
                            : 'Ẩn mật khẩu',
                        onPressed: widget.controller.isLoading
                            ? null
                            : () => setState(
                                () =>
                                    _obscureNewPassword = !_obscureNewPassword,
                              ),
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => PasswordRules.validateNewPassword(
                      value,
                      currentPassword: _currentPasswordController.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('confirm-password-input'),
                    controller: _confirmPasswordController,
                    enabled: !widget.controller.isLoading,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _submit(),
                    onChanged: (_) {
                      if (widget.controller.error != null) {
                        widget.controller.clearError();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Xác nhận mật khẩu mới',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirmPassword
                            ? 'Hiện mật khẩu'
                            : 'Ẩn mật khẩu',
                        onPressed: widget.controller.isLoading
                            ? null
                            : () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => PasswordRules.validateConfirmPassword(
                      value,
                      _newPasswordController.text,
                    ),
                  ),
                  if (widget.controller.error case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      key: const Key('auth-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('active-change-password-submit-btn'),
                    onPressed: widget.controller.isLoading ? null : _submit,
                    child: widget.controller.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Đổi mật khẩu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
