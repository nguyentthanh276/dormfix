// Đóng góp của Nguyễn Tiến Thành (DF-020, DF-022).
// Tiện ích hiển thị được dùng lại trong bộ lọc DF-021 và theo dõi DF-027.

import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/widgets/status_chip.dart';

// DF-020: Định dạng ngày giờ địa phương để hiển thị trên thẻ công việc.
String technicianDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

// DF-022: Dùng nhãn trạng thái chung cho danh sách, chi tiết và lịch sử.
class TechnicianStatusBadge extends StatelessWidget {
  const TechnicianStatusBadge({super.key, required this.status});

  final RepairStatus status;

  @override
  Widget build(BuildContext context) => StatusChip(status);
}

// DF-027: Dùng lại thông báo và nút thao tác ở các màn theo dõi.
class TechnicianJobsMessage extends StatelessWidget {
  const TechnicianJobsMessage({
    super.key,
    required this.icon,
    required this.message,
    this.secondary,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? secondary;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (secondary != null) ...[
            const SizedBox(height: 12),
            Text(secondary!, textAlign: TextAlign.center),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
