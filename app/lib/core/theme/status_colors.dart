import 'package:flutter/material.dart';

import '../models/repair_status.dart';

/// Màu hiển thị của từng trạng thái yêu cầu (dùng cho nhãn và chấm trạng thái).
extension RepairStatusColor on RepairStatus {
  Color get color => switch (this) {
    RepairStatus.pending => const Color(0xFFF59E0B),
    RepairStatus.assigned => const Color(0xFF0EA5E9),
    RepairStatus.inProgress => const Color(0xFF8B5CF6),
    RepairStatus.awaitingConfirmation => const Color(0xFFEA580C),
    RepairStatus.awaitingRework => const Color(0xFFDB2777),
    RepairStatus.completed => const Color(0xFF16A34A),
    RepairStatus.rejected => const Color(0xFFDC2626),
    RepairStatus.cancelled => const Color(0xFF9CA3AF),
  };
}
