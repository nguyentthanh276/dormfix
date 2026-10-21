import 'history_entry.dart';
import 'repair_request.dart';

/// Chi tiết một yêu cầu (DF-010): thông tin ở danh sách + mô tả, KTV đang được giao, lịch sử.
class RequestDetail {
  const RequestDetail({
    required this.request,
    required this.description,
    required this.history,
    this.technicianName,
    this.technicianPhone,
  });

  final RepairRequest request;
  final String description;
  final List<HistoryEntry> history; // cũ nhất trước
  final String? technicianName; // null = chưa phân công
  final String? technicianPhone;
}
