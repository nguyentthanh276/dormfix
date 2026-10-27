import 'new_repair_request.dart';

/// Dữ liệu sinh viên chỉnh sửa yêu cầu (DF-011).
/// Chỉ cho phép sửa khi yêu cầu đang ở trạng thái `pending`.
class EditRepairRequest {
  const EditRepairRequest({
    required this.requestId,
    required this.title,
    required this.categoryId,
    required this.description,
    this.keepPhotos = const [],
    this.newAttachments = const [],
  });

  final String requestId;
  final String title;
  final String categoryId;
  final String description;
  final List<String> keepPhotos; // Danh sách tên ảnh cũ giữ lại
  final List<AttachmentDraft> newAttachments; // Ảnh mới thêm vào
}
