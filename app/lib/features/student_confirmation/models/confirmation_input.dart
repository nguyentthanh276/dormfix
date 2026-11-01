/// Loại hành động xác nhận kết quả của sinh viên
enum ConfirmationAction {
  confirmFixed, // DF-014: Xác nhận đã khắc phục (Hoàn tất)
}

/// Dữ liệu đầu vào khi sinh viên xác nhận hoặc phản hồi
class ConfirmationInput {
  final String requestId;
  final ConfirmationAction action;
  final String?
  note; // Nhận xét (tùy chọn với confirmFixed, bắt buộc với rework/reopen)

  const ConfirmationInput({
    required this.requestId,
    required this.action,
    this.note,
  });

  /// Kiểm tra tính hợp lệ trước khi gửi
  String? validate() {
    if (action != ConfirmationAction.confirmFixed) {
      if (note == null || note!.trim().isEmpty) {
        return 'Vui lòng nhập lý do.';
      }
    }
    return null;
  }
}
