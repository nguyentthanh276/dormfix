import '../../../core/models/repair_status.dart';
import 'repair_request.dart';

/// DF-009: lọc danh sách yêu cầu theo TRẠNG THÁI (chỉ trạng thái, không lọc loại/ngày/từ khóa).
/// Viết thành hàm thuần (không dùng setState, không gọi mạng) để unit test dễ.
abstract final class RequestFilter {
  /// Trả về các yêu cầu có đúng trạng thái [status]. [status] null nghĩa là "Tất cả".
  static List<RepairRequest> byStatus(
    List<RepairRequest> all,
    RepairStatus? status,
  ) {
    if (status == null) {
      // Không lọc: trả bản sao của danh sách.
      return List.of(all);
    }
    return all.where((r) => r.status == status).toList();
  }

  /// Các trạng thái ĐANG CÓ trong danh sách, theo thứ tự khai báo của enum.
  /// Dùng để chỉ hiện nhãn lọc cho trạng thái nào thật sự có yêu cầu.
  static List<RepairStatus> availableStatuses(List<RepairRequest> all) {
    return RepairStatus.values
        .where((s) => all.any((r) => r.status == s))
        .toList();
  }

  /// Đếm số yêu cầu của một trạng thái (hiện trong nhãn, ví dụ "Hoàn tất (2)").
  static int count(List<RepairRequest> all, RepairStatus status) {
    return all.where((r) => r.status == status).length;
  }

  /// Chống "kẹt bộ lọc": nếu trạng thái đang chọn không còn yêu cầu nào
  /// (ví dụ sau khi tải lại dữ liệu), coi như "Tất cả" (null).
  /// Nếu không có bước này, danh sách sẽ trống và nhãn lọc cũng biến mất,
  /// người dùng không có cách nào thoát ra.
  static RepairStatus? validSelection(
    List<RepairRequest> all,
    RepairStatus? selected,
  ) {
    if (selected == null) return null;
    return all.any((r) => r.status == selected) ? selected : null;
  }
}
