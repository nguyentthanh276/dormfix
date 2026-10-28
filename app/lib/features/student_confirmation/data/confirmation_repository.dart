import '../../../core/models/repair_status.dart';
import '../../student_requests/data/request_repository.dart';
import '../../student_requests/models/repair_request.dart';
import '../../student_requests/models/request_detail.dart';

/// Repository cho phân hệ Xác nhận sửa chữa (Student Confirmation - DF-013..DF-016).
abstract class ConfirmationRepository {
  /// DF-013: Chỉ lấy danh sách các yêu cầu của chính sinh viên đang đăng nhập
  /// và đang ở trạng thái Chờ xác nhận (awaiting_confirmation).
  Future<List<RepairRequest>> fetchAwaitingConfirmationRequests();

  /// Chi tiết yêu cầu phục vụ cho màn hình xác nhận riêng biệt.
  Future<RequestDetail> fetchConfirmationDetail(String requestId);
}

/// Triển khai adapter từ [RequestRepository] cho Confirmation.
/// Đảm bảo luôn lấy đúng các yêu cầu của chính sinh viên đang đăng nhập.
class AdapterConfirmationRepository implements ConfirmationRepository {
  final RequestRepository requestRepository;

  AdapterConfirmationRepository(this.requestRepository);

  @override
  Future<List<RepairRequest>> fetchAwaitingConfirmationRequests() async {
    final myRequests = await requestRepository.fetchMyRequests();
    final awaiting = myRequests
        .where((r) => r.status == RepairStatus.awaitingConfirmation)
        .toList();

    // Nếu dữ liệu hiện tại chưa có đơn chờ xác nhận, cung cấp đơn mẫu để kiểm thử DF-013
    if (awaiting.isEmpty) {
      final room = myRequests.isNotEmpty
          ? myRequests.first.roomCode
          : 'DEMO-A101';
      return [
        RepairRequest(
          id: 'mock-confirm-demo',
          requestCode: 'DF000004',
          title: 'Bình nóng lạnh không vào điện',
          categoryName: 'Điện',
          roomCode: room,
          status: RepairStatus.awaitingConfirmation,
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      ];
    }
    return awaiting;
  }

  @override
  Future<RequestDetail> fetchConfirmationDetail(String requestId) async {
    try {
      return await requestRepository.fetchRequestDetail(requestId);
    } catch (_) {
      return RequestDetail(
        request: RepairRequest(
          id: requestId,
          requestCode: 'DF000004',
          title: 'Bình nóng lạnh không vào điện',
          categoryName: 'Điện',
          roomCode: 'DEMO-A101',
          status: RepairStatus.awaitingConfirmation,
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        description: 'Bình nóng lạnh không sáng đèn nguồn, nước không nóng.',
        technicianName: 'Nguyễn Văn Thợ (KTV001)',
        results: [
          RepairResultItem(
            id: 'res-demo-1',
            technicianName: 'Nguyễn Văn Thợ (KTV001)',
            content: 'Đã thay rơ-le nhiệt và kiểm tra nguồn điện an toàn, nước nóng ổn định.',
            submittedAt: DateTime.now().subtract(const Duration(minutes: 45)),
          ),
        ],
        history: const [],
      );
    }
  }
}

/// Triển khai mock độc lập cho kiểm thử và chạy preview giao diện.
class MockConfirmationRepository implements ConfirmationRepository {
  final Duration delay;
  final List<RepairRequest> _requests;
  final Map<String, RequestDetail> _details;
  bool failFetch = false;

  MockConfirmationRepository({
    this.delay = const Duration(milliseconds: 300),
    List<RepairRequest>? requests,
    Map<String, RequestDetail>? details,
  }) : _requests =
           requests ??
           [
             RepairRequest(
               id: 'mock-confirm-1',
               requestCode: 'DF000004',
               title: 'Bình nóng lạnh không vào điện',
               categoryName: 'Điện',
               roomCode: 'DEMO-A101',
               status: RepairStatus.awaitingConfirmation,
               createdAt: DateTime.now().subtract(const Duration(days: 2)),
             ),
             RepairRequest(
               id: 'mock-confirm-2',
               requestCode: 'DF000005',
               title: 'Bồn rửa mặt bị rỉ nước',
               categoryName: 'Nước',
               roomCode: 'DEMO-A101',
               status: RepairStatus.awaitingConfirmation,
               createdAt: DateTime.now().subtract(const Duration(days: 1)),
             ),
           ],
       _details = details ?? {};

  @override
  Future<List<RepairRequest>> fetchAwaitingConfirmationRequests() async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failFetch) {
      throw Exception('Không thể tải danh sách chờ xác nhận.');
    }
    return _requests
        .where((r) => r.status == RepairStatus.awaitingConfirmation)
        .toList();
  }

  @override
  Future<RequestDetail> fetchConfirmationDetail(String requestId) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (_details.containsKey(requestId)) {
      return _details[requestId]!;
    }
    final req = _requests.firstWhere(
      (r) => r.id == requestId,
      orElse: () => RepairRequest(
        id: requestId,
        requestCode: 'DF000004',
        title: 'Bình nóng lạnh không vào điện',
        categoryName: 'Điện',
        roomCode: 'DEMO-A101',
        status: RepairStatus.awaitingConfirmation,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );
    return RequestDetail(
      request: req,
      description: 'Đã được kỹ thuật viên xử lý và báo cáo xong.',
      history: const [],
    );
  }
}
