import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/account_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../student_requests/models/repair_request.dart';
import '../../student_requests/presentation/widgets/request_card.dart';
import '../models/technician_info.dart';
import 'admin_request_detail_screen.dart';

/// GIAO DIỆN khung quản lý KTX: Tổng quan / Yêu cầu / Kỹ thuật / Tài khoản.
/// Dữ liệu truyền từ ngoài vào (mock hoặc Supabase), màn này không tự tải.
class AdminShellScreen extends StatefulWidget {
  final List<RepairRequest> requests;
  final List<TechnicianInfo> technicians;
  final String name;
  final VoidCallback onSignOut;

  const AdminShellScreen({
    super.key,
    required this.requests,
    required this.technicians,
    required this.name,
    required this.onSignOut,
  });

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _tab = 0;
  RepairStatus? _status; // lọc ở tab Yêu cầu, null = tất cả

  Widget _page() {
    switch (_tab) {
      case 0:
        return _overview();
      case 1:
        return _requestList();
      case 2:
        return _technicianList();
      default:
        return AccountView(
          name: widget.name,
          roleLabel: 'Quản lý KTX',
          onSignOut: widget.onSignOut,
        );
    }
  }

  // Tổng quan: mỗi trạng thái một ô đếm số yêu cầu.
  Widget _overview() {
    return Scaffold(
      appBar: AppBar(title: const Text('Tổng quan')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(12),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
        children: [
          for (final s in RepairStatus.values)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: s.color, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${widget.requests.where((r) => r.status == s).length}',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: s.color,
                    ),
                  ),
                  Text(s.label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _requestList() {
    final list = widget.requests
        .where((r) => _status == null || r.status == _status)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tất cả yêu cầu')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                _chip(null, 'Tất cả (${widget.requests.length})'),
                for (final s in RepairStatus.values)
                  if (widget.requests.any((r) => r.status == s))
                    _chip(
                      s,
                      '${s.label} (${widget.requests.where((r) => r.status == s).length})',
                    ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyView('Không có yêu cầu nào')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    itemCount: list.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, i) => RequestCard(
                      request: list[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminRequestDetailScreen(
                            request: list[i],
                            technicians: widget.technicians,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(RepairStatus? s, String label) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _status == s,
      onSelected: (_) => setState(() => _status = s),
    ),
  );

  Widget _technicianList() {
    return Scaffold(
      appBar: AppBar(title: const Text('Kỹ thuật viên')),
      body: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: widget.technicians.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final t = widget.technicians[i];
          return Card(
            margin: EdgeInsets.zero,
            color: Colors.white,
            child: ListTile(
              leading: UserAvatar(t.name),
              title: Text(t.name),
              subtitle: Text(t.phone),
              trailing: Text('${t.activeJobs} việc'),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _page(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Tổng quan',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Yêu cầu'),
          BottomNavigationBarItem(
            icon: Icon(Icons.engineering_outlined),
            label: 'Kỹ thuật',
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
