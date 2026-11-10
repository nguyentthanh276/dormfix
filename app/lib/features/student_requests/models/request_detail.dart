import 'history_entry.dart';
import 'repair_request.dart';

/// Private Storage metadata; never contains a public or signed URL.
class RequestAttachment {
  const RequestAttachment({
    required this.id,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    this.resultId,
    this.feedbackId,
  });

  final String id;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final String? resultId;
  final String? feedbackId;
}

class RequestFeedbackItem {
  const RequestFeedbackItem({
    required this.id,
    required this.kind,
    required this.reason,
    required this.createdAt,
    required this.authorName,
    this.photos = const [],
  });

  final String id;
  final String kind;
  final String reason;
  final DateTime createdAt;
  final String authorName;
  final List<String> photos;
}

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
    this.attachments = const [],
    this.feedback = const [],
    this.categoryId,
    this.canEdit = false,
    this.canCancel = false,
    this.canReopen = false,
  });

  final RepairRequest request;
  final String description;
  final List<HistoryEntry> history; // cũ nhất trước
  final String? technicianName; // null = chưa phân công
  final String? technicianPhone;
  final List<String>
  studentPhotos; // ảnh đính kèm lúc sinh viên tạo yêu cầu (DF-007)
  final List<RepairResultItem> results; // kết quả sửa chữa từ KTV (DF-026)
  final List<RequestAttachment> attachments;
  final List<RequestFeedbackItem> feedback;
  final String? categoryId;
  final bool canEdit;
  final bool canCancel;
  final bool canReopen;

  /// Kết quả mới nhất (nếu có).
  RepairResultItem? get latestResult =>
      results.isNotEmpty ? results.last : null;
}
