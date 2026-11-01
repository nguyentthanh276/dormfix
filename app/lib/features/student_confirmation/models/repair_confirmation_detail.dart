import '../../../core/models/repair_status.dart';

/// Kết quả mà kỹ thuật viên đã báo cáo lên
class TechnicianResultInfo {
  final String content; // Nội dung kết quả sửa chữa
  final String technicianName;
  final DateTime submittedAt;
  final List<String> imageUrls; // Ảnh bằng chứng do thợ chụp gửi lên

  TechnicianResultInfo({
    required this.content,
    required this.technicianName,
    required this.submittedAt,
    this.imageUrls = const [],
  });

  factory TechnicianResultInfo.fromJson(Map<String, dynamic> json) {
    return TechnicianResultInfo(
      content: json['content'] as String? ?? '',
      technicianName:
          json['profiles']?['full_name'] as String? ?? 'Kỹ thuật viên',
      submittedAt:
          DateTime.tryParse(json['submitted_at'] as String? ?? '') ??
          DateTime.now(),
      imageUrls:
          (json['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Thông tin chi tiết một đơn cần sinh viên xác nhận
class RepairConfirmationDetail {
  final String id;
  final String requestCode;
  final String title;
  final String description;
  final String roomCode;
  final String categoryName;
  final RepairStatus status;
  final TechnicianResultInfo? latestResult;

  RepairConfirmationDetail({
    required this.id,
    required this.requestCode,
    required this.title,
    required this.description,
    required this.roomCode,
    required this.categoryName,
    required this.status,
    this.latestResult,
  });

  /// Kiểm tra đơn có đang ở trạng thái Chờ sinh viên xác nhận hay không
  bool get canConfirmOrRework => status == RepairStatus.awaitingConfirmation;

  /// DF-016: Kiểm tra đơn đã hoàn tất có đủ điều kiện mở lại không
  bool canReopen(String? currentStudentRoomCode) {
    return status == RepairStatus.completed &&
        currentStudentRoomCode != null &&
        currentStudentRoomCode == roomCode;
  }
}
