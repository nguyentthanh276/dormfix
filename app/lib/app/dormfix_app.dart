import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../features/admin_accounts/data/admin_account_management_repository.dart';
import '../features/admin_accounts/data/admin_accounts_repository.dart';
import '../features/admin_requests/data/admin_request_repository.dart';
import '../features/admin_rooms/data/admin_room_repository.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/incident_categories/data/incident_category_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/student_requests/data/request_repository.dart';
import '../features/student_requests/data/supabase_request_repository.dart';
import '../features/notifications/data/notification_repository.dart';
import '../features/notifications/data/supabase_notification_repository.dart';
import '../features/technician_jobs/data/technician_jobs_repository.dart';
import '../features/technician_jobs/data/technician_tracking_repository.dart';
import '../features/technician_jobs/data/technician_workflow_repository.dart';
import 'startup_page.dart';

class DormFixApp extends StatefulWidget {
  const DormFixApp({
    super.key,
    this.backendReady = false,
    this.backendError,
    this.authRepository,
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

  final bool backendReady;
  final String? backendError;
  final AuthRepository? authRepository;
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
  State<DormFixApp> createState() => _DormFixAppState();
}

class _DormFixAppState extends State<DormFixApp> {
  late final AuthController _authController;
  late final TechnicianJobsRepository? _technicianJobsRepository;
  late final TechnicianTrackingRepository? _technicianTrackingRepository;
  late final TechnicianWorkflowRepository? _technicianWorkflowRepository;
  late final ProfileRepository? _profileRepository;
  late final AdminAccountsRepository? _adminAccountsRepository;
  late final AdminAccountManagementRepository?
  _adminAccountManagementRepository;
  late final AdminRequestRepository? _adminRequestRepository;
  late final AdminRoomRepository? _adminRoomRepository;
  late final IncidentCategoryRepository? _incidentCategoryRepository;
  late final RequestRepository? _studentRequestRepository;
  late final NotificationRepository? _studentNotificationRepository;

  @override
  void initState() {
    super.initState();
    final repository =
        widget.authRepository ??
        (widget.backendReady
            ? SupabaseAuthRepository(Supabase.instance.client)
            : null);
    _authController = AuthController(
      repository: repository,
      configurationError:
          widget.backendError ??
          (repository == null
              ? 'Chưa sẵn sàng kết nối dịch vụ. Hãy kiểm tra cấu hình Supabase.'
              : null),
    );
    // DF-020–027: Khởi tạo các repository cho màn Kỹ thuật viên.
    _technicianJobsRepository =
        widget.technicianJobsRepository ??
        (widget.backendReady
            ? SupabaseTechnicianJobsRepository(Supabase.instance.client)
            : null);
    _technicianWorkflowRepository =
        widget.technicianWorkflowRepository ??
        (widget.backendReady
            ? SupabaseTechnicianWorkflowRepository(Supabase.instance.client)
            : null);
    _technicianTrackingRepository =
        widget.technicianTrackingRepository ??
        (widget.backendReady
            ? SupabaseTechnicianTrackingRepository(Supabase.instance.client)
            : null);
    _profileRepository =
        widget.profileRepository ??
        (widget.backendReady
            ? SupabaseProfileRepository(Supabase.instance.client)
            : null);
    _adminAccountsRepository =
        widget.adminAccountsRepository ??
        (widget.backendReady
            ? SupabaseAdminAccountsRepository(Supabase.instance.client)
            : null);
    final accountsRepository = _adminAccountsRepository;
    _adminAccountManagementRepository =
        widget.adminAccountManagementRepository ??
        (accountsRepository is AdminAccountManagementRepository
            ? accountsRepository as AdminAccountManagementRepository
            : null);
    _adminRequestRepository =
        widget.adminRequestRepository ??
        (widget.backendReady
            ? SupabaseAdminRequestRepository(Supabase.instance.client)
            : null);
    _adminRoomRepository =
        widget.adminRoomRepository ??
        (widget.backendReady
            ? SupabaseAdminRoomRepository(Supabase.instance.client)
            : null);
    _incidentCategoryRepository =
        widget.incidentCategoryRepository ??
        (widget.backendReady
            ? SupabaseIncidentCategoryRepository(Supabase.instance.client)
            : null);
    _studentRequestRepository =
        widget.studentRequestRepository ??
        (widget.backendReady
            ? SupabaseRequestRepository(Supabase.instance.client)
            : null);
    _studentNotificationRepository =
        widget.studentNotificationRepository ??
        (widget.backendReady
            ? SupabaseNotificationRepository(client: Supabase.instance.client)
            : null);
  }

  @override
  void dispose() {
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DormFix',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: StartupPage(
      controller: _authController,
      technicianJobsRepository: _technicianJobsRepository,
      technicianTrackingRepository: _technicianTrackingRepository,
      technicianWorkflowRepository: _technicianWorkflowRepository,
      profileRepository: _profileRepository,
      adminAccountsRepository: _adminAccountsRepository,
      adminAccountManagementRepository: _adminAccountManagementRepository,
      adminRequestRepository: _adminRequestRepository,
      adminRoomRepository: _adminRoomRepository,
      incidentCategoryRepository: _incidentCategoryRepository,
      studentRequestRepository: _studentRequestRepository,
      studentNotificationRepository: _studentNotificationRepository,
    ),
  );
}
