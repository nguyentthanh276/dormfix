/// Loại hành động xác nhận kết quả của sinh viên
enum ConfirmationAction {
  confirmFixed, // DF-014: Xác nhận đã khắc phục (Hoàn tất)
  requestRework, // DF-015: Yêu cầu thợ sửa lại
}

/// Dữ liệu đầu vào khi sinh viên xác nhận hoặc phản hồi
class ConfirmationInput {
  final String requestId;
  final ConfirmationAction action;
  final String?
  note; // Nhận xét (tùy chọn với confirmFixed, bắt buộc với rework/reopen)
  final List<String>
  imagePaths; // Đường dẫn ảnh đính kèm cục bộ (tối đa 5 ảnh, mỗi ảnh <= 5MB)

  const ConfirmationInput({
    required this.requestId,
    required this.action,
    this.note,
    this.imagePaths = const [],
  });

  /// Kiểm tra tính hợp lệ trước khi gửi
  String? validate() {
    if (action != ConfirmationAction.confirmFixed) {
      if (note == null || note!.trim().isEmpty) {
        return 'Vui lòng nhập lý do.';
      }
    }
    if (imagePaths.length > 5) {
      return 'Chỉ được đính kèm tối đa 5 hình ảnh.';
    }
    return null;
  }
}
