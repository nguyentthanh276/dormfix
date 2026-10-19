import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/app_role.dart';
import '../features/admin_requests/presentation/admin_home_page.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/change_password_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/student_requests/presentation/student_home_page.dart';
import '../features/technician_jobs/data/technician_jobs_repository.dart';
import '../features/technician_jobs/presentation/technician_home_page.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({
    super.key,
    required this.controller,
    this.technicianJobsRepository,
  });

  final AuthController controller;
  final TechnicianJobsRepository? technicianJobsRepository;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.state == AuthViewState.checking) {
      unawaited(widget.controller.restoreSession());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => switch (widget.controller.state) {
      AuthViewState.checking => const _StartupLoadingPage(),
      AuthViewState.signedOut => LoginPage(controller: widget.controller),
      AuthViewState.authenticated => switch (widget.controller.profile?.role) {
        AppRole.admin => AdminHomePage(controller: widget.controller),
        AppRole.student => StudentHomePage(controller: widget.controller),
        AppRole.technician => TechnicianHomePage(
          key: ValueKey('technician-${widget.controller.profile?.id}'),
          controller: widget.controller,
          repository: widget.technicianJobsRepository,
        ),
        null => _InvalidProfilePage(controller: widget.controller),
      },
      AuthViewState.changePasswordRequired => ChangePasswordPage(
        controller: widget.controller,
      ),
      AuthViewState.retryRequired => _StartupErrorPage(
        controller: widget.controller,
      ),
      AuthViewState.unavailable => _ConfigurationErrorPage(
        message:
            widget.controller.error ?? 'Dịch vụ xác thực chưa được cấu hình.',
      ),
    },
  );
}

class _InvalidProfilePage extends StatelessWidget {
  const _InvalidProfilePage({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => _MessagePage(
    title: 'Không thể xác minh quyền',
    message: 'Hồ sơ không có vai trò hợp lệ. Vui lòng đăng xuất và liên hệ quản trị viên.',
    icon: Icons.lock_outline,
    action: TextButton.icon(
      onPressed: controller.isLoading ? null : controller.signOut,
      icon: const Icon(Icons.logout),
      label: const Text('Đăng xuất'),
    ),
  );
}

class _StartupLoadingPage extends StatelessWidget {
  const _StartupLoadingPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Đang kiểm tra phiên đăng nhập...'),
        ],
      ),
    ),
  );
}

class _ConfigurationErrorPage extends StatelessWidget {
  const _ConfigurationErrorPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => _MessagePage(
    title: 'Chưa sẵn sàng kết nối',
    message: message,
    icon: Icons.cloud_off_outlined,
  );
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => _MessagePage(
    title: 'Không thể kiểm tra phiên',
    message:
        controller.error ??
        'Đã xảy ra lỗi khi kiểm tra phiên đăng nhập. Vui lòng thử lại.',
    icon: Icons.cloud_off_outlined,
    action: FilledButton.icon(
      onPressed: controller.isLoading ? null : controller.restoreSession,
      icon: const Icon(Icons.refresh),
      label: const Text('Thử lại'),
    ),
  );
}

class _MessagePage extends StatelessWidget {
  const _MessagePage({
    required this.title,
    required this.message,
    required this.icon,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DormFix')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    ),
  );
}
