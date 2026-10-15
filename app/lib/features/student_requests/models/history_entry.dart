import '../../../core/models/repair_status.dart';

/// Một dòng lịch sử của yêu cầu (khớp bảng request_history): đổi sang trạng thái nào, ghi chú gì, lúc nào.
class HistoryEntry {
  const HistoryEntry({
    required this.status,
    required this.note,
    required this.createdAt,
  });

  final RepairStatus status;
  final String note;
  final DateTime createdAt;
}
