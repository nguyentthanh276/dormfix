import 'package:flutter/material.dart';

import '../../../core/widgets/dormfix_app_bar.dart';

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
  bool _allowLeave = false;
  bool _askingToLeave = false;

  bool get _hasDraft => [
    _currentPasswordController,
    _newPasswordController,
    _confirmPasswordController,
  ].any((controller) => controller.text.isNotEmpty);

  Future<void> _requestBack() async {
    if (widget.controller.isLoading || _askingToLeave) return;
    if (!_hasDraft) {
      Navigator.of(context).pop();
      return;
    }
    _askingToLeave = true;
    final discard = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ thay đổi?'),
        content: const Text('Thông tin mật khẩu đang nhập sẽ không được lưu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tiếp tục nhập'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ thay đổi'),
          ),
        ],
      ),
    );
    _askingToLeave = false;
    if (!mounted || discard != true) return;
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

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
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave || (!_hasDraft && !widget.controller.isLoading),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _requestBack();
    },
    child: Scaffold(
      appBar: DormFixAppBar(
        title: 'Đổi mật khẩu',
        leading: Navigator.of(context).canPop()
            ? BackButton(onPressed: _requestBack)
            : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Đổi mật khẩu',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nhập mật khẩu hiện tại và mật khẩu mới để tăng cường bảo mật tài khoản.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('current-password-input'),
                      controller: _currentPasswordController,
                      enabled: !widget.controller.isLoading,
                      obscureText: _obscureCurrentPassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      onChanged: (_) {
                        setState(() {});
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
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('new-password-input'),
                      controller: _newPasswordController,
                      enabled: !widget.controller.isLoading,
                      obscureText: _obscureNewPassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      onChanged: (_) {
                        setState(() {});
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
                                  () => _obscureNewPassword =
                                      !_obscureNewPassword,
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
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _PasswordRequirementItem(
                            isMet: PasswordRules.hasMinLength(
                              _newPasswordController.text,
                            ),
                            text: '≥6 ký tự',
                          ),
                          _PasswordRequirementItem(
                            isMet: PasswordRules.hasLetter(
                              _newPasswordController.text,
                            ),
                            text: 'Có chữ cái',
                          ),
                          _PasswordRequirementItem(
                            isMet: PasswordRules.hasDigit(
                              _newPasswordController.text,
                            ),
                            text: 'Có chữ số',
                          ),
                          _PasswordRequirementItem(
                            isMet:
                                _currentPasswordController.text.isNotEmpty &&
                                _newPasswordController.text.isNotEmpty &&
                                _newPasswordController.text !=
                                    _currentPasswordController.text,
                            text: 'Khác mật khẩu cũ',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                      validator: (value) =>
                          PasswordRules.validateConfirmPassword(
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
    ),
  );
}

class _PasswordRequirementItem extends StatelessWidget {
  const _PasswordRequirementItem({required this.isMet, required this.text});

  final bool isMet;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = isMet ? Colors.green.shade700 : Colors.black45;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isMet ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: isMet ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
