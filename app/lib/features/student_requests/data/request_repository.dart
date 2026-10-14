import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/repair_request.dart';

/// Màn hình chỉ biết lớp này, không biết dữ liệu đến từ Mock hay Supabase.
abstract class RequestRepository {
  /// DF-008: chỉ yêu cầu của chính sinh viên đang đăng nhập, mới nhất trước.
  Future<List<RepairRequest>> fetchMyRequests();

  /// Danh sách loại sự cố đang sử dụng, để sinh viên chọn khi tạo yêu cầu.
  Future<List<IncidentCategory>> fetchCategories();

  /// DF-007: tạo yêu cầu ở Chờ tiếp nhận. Không tự thử lại khi lỗi (tránh tạo 2 yêu cầu).
  Future<RepairRequest> createRequest(NewRepairRequest request);
}
