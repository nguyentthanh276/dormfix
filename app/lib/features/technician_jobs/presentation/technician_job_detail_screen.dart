import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../student_requests/models/repair_request.dart';
import '../../student_requests/presentation/widgets/category_icon.dart';

/// GIAO DIỆN chi tiết một việc của kỹ thuật viên. Nút hành động mới chỉ báo "chưa nối dữ liệu".
class TechnicianJobDetailScreen extends StatelessWidget {
  final RepairRequest job;

  const TechnicianJobDetailScreen({super.key, required this.job});

  // Nút hành động hợp lệ theo trạng thái hiện tại (null = không có thao tác).
  String? get _actionLabel => switch (job.status) {
    RepairStatus.assigned => 'Bắt đầu xử lý',
    RepairStatus.inProgress || RepairStatus.awaitingRework => 'Báo hoàn tất',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final action = _actionLabel;
    return Scaffold(
      appBar: AppBar(title: Text(job.requestCode)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            child: Row(
              children: [
                Icon(categoryIcon(job.categoryName), size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      StatusChip(job.status),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Thông tin',
            child: Column(
              children: [
                InfoRow('Loại sự cố', job.categoryName),
                InfoRow('Phòng', job.roomCode),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$action: chưa nối dữ liệu')),
                ),
                child: Text(action),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
