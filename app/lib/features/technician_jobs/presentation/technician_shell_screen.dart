import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/account_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../student_requests/models/repair_request.dart';
import '../../student_requests/presentation/widgets/request_card.dart';
import 'technician_job_detail_screen.dart';

/// GIAO DIỆN khung kỹ thuật viên: Việc cần làm / Đã xong / Tài khoản.
/// Dữ liệu truyền từ ngoài vào (mock hoặc Supabase), màn này không tự tải.
class TechnicianShellScreen extends StatefulWidget {
  final List<RepairRequest> jobs; // các việc được giao cho KTV này
  final String name;
  final String phone;
  final VoidCallback onSignOut;

  const TechnicianShellScreen({
    super.key,
    required this.jobs,
    required this.name,
    required this.phone,
    required this.onSignOut,
  });

  @override
  State<TechnicianShellScreen> createState() => _TechnicianShellScreenState();
}

class _TechnicianShellScreenState extends State<TechnicianShellScreen> {
  int _tab = 0;

  // Việc còn phải xử lý: đã phân công, đang xử lý, hoặc sinh viên yêu cầu sửa lại.
  static const _open = {
    RepairStatus.assigned,
    RepairStatus.inProgress,
    RepairStatus.awaitingRework,
  };

  Widget _page() {
    switch (_tab) {
      case 0:
        return _JobList(
          title: 'Việc cần làm',
          emptyText: 'Hiện chưa có việc nào được giao',
          jobs: widget.jobs.where((j) => _open.contains(j.status)).toList(),
        );
      case 1:
        return _JobList(
          title: 'Đã xong',
          emptyText: 'Chưa có việc nào hoàn thành',
          jobs: widget.jobs.where((j) => !_open.contains(j.status)).toList(),
        );
      default:
        return AccountView(
          name: widget.name,
          roleLabel: 'Kỹ thuật viên',
          info: {'Số điện thoại': widget.phone},
          onSignOut: widget.onSignOut,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _page(),
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
            icon: Icon(Icons.handyman_outlined),
            label: 'Việc cần làm',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: 'Đã xong'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<RepairRequest> jobs;

  const _JobList({
    required this.title,
    required this.emptyText,
    required this.jobs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: jobs.isEmpty
          ? EmptyView(emptyText)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              itemCount: jobs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) => RequestCard(
                request: jobs[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TechnicianJobDetailScreen(job: jobs[i]),
                  ),
                ),
              ),
            ),
    );
  }
}
