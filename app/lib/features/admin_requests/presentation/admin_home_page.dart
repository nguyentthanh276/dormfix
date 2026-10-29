import 'package:flutter/material.dart';

import '../../admin_accounts/data/admin_accounts_repository.dart';
import '../../admin_accounts/presentation/admin_accounts_page.dart';
import '../../auth/presentation/auth_controller.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key, required this.controller, this.repository});

  final AuthController controller;
  final AdminAccountsRepository? repository;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  bool _showAccounts = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    if (profile == null || profile.role?.databaseValue != 'admin') {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền truy cập.')),
      );
    }
    final repository = widget.repository;
    if (_showAccounts) {
      return repository == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Quản lý tài khoản')),
              body: const Center(child: Text('Dịch vụ chưa sẵn sàng.')),
            )
          : AdminAccountsPage(
              repository: repository,
              isAdmin: true,
              onBack: () => setState(() => _showAccounts = false),
            );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('DormFix - Quản lý KTX'),
        actions: [
          TextButton.icon(
            onPressed: widget.controller.isLoading
                ? null
                : widget.controller.signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Xin chào quản lý${profile.fullName == null ? '' : ', ${profile.fullName}'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => setState(() => _showAccounts = true),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Quản lý tài khoản'),
            ),
          ],
        ),
      ),
    );
  }
}
