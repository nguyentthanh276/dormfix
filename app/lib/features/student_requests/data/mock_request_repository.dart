import '../../../../core/models/repair_status.dart';
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
class MockRequestRepository implements RequestRepository {
  MockRequestRepository({
    String? roomCode,
    this.delay = const Duration(milliseconds: 300),
  }) : roomCode = roomCode ?? 'DEMO-A101';

  final String roomCode;
  final Duration delay;

  bool failFetch = false;
  bool failCreate = false;

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

  @override
  Future<List<RepairRequest>> fetchMyRequests() async {
    await Future.delayed(delay);
    if (failFetch) throw Exception('Mock: lỗi tải danh sách');
    return List.of(_requests);
  }

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) async {
    await Future.delayed(delay);
    if (failFetch) throw Exception('Mock: lỗi tải chi tiết');
    final r = _requests.firstWhere((e) => e.id == requestId);
    final at = r.createdAt;

    final history = [
      HistoryEntry(
        status: RepairStatus.pending,
        note: 'Sinh viên gửi yêu cầu',
        createdAt: at,
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
    final assigned = r.status != RepairStatus.pending;

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
    await Future.delayed(delay);
    return _categories;
  }

  @override
  Future<RepairRequest> createRequest(NewRepairRequest request) async {
    await Future.delayed(delay);
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
