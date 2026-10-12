import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/models/app_role.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/presentation/password_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.auth});
  final AuthService auth;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _phone = TextEditingController();
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _phone.text = widget.auth.current?.phone ?? '';
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.auth.updatePhone(_phone.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật số điện thoại.')),
        );
      }
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Không lưu được hồ sơ.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.auth.current!;
    return Scaffold(
      appBar: AppBar(
        title: Text('DormFix • ${p.role.label}'),
        actions: [
          IconButton(
            onPressed: _busy ? null : widget.auth.logout,
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Hồ sơ cá nhân',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text('Họ tên: ${p.fullName}'),
          Text('Mã: ${p.identityCode}'),
          Text('Email: ${p.email}'),
          Text('Vai trò: ${p.role.label}'),
          if (p.roomCode != null) Text('Phòng: ${p.roomCode}'),
          const SizedBox(height: 20),
          if (p.role != AppRole.admin) ...[
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Số điện thoại'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Lưu số điện thoại'),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PasswordPage(auth: widget.auth),
                    ),
                  ),
            child: const Text('Đổi mật khẩu'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Các màn hình yêu cầu sửa chữa và quản trị đang được phát triển.',
          ),
        ],
      ),
    );
  }
}
