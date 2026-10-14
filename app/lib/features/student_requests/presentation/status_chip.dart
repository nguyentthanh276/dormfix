import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_theme.dart';

/// Nhãn màu hiển thị trạng thái yêu cầu.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final RepairStatus status;

  Color get _color => switch (status) {
    RepairStatus.pending => Colors.grey.shade700,
    RepairStatus.assigned || RepairStatus.inProgress => AppColors.blue,
    RepairStatus.awaitingConfirmation ||
    RepairStatus.awaitingRework => AppColors.orange,
    RepairStatus.completed => Colors.green.shade700,
    RepairStatus.rejected || RepairStatus.cancelled => Colors.red.shade700,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        color: _color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
