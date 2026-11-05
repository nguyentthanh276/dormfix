import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/admin_accounts_repository.dart';
import '../models/managed_account.dart';

class ResetPasswordDialog extends StatefulWidget {
  const ResetPasswordDialog({
    super.key,
    required this.repository,
    required this.account,
  });

  final AdminAccountsRepository repository;
  final ManagedAccount account;

  static Future<void> show(
    BuildContext context, {
    required AdminAccountsRepository repository,
    required ManagedAccount account,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        ResetPasswordDialog(repository: repository, account: account),
  );

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  bool _submitting = false;
  String? _error;
  ResetPasswordResult? _result;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.resetPassword(
        identityCode: widget.account.identityCode,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is AdminAccountsFailure
            ? error.message
            : 'Không thể đặt lại mật khẩu. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_result == null ? 'Đặt lại mật khẩu?' : 'Mật khẩu tạm mới'),
    content: SizedBox(
      width: 440,
      child: _result == null
          ? _confirmationContent(context)
          : _resultContent(context),
    ),
    actions: _result == null
        ? [
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
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
                  : const Icon(Icons.lock_reset_outlined),
              label: Text(_submitting ? 'Đang đặt lại...' : 'Cấp mật khẩu tạm'),
            ),
          ]
        : [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hoàn tất'),
            ),
          ],
  );

  Widget _confirmationContent(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${widget.account.fullName} · ${widget.account.identityCode} · ${widget.account.role.label}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text(
        'Hệ thống sẽ cấp mật khẩu tạm mới và yêu cầu đổi mật khẩu ở lần đăng nhập kế tiếp. Các phiên đăng nhập hiện tại sẽ bị thu hồi.',
      ),
      if (widget.account.status != AccountStatus.active) ...[
        const SizedBox(height: 8),
        Text(
          'Trạng thái hiện tại: ${widget.account.status.label}. Đặt lại mật khẩu không thay đổi trạng thái tài khoản.',
          style: const TextStyle(color: Color(0xFF92400E)),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );

  Widget _resultContent(BuildContext context) {
    final result = _result!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${result.fullName} · ${result.identityCode}'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                result.temporaryPassword,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Sao chép mật khẩu tạm',
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
        const SizedBox(height: 8),
        const Text(
          'Mật khẩu này chỉ hiển thị trong màn hình hiện tại. Hãy gửi an toàn cho người dùng.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Khi đăng nhập, người dùng phải đổi mật khẩu trước khi sử dụng hệ thống.',
          style: TextStyle(color: Color(0xFF92400E)),
        ),
        if (result.status == AccountStatus.revoked.databaseValue) ...[
          const SizedBox(height: 8),
          const Text(
            'Tài khoản đang bị thu hồi nên chưa thể đăng nhập cho tới khi được khôi phục.',
          ),
        ],
      ],
    );
  }
}
