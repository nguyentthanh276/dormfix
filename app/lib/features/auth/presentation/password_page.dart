import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/security/password_hasher.dart';
import '../data/auth_service.dart';

class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key, required this.auth, this.mandatory = false});
  final AuthService auth;
  final bool mandatory;
  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final _form = GlobalKey<FormState>();
  final _old = TextEditingController(),
      _new = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.changePassword(_old.text, _new.text);
      if (mounted && !widget.mandatory) Navigator.of(context).pop();
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không lưu được mật khẩu. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.mandatory,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Đổi mật khẩu'),
        automaticallyImplyLeading: !widget.mandatory,
        actions: widget.mandatory
            ? [
                TextButton(
                  onPressed: _busy ? null : widget.auth.logout,
                  child: const Text('Đăng xuất'),
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.mandatory)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text('Bạn cần đổi mật khẩu tạm trước khi sử dụng.'),
                ),
              TextFormField(
                controller: _old,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu hiện tại',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Nhập mật khẩu hiện tại.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _new,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
                validator: (v) =>
                    PasswordHasher.validate(v ?? '') ??
                    (v == _old.text
                        ? 'Mật khẩu mới phải khác mật khẩu hiện tại.'
                        : null),
              ),
              const SizedBox(height: 8),
              const Text('Ít nhất 8 ký tự, có chữ hoa, chữ thường và số.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Xác nhận mật khẩu mới',
                ),
                validator: (v) =>
                    v != _new.text ? 'Mật khẩu xác nhận không trùng.' : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Đang lưu…' : 'Lưu mật khẩu'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
