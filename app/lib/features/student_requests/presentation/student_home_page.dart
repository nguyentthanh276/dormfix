import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/role_home_page.dart';
import '../data/mock_request_repository.dart';
import '../data/request_repository.dart';
import 'student_shell_screen.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  // Đổi MockRequestRepository thành bản Supabase chỉ cần sửa đúng một dòng này.
  late final RequestRepository _repository = MockRequestRepository(
    roomCode: widget.controller.profile?.room?.code,
  );

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    // Sai vai trò hoặc chưa có hồ sơ: dùng lại màn từ chối truy cập của An.
    if (profile == null || profile.role != AppRole.student) {
      return RoleHomePage(controller: widget.controller, role: AppRole.student);
    }
    return StudentShellScreen(
      repository: _repository,
      name: profile.fullName,
      roomCode: profile.room?.code,
      onSignOut: widget.controller.signOut,
    );
  }
}
