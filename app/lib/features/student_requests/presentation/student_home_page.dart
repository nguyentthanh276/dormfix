import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/role_home_page.dart';
import '../../profile/data/profile_repository.dart';
import '../data/mock_request_repository.dart';
import '../data/request_repository.dart';
import 'student_shell_screen.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({
    super.key,
    required this.controller,
    this.profileRepository,
  });

  final AuthController controller;
  final ProfileRepository? profileRepository;

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  // Đổi MockRequestRepository thành bản Supabase chỉ cần sửa đúng một dòng này.
  late final RequestRepository _repository = MockRequestRepository(
    roomCode: widget.controller.profile?.room?.code,
    studentId: widget.controller.profile!.id,
    studentName: widget.controller.profile?.fullName ?? 'Sinh viên',
  );

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    // Sai vai trò hoặc chưa có hồ sơ: dùng lại màn từ chối truy cập của An.
    if (profile == null || profile.role != AppRole.student) {
      return RoleHomePage(controller: widget.controller, role: AppRole.student);
    }
    // Student detail routes belong to this authenticated Home. Removing the
    // Home on logout/expiry also removes every detail above its tab shell.
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (result) => _navigatorKey.currentState?.maybePop(result),
      child: Navigator(
        key: _navigatorKey,
        pages: [
          MaterialPage<void>(
            key: ValueKey('student-shell-${profile.id}'),
            child: StudentShellScreen(
              repository: _repository,
              name: profile.fullName,
              roomCode: profile.room?.code,
              onSignOut: widget.controller.signOut,
              controller: widget.controller,
              profileRepository: widget.profileRepository,
            ),
          ),
        ],
        // The shell page lives until StartupPage removes this Home.
        onDidRemovePage: (_) {},
      ),
    );
  }
}
