import '../../../core/models/repair_status.dart';

/// Một yêu cầu sửa chữa của sinh viên (khớp bảng repair_requests, chỉ các cột cần cho danh sách).
class RepairRequest {
  const RepairRequest({
    required this.id,
    required this.requestCode,
    required this.title,
    required this.categoryName,
    required this.roomCode,
    required this.status,
    required this.createdAt,
    this.version = 1,
    this.studentId,
  });

  final String id;
  final String requestCode; // mã hiển thị, ví dụ DF000001
  final String title;
  final String categoryName; // tên loại sự cố tại thời điểm gửi
  final String roomCode; // phòng tại thời điểm gửi
  final RepairStatus status;
  final DateTime createdAt;
  final int version;
  final String? studentId;
}
