import '../models/edit_repair_request.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/repair_request.dart';
import '../models/request_detail.dart';

/// Màn hình chỉ biết lớp này, không biết dữ liệu đến từ Mock hay Supabase.
abstract class RequestRepository {
  /// DF-008: chỉ yêu cầu của chính sinh viên đang đăng nhập, mới nhất trước.
  Future<List<RepairRequest>> fetchMyRequests();

  /// DF-010: chi tiết + lịch sử một yêu cầu của chính sinh viên. Ném lỗi nếu không có.
  Future<RequestDetail> fetchRequestDetail(String requestId);

  /// Danh sách loại sự cố đang sử dụng, để sinh viên chọn khi tạo/sửa yêu cầu.
  Future<List<IncidentCategory>> fetchCategories();

  /// DF-007: tạo yêu cầu ở Chờ tiếp nhận. Không tự thử lại khi lỗi (tránh tạo 2 yêu cầu).
  Future<RepairRequest> createRequest(NewRepairRequest request);

  /// DF-011: sửa yêu cầu khi ở trạng thái Chờ tiếp nhận (pending).
  Future<void> updateRequest(EditRepairRequest request);

  /// DF-012: hủy yêu cầu khi ở pending hoặc assigned. Lý do bắt buộc.
  /// Ném lỗi nếu trạng thái không cho phép hủy (ví dụ đã in_progress).
  Future<void> cancelRequest({
    required String requestId,
    required String reason,
  });
}
