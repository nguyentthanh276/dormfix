import 'package:flutter/material.dart';

import '../models/repair_status.dart';
import '../theme/status_colors.dart';

/// Nhãn bo tròn hiển thị trạng thái yêu cầu (dùng chung cho mọi vai trò).
class StatusChip extends StatelessWidget {
  final RepairStatus status;

  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
