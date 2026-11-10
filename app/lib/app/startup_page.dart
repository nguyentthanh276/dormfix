import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/app_role.dart';
import '../features/admin_accounts/data/admin_account_management_repository.dart';
import '../features/admin_requests/presentation/admin_home_page.dart';
import '../features/admin_rooms/data/admin_room_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/change_password_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/incident_categories/data/incident_category_repository.dart';
import '../features/student_requests/presentation/student_home_page.dart';
import '../features/technician_jobs/data/technician_jobs_repository.dart';
import '../features/technician_jobs/data/technician_tracking_repository.dart';
import '../features/technician_jobs/data/technician_workflow_repository.dart';
import '../features/technician_jobs/presentation/technician_home_page.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/admin_accounts/data/admin_accounts_repository.dart';
import '../features/admin_requests/data/admin_request_repository.dart';
import '../features/student_requests/data/request_repository.dart';
import '../features/notifications/data/notification_repository.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({
    super.key,
    required this.controller,
    this.technicianJobsRepository,
    this.technicianTrackingRepository,
    this.technicianWorkflowRepository,
    this.profileRepository,
    this.adminAccountsRepository,
    this.adminAccountManagementRepository,
    this.adminRequestRepository,
    this.adminRoomRepository,
    this.incidentCategoryRepository,
    this.studentRequestRepository,
    this.studentNotificationRepository,
  });

  final AuthController controller;
  final TechnicianJobsRepository? technicianJobsRepository;
  final TechnicianTrackingRepository? technicianTrackingRepository;
  final TechnicianWorkflowRepository? technicianWorkflowRepository;
  final ProfileRepository? profileRepository;
  final AdminAccountsRepository? adminAccountsRepository;
  final AdminAccountManagementRepository? adminAccountManagementRepository;
  final AdminRequestRepository? adminRequestRepository;
  final AdminRoomRepository? adminRoomRepository;
  final IncidentCategoryRepository? incidentCategoryRepository;
  final RequestRepository? studentRequestRepository;
  final NotificationRepository? studentNotificationRepository;

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
        AppRole.admin => AdminHomePage(
          key: ValueKey('admin-${widget.controller.profile?.id}'),
          controller: widget.controller,
          accountsRepository: widget.adminAccountsRepository,
          accountManagementRepository: widget.adminAccountManagementRepository,
          requestsRepository: widget.adminRequestRepository,
          roomsRepository: widget.adminRoomRepository,
          categoriesRepository: widget.incidentCategoryRepository,
        ),
        AppRole.student => StudentHomePage(
          key: ValueKey('student-${widget.controller.profile?.id}'),
          controller: widget.controller,
          profileRepository: widget.profileRepository,
          requestRepository: widget.studentRequestRepository,
          notificationRepository: widget.studentNotificationRepository,
        ),
        // DF-020–027: Mở màn Kỹ thuật viên theo vai trò đã xác thực.
        AppRole.technician => TechnicianHomePage(
          key: ValueKey('technician-${widget.controller.profile?.id}'),
          controller: widget.controller,
          repository: widget.technicianJobsRepository,
          trackingRepository: widget.technicianTrackingRepository,
          workflowRepository: widget.technicianWorkflowRepository,
          profileRepository: widget.profileRepository,
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
