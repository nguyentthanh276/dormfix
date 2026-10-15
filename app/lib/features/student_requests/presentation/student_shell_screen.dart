import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/request_repository.dart';
import 'create_request_screen.dart';
import 'my_requests_screen.dart';
import 'student_account_screen.dart';

/// Khung điều hướng của sinh viên: thanh tab dưới cùng, mỗi tab một màn hình.
class StudentShellScreen extends StatefulWidget {
  final RequestRepository repository;
  final String? name;
  final String? roomCode; // null nếu tài khoản chưa được gắn phòng
  final VoidCallback onSignOut;

  const StudentShellScreen({
    super.key,
    required this.repository,
    required this.name,
    required this.roomCode,
    required this.onSignOut,
  });

  @override
  State<StudentShellScreen> createState() => _StudentShellScreenState();
}

class _StudentShellScreenState extends State<StudentShellScreen> {
  int _tab = 0;

  Widget _page() => switch (_tab) {
    0 => MyRequestsScreen(repository: widget.repository),
    1 => CreateRequestScreen(
      repository: widget.repository,
      roomCode: widget.roomCode,
      onCreated: () => setState(() => _tab = 0), // tạo xong về danh sách
    ),
    _ => StudentAccountScreen(
      name: widget.name,
      roomCode: widget.roomCode,
      onSignOut: widget.onSignOut,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // KeyedSubtree: đổi tab thì dựng lại màn, nên danh sách luôn tải mới.
      body: KeyedSubtree(key: ValueKey(_tab), child: _page()),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.build_circle_outlined),
            label: 'Yêu cầu',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: 'Tạo mới',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
}
