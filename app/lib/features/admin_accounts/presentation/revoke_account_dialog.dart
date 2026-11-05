import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../data/admin_accounts_repository.dart';
import '../models/managed_account.dart';

class RevokeAccountDialog extends StatefulWidget {
  const RevokeAccountDialog({
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
          RevokeAccountDialog(repository: repository, account: account),
    );
  }

  @override
  State<RevokeAccountDialog> createState() => _RevokeAccountDialogState();
}

class _RevokeAccountDialogState extends State<RevokeAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.revokeAccount(
        identityCode: widget.account.identityCode,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is AdminAccountsFailure
            ? error.message
            : 'Không thể thu hồi tài khoản. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thu hồi tài khoản?'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.account.fullName} · ${widget.account.identityCode} · ${widget.account.role.label}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Đăng nhập sẽ bị chặn. Hồ sơ, lịch sử và yêu cầu liên quan vẫn được giữ lại.',
            ),
            if (widget.account.role == AppRole.student) ...[
              const SizedBox(height: 6),
              const Text(
                'Admin tiếp tục xử lý các yêu cầu chưa kết thúc của Sinh viên này.',
              ),
            ],
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 10),
            ],
            TextFormField(
              controller: _reason,
              enabled: !_submitting,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Lý do thu hồi *',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Vui lòng nhập lý do thu hồi.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context, false),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: _submitting ? null : _submit,
        icon: _submitting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.person_off_outlined),
        label: Text(_submitting ? 'Đang thu hồi...' : 'Thu hồi'),
      ),
    ],
  );
}
