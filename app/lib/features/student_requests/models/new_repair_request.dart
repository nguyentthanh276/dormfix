import 'dart:typed_data';

/// Một ảnh sinh viên đã chọn, đang chờ gửi kèm yêu cầu.
class AttachmentDraft {
  const AttachmentDraft({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Dữ liệu sinh viên nhập trên form tạo yêu cầu.
/// Không có phòng: phòng do server lấy từ tài khoản đăng nhập.
class NewRepairRequest {
  const NewRepairRequest({
    required this.title,
    required this.categoryId,
    required this.description,
    this.attachments = const [],
    this.requestId,
  });

  final String title;
  final String categoryId;
  final String description;
  final List<AttachmentDraft> attachments;

  /// Retain this UUID and the same immutable draft when retrying an uncertain
  /// create. The server treats it as the idempotency key.
  final String? requestId;
}
