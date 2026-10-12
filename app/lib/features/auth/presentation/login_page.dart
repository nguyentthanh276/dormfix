import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../data/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});
  final AuthService auth;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(_email.text, _password.text);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không đọc được dữ liệu. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DormFix')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Đăng nhập',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text('Sửa chữa ký túc xá'),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) =>
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Nhập email đúng định dạng.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mật khẩu'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Nhập mật khẩu.' : null,
                  onFieldSubmitted: (_) => _login(),
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
                  onPressed: _busy ? null : _login,
                  child: Text(_busy ? 'Đang đăng nhập…' : 'Đăng nhập'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
