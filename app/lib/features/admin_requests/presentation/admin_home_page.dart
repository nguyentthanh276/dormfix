import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../admin_accounts/data/admin_accounts_repository.dart';
import '../../admin_accounts/presentation/admin_accounts_page.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/admin_request_repository.dart';
import 'admin_requests_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({
    super.key,
    required this.controller,
    this.accountsRepository,
    this.requestsRepository,
  });

  final AuthController controller;
  final AdminAccountsRepository? accountsRepository;
  final AdminRequestRepository? requestsRepository;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  bool _showAccounts = false;
  bool _showRequests = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    if (profile == null || profile.role != AppRole.admin) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền truy cập.')),
      );
    }

    if (_showAccounts) return _accountsPage();
    if (_showRequests) return _requestsPage();

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Xin chào quản lý${profile.fullName == null ? '' : ', ${profile.fullName}'}',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => setState(() => _showRequests = true),
                  icon: const Icon(Icons.home_repair_service_outlined),
                  label: const Text('Quản lý yêu cầu sửa chữa'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showAccounts = true),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Quản lý tài khoản'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountsPage() {
    final repository = widget.accountsRepository;
    if (repository == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Quản lý tài khoản'),
          leading: BackButton(
            onPressed: () => setState(() => _showAccounts = false),
          ),
        ),
        body: const Center(
          child: Text('Dịch vụ quản lý tài khoản chưa sẵn sàng.'),
        ),
      );
    }
    return AdminAccountsPage(
      repository: repository,
      isAdmin: true,
      onBack: () => setState(() => _showAccounts = false),
    );
  }

  Widget _requestsPage() {
    final repository = widget.requestsRepository;
    if (repository == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Yêu cầu sửa chữa'),
          leading: BackButton(
            onPressed: () => setState(() => _showRequests = false),
          ),
        ),
        body: const Center(
          child: Text('Dịch vụ yêu cầu sửa chữa chưa sẵn sàng.'),
        ),
      );
    }
    return AdminRequestsPage(
      repository: repository,
      isAdmin: true,
      onSignOut: widget.controller.signOut,
      onBack: () => setState(() => _showRequests = false),
    );
  }
}
