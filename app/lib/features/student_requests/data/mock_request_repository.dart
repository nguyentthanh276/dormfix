import '../../../../core/models/repair_status.dart';
import '../models/edit_repair_request.dart';
import '../models/history_entry.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/repair_request.dart';
import '../models/request_detail.dart';
import 'request_repository.dart';

/// Triển khai mock cho cụm 2 (Sinh viên gửi & theo dõi yêu cầu).
///
/// Dùng để dựng UI / unit test / demo khi backend chưa có RPC tạo/sửa/hủy và Storage ảnh.
/// Dữ liệu lưu trong bộ nhớ; mất khi tắt app.
class MockRequestRepository extends RequestRepository {
  MockRequestRepository({
    String? roomCode,
    this.studentId = 'mock-student',
    this.studentName = 'Sinh viên demo',
    this.delay = const Duration(milliseconds: 300),
  }) : roomCode = roomCode ?? 'DEMO-A101';

  /// Khởi tạo repo có sẵn 1 yêu cầu pending ('mock-3') phục vụ test và demo DF-011.
  factory MockRequestRepository.withSamplePending({
    String? roomCode,
    String studentId = 'mock-student',
    String studentName = 'Sinh viên demo',
    Duration delay = Duration.zero,
  }) {
    final repo = MockRequestRepository(
      roomCode: roomCode,
      studentId: studentId,
      studentName: studentName,
      delay: delay,
    );
    repo._requests.insert(
      0,
      repo._sample(
        3,
        'Cửa sổ bị kẹt chốt',
        'Nội thất',
        RepairStatus.pending,
        1,
      ),
    );
    repo._customDescriptions['mock-3'] = 'Chốt cửa bị gỉ sét không đóng được';
    repo._nextNumber = 4;
    return repo;
  }

  final String roomCode;
  final String studentId;
  final String studentName;
  final Duration delay;

  bool failFetch = false;
  bool failCreate = false;
  bool failUpdate = false;

  static const _categories = [
    IncidentCategory(id: 'cat-dien', name: 'Điện'),
    IncidentCategory(id: 'cat-nuoc', name: 'Nước'),
    IncidentCategory(id: 'cat-noithat', name: 'Nội thất'),
    IncidentCategory(id: 'cat-khac', name: 'Khác'),
  ];

  late final List<RepairRequest> _requests = [
    _sample(2, 'Vòi nước rò rỉ', 'Nước', RepairStatus.assigned, 3),
    // Yêu cầu cũ gửi từ phòng trước khi chuyển phòng: vẫn hiển thị, giữ phòng cũ.
    _sample(
      1,
      'Bóng đèn phòng bị cháy',
      'Điện',
      RepairStatus.completed,
      7,
      room: 'OLD-B202',
    ),
  ];
  int _nextNumber = 3;

  // Lưu mô tả và ảnh cho các yêu cầu mới tạo hoặc tùy chỉnh
  final Map<String, String> _customDescriptions = {};
  final Map<String, List<String>> _customPhotos = {};
  final Map<String, List<HistoryEntry>> _customHistories = {};

  @override
  Future<List<RepairRequest>> fetchMyRequests() async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failFetch) throw Exception('Mock: lỗi tải danh sách');
    return List.of(_requests);
  }

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failFetch) throw Exception('Mock: lỗi tải chi tiết');
    final r = _requests.firstWhere((e) => e.id == requestId);
    final at = r.createdAt;

    final history = _historyFor(r);
    final assigned = history.any(
      (entry) => entry.status == RepairStatus.assigned,
    );

    // Dữ liệu kết quả sửa chữa (DF-026 / DF-010)
    final hasResult =
        r.status == RepairStatus.awaitingConfirmation ||
        r.status == RepairStatus.completed;

    final results = hasResult
        ? [
            RepairResultItem(
              id: 'result-${r.id}',
              technicianName: 'Lê Văn Cường',
              content: r.status == RepairStatus.completed
                  ? 'Đã thay mới bóng đèn LED 18W và chấn lưu, kiểm tra độ sáng đạt chuẩn.'
                  : 'Đã thay ron cao su và khóa van tổng, không còn rò rỉ nước.',
              submittedAt: at.add(const Duration(hours: 20)),
              photos: const ['anh_nghiem_thu_sua_chua.jpg'],
            ),
          ]
        : const <RepairResultItem>[];

    // Dữ liệu ảnh sinh viên gửi kèm (DF-007 / DF-010)
    final studentPhotos =
        _customPhotos[r.id] ??
        (r.id == 'mock-2'
            ? const ['anh_voi_nuoc_ro_ri_1.jpg', 'anh_voi_nuoc_ro_ri_2.jpg']
            : (r.id == 'mock-1' ? const ['anh_bong_den_chay.jpg'] : const []));

    final description =
        _customDescriptions[r.id] ??
        'Mô tả mẫu (mock) cho yêu cầu "${r.title}".';

    return RequestDetail(
      request: r,
      description: description,
      history: history,
      technicianName: assigned ? 'Lê Văn Cường' : null,
      technicianPhone: assigned ? '0987 111 222' : null,
      studentPhotos: studentPhotos,
      results: results,
    );
  }

  @override
  Future<List<IncidentCategory>> fetchCategories() async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return _categories;
  }

  @override
  Future<RepairRequest> createRequest(NewRepairRequest request) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failCreate) throw Exception('Mock: lỗi tạo yêu cầu');
    final category = _categories.firstWhere((c) => c.id == request.categoryId);
    final created = RepairRequest(
      id: 'mock-$_nextNumber',
      requestCode: _code(_nextNumber),
      title: request.title,
      categoryName: category.name,
      roomCode: roomCode,
      status: RepairStatus.pending, // yêu cầu mới luôn ở Chờ tiếp nhận
      createdAt: DateTime.now(),
    );
    _customDescriptions[created.id] = request.description;
    _customPhotos[created.id] = request.attachments.map((a) => a.name).toList();
    _nextNumber++;
    _requests.insert(0, created); // mới nhất lên đầu
    return created;
  }

  @override
  Future<void> updateRequest(EditRepairRequest request) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    if (failUpdate) throw Exception('Mock: lỗi cập nhật yêu cầu');

    final index = _requests.indexWhere((e) => e.id == request.requestId);
    if (index < 0) throw Exception('Yêu cầu không tồn tại');

    final current = _requests[index];
    // Kiểm tra trạng thái: chỉ cho sửa khi đang ở pending
    if (current.status != RepairStatus.pending) {
      throw Exception(
        'Chỉ có thể chỉnh sửa yêu cầu khi đang ở trạng thái Chờ tiếp nhận.',
      );
    }

    final category = _categories.firstWhere((c) => c.id == request.categoryId);

    // Cập nhật lại yêu cầu
    final updated = RepairRequest(
      id: current.id,
      requestCode: current.requestCode,
      title: request.title,
      categoryName: category.name,
      roomCode: current.roomCode,
      status: current.status,
      createdAt: current.createdAt,
    );
    _requests[index] = updated;

    // Cập nhật mô tả
    _customDescriptions[current.id] = request.description;

    // Cập nhật ảnh: ảnh cũ giữ lại + ảnh mới
    final combinedPhotos = [
      ...request.keepPhotos,
      ...request.newAttachments.map((a) => a.name),
    ];
    _customPhotos[current.id] = combinedPhotos;

    // Ghi lịch sử chỉnh sửa
    final currentHistory = List<HistoryEntry>.from(_historyFor(current));
    currentHistory.add(
      HistoryEntry(
        status: RepairStatus.pending,
        note: 'Sinh viên chỉnh sửa thông tin yêu cầu',
        createdAt: DateTime.now(),
        actorId: studentId,
        actorName: studentName,
      ),
    );
    _customHistories[current.id] = currentHistory;
  }

  @override
  Future<void> cancelRequest({
    required String requestId,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) throw Exception('Vui lòng nhập lý do');
    if (delay > Duration.zero) await Future.delayed(delay);

    final index = _requests.indexWhere((e) => e.id == requestId);
    if (index < 0) throw Exception('Yêu cầu không tồn tại');

    final current = _requests[index];
    // Chỉ hủy được khi pending hoặc assigned
    if (current.status != RepairStatus.pending &&
        current.status != RepairStatus.assigned) {
      throw Exception(
        'Chỉ có thể hủy yêu cầu khi đang ở trạng thái '
        'Chờ tiếp nhận hoặc Đã phân công.',
      );
    }

    final currentHistory = List<HistoryEntry>.from(_historyFor(current));

    // Cập nhật trạng thái → cancelled
    _requests[index] = RepairRequest(
      id: current.id,
      requestCode: current.requestCode,
      title: current.title,
      categoryName: current.categoryName,
      roomCode: current.roomCode,
      status: RepairStatus.cancelled,
      createdAt: current.createdAt,
    );

    // Ghi lịch sử hủy
    currentHistory.add(
      HistoryEntry(
        status: RepairStatus.cancelled,
        note: 'Sinh viên hủy yêu cầu: $trimmedReason',
        createdAt: DateTime.now(),
        actorId: studentId,
        actorName: studentName,
      ),
    );
    _customHistories[current.id] = currentHistory;
  }

  List<HistoryEntry> _historyFor(RepairRequest r) {
    final at = r.createdAt;
    return _customHistories[r.id] ??
        [
          HistoryEntry(
            status: RepairStatus.pending,
            note: 'Sinh viên gửi yêu cầu',
            createdAt: at,
            actorId: studentId,
            actorName: studentName,
          ),
          if (r.status != RepairStatus.pending)
            HistoryEntry(
              status: RepairStatus.assigned,
              note: 'Phân công cho Lê Văn Cường',
              createdAt: at.add(const Duration(hours: 2)),
            ),
          if (r.status == RepairStatus.inProgress ||
              r.status == RepairStatus.awaitingConfirmation ||
              r.status == RepairStatus.completed)
            HistoryEntry(
              status: RepairStatus.inProgress,
              note: 'Kỹ thuật viên bắt đầu xử lý',
              createdAt: at.add(const Duration(hours: 10)),
            ),
          if (r.status == RepairStatus.awaitingConfirmation ||
              r.status == RepairStatus.completed)
            HistoryEntry(
              status: RepairStatus.awaitingConfirmation,
              note: 'Báo cáo kết quả sửa chữa',
              createdAt: at.add(const Duration(hours: 20)),
            ),
          if (r.status == RepairStatus.completed)
            HistoryEntry(
              status: RepairStatus.completed,
              note: 'Đã hoàn tất xử lý sự cố',
              createdAt: at.add(const Duration(hours: 24)),
            ),
        ];
  }

  String _code(int n) => 'DF${n.toString().padLeft(6, '0')}';

  RepairRequest _sample(
    int n,
    String title,
    String category,
    RepairStatus status,
    int daysAgo, {
    String? room,
  }) => RepairRequest(
    id: 'mock-$n',
    requestCode: _code(n),
    title: title,
    categoryName: category,
    roomCode: room ?? roomCode,
    status: status,
    createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
  );
}
