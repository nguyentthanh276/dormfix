import 'history_entry.dart';
import 'repair_request.dart';

/// Kết quả sửa chữa từ Kỹ thuật viên (DF-026 / DF-010).
class RepairResultItem {
  const RepairResultItem({
    required this.id,
    required this.technicianName,
    required this.content,
    required this.submittedAt,
    this.photos = const [],
  });

  final String id;
  final String technicianName;
  final String content;
  final DateTime submittedAt;
  final List<String> photos;
}

/// Chi tiết một yêu cầu (DF-010): thông tin ở danh sách, mô tả, ảnh sinh viên,
/// KTV đang được giao, kết quả sửa chữa và lịch sử tiến trình.
class RequestDetail {
  const RequestDetail({
    required this.request,
    required this.description,
    required this.history,
    this.technicianName,
    this.technicianPhone,
    this.studentPhotos = const [],
    this.results = const [],
  });

  final RepairRequest request;
  final String description;
  final List<HistoryEntry> history; // cũ nhất trước
  final String? technicianName; // null = chưa phân công
  final String? technicianPhone;
  final List<String>
  studentPhotos; // ảnh đính kèm lúc sinh viên tạo yêu cầu (DF-007)
  final List<RepairResultItem> results; // kết quả sửa chữa từ KTV (DF-026)

  /// Kết quả mới nhất (nếu có).
  RepairResultItem? get latestResult =>
      results.isNotEmpty ? results.last : null;
}
