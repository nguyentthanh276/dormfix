import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../student_requests/models/repair_request.dart';
import '../models/technician_info.dart';

/// GIAO DIỆN chi tiết yêu cầu của quản lý: chọn kỹ thuật viên để phân công (chưa nối dữ liệu).
class AdminRequestDetailScreen extends StatefulWidget {
  final RepairRequest request;
  final List<TechnicianInfo> technicians;

  const AdminRequestDetailScreen({
    super.key,
    required this.request,
    required this.technicians,
  });

  @override
  State<AdminRequestDetailScreen> createState() =>
      _AdminRequestDetailScreenState();
}

class _AdminRequestDetailScreenState extends State<AdminRequestDetailScreen> {
  String? _technicianId;

  // Chỉ phân công được khi yêu cầu còn Chờ tiếp nhận.
  bool get _canAssign => widget.request.status == RepairStatus.pending;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Scaffold(
      appBar: AppBar(title: Text(r.requestCode)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StatusChip(r.status),
              ],
            ),
          ),
          SectionCard(
            title: 'Thông tin',
            child: Column(
              children: [
                InfoRow('Loại sự cố', r.categoryName),
                InfoRow('Phòng', r.roomCode),
              ],
            ),
          ),
          if (_canAssign)
            SectionCard(
              title: 'Phân công kỹ thuật viên',
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _technicianId,
                    hint: const Text('Chọn kỹ thuật viên'),
                    items: [
                      for (final t in widget.technicians)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.name} (${t.activeJobs} việc)'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _technicianId = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      // Chưa chọn KTV thì khóa nút.
                      onPressed: _technicianId == null
                          ? null
                          : () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Phân công: chưa nối dữ liệu'),
                              ),
                            ),
                      child: const Text('Phân công'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
