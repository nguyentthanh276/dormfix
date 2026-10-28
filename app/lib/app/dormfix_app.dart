import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/technician_jobs/data/technician_jobs_repository.dart';
import '../features/technician_jobs/data/technician_workflow_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/admin_accounts/data/admin_accounts_repository.dart';
import 'startup_page.dart';

class DormFixApp extends StatefulWidget {
  const DormFixApp({
    super.key,
    this.backendReady = false,
    this.backendError,
    this.authRepository,
    this.technicianJobsRepository,
    this.technicianWorkflowRepository,
    this.profileRepository,
    this.adminAccountsRepository,
  });

  final bool backendReady;
  final String? backendError;
  final AuthRepository? authRepository;
  final TechnicianJobsRepository? technicianJobsRepository;
  final TechnicianWorkflowRepository? technicianWorkflowRepository;
  final ProfileRepository? profileRepository;
  final AdminAccountsRepository? adminAccountsRepository;

  @override
  State<DormFixApp> createState() => _DormFixAppState();
}

class _DormFixAppState extends State<DormFixApp> {
  late final AuthController _authController;
  late final TechnicianJobsRepository? _technicianJobsRepository;
  late final TechnicianWorkflowRepository? _technicianWorkflowRepository;
  late final ProfileRepository? _profileRepository;
  late final AdminAccountsRepository? _adminAccountsRepository;

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
    _profileRepository =
        widget.profileRepository ??
        (widget.backendReady
            ? SupabaseProfileRepository(Supabase.instance.client)
            : null);
    _adminAccountsRepository = widget.adminAccountsRepository ??
        (widget.backendReady ? SupabaseAdminAccountsRepository(Supabase.instance.client) : null);
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
      technicianWorkflowRepository: _technicianWorkflowRepository,
      profileRepository: _profileRepository,
      adminAccountsRepository: _adminAccountsRepository,
    ),
  );
}
