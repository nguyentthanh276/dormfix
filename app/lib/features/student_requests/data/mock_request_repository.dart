import '../../../core/models/repair_status.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/repair_request.dart';
import 'request_repository.dart';

/// Dữ liệu MOCK trong bộ nhớ (mất khi tắt app), dùng tạm vì backend chưa có API.
class MockRequestRepository implements RequestRepository {
  MockRequestRepository({
    required String? roomCode,
    this.delay = const Duration(milliseconds: 600),
  }) : roomCode = roomCode ?? 'Chưa có phòng';

  final String roomCode;
  final Duration delay; // giả lập chờ mạng; test truyền Duration.zero

  // Công tắc để test các đường lỗi (báo lỗi, nút Thử lại, gửi thất bại).
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

  @override
  Future<List<RepairRequest>> fetchMyRequests() async {
    await Future.delayed(delay);
    if (failFetch) throw Exception('Mock: lỗi tải danh sách');
    return List.of(_requests);
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
