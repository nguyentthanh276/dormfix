import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/role_home_page.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) =>
      RoleHomePage(controller: controller, role: AppRole.admin);
}
