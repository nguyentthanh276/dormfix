import 'dart:typed_data';

import '../../student_confirmation/models/student_confirmation_submission.dart';
import '../models/edit_repair_request.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/repair_request.dart';
import '../models/request_detail.dart';
import '../models/student_request_mutation.dart';

/// Màn hình chỉ biết lớp này, không biết dữ liệu đến từ Mock hay Supabase.
abstract class RequestRepository {
  bool get supportsEditing => true;
  bool get supportsCancellation => true;
  bool get supportsConfirmationActions => false;
  bool get supportsVersionedMutations => false;
  bool get supportsReopening => false;
  bool get allowsDemoFallback => true;

  /// Emits when already displayed private data must be discarded.
  /// Same-user token refresh does not invalidate a view.
  Stream<void> get accessChanges => const Stream<void>.empty();

  Future<Uint8List> fetchAttachment(
    String requestId,
    RequestAttachment attachment,
  ) async => throw const RequestFailure('Ảnh chưa sẵn sàng.');

  Future<StudentConfirmationReceipt> submitConfirmation(
    StudentConfirmationSubmission submission,
  ) async => throw const RequestFailure('Chức năng xác nhận chưa sẵn sàng.');

  Future<StudentConfirmationReceipt> submitMutation(
    StudentRequestMutation mutation,
  ) async => throw const RequestFailure('Thao tác yêu cầu chưa sẵn sàng.');

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

class RequestFailure implements Exception {
  const RequestFailure(
    this.message, {
    this.accessDenied = false,
    this.uncertain = false,
    this.conflict = false,
  });

  final String message;
  final bool accessDenied;
  final bool uncertain;
  final bool conflict;

  @override
  String toString() => message;
}
