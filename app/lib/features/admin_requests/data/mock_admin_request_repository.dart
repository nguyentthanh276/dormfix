import 'dart:convert';
import 'dart:typed_data';

import '../../../core/models/repair_status.dart';
import '../models/admin_request.dart';
import 'admin_request_repository.dart';

/// DF-043/044: local UI/test fixtures only; never writes shared Supabase data.
class MockAdminRequestRepository implements AdminRequestRepository {
  const MockAdminRequestRepository();

  static final _requests = <AdminRequestSummary>[
    AdminRequestSummary(
      id: 'demo-1',
      requestCode: 'DF000101',
      title: 'Bóng đèn phòng bị cháy',
      roomCode: 'DEMO-A101',
      categoryName: 'Điện',
      studentName: 'Nguyễn An',
      technicianName: null,
      status: RepairStatus.pending,
      createdAt: DateTime.utc(2026, 10, 27, 3),
      updatedAt: DateTime.utc(2026, 10, 27, 3),
    ),
    AdminRequestSummary(
      id: 'demo-2',
      requestCode: 'DF000102',
      title: 'Vòi nước rò rỉ',
      roomCode: 'DEMO-A101',
      categoryName: 'Nước',
      studentName: 'Trần Bình',
      technicianName: 'Lê Cường',
      status: RepairStatus.assigned,
      createdAt: DateTime.utc(2026, 10, 26, 3),
      updatedAt: DateTime.utc(2026, 10, 26, 5),
    ),
    AdminRequestSummary(
      id: 'demo-3',
      requestCode: 'DF000103',
      title: 'Cửa sổ kẹt chốt',
      roomCode: 'DEMO-B202',
      categoryName: 'Nội thất',
      studentName: 'Lê Dung',
      technicianName: 'Lê Cường',
      status: RepairStatus.inProgress,
      createdAt: DateTime.utc(2026, 10, 25, 3),
      updatedAt: DateTime.utc(2026, 10, 25, 10),
    ),
    AdminRequestSummary(
      id: 'demo-4',
      requestCode: 'DF000104',
      title: 'Ổ cắm phát tia lửa',
      roomCode: 'DEMO-A102',
      categoryName: 'Điện',
      studentName: 'Phạm Hà',
      technicianName: 'Võ Long',
      status: RepairStatus.awaitingConfirmation,
      createdAt: DateTime.utc(2026, 10, 24, 3),
      updatedAt: DateTime.utc(2026, 10, 25, 3),
    ),
    AdminRequestSummary(
      id: 'demo-5',
      requestCode: 'DF000105',
      title: 'Tủ quần áo lệch cánh',
      roomCode: 'DEMO-C301',
      categoryName: 'Nội thất',
      studentName: 'Đặng Hoa',
      technicianName: 'Võ Long',
      status: RepairStatus.awaitingRework,
      createdAt: DateTime.utc(2026, 10, 23, 3),
      updatedAt: DateTime.utc(2026, 10, 24, 3),
    ),
    AdminRequestSummary(
      id: 'demo-6',
      requestCode: 'DF000106',
      title: 'Vòi sen không có nước nóng',
      roomCode: 'DEMO-A103',
      categoryName: 'Nước',
      studentName: 'Bùi Khôi',
      technicianName: 'Lê Cường',
      status: RepairStatus.completed,
      createdAt: DateTime.utc(2026, 10, 22, 3),
      updatedAt: DateTime.utc(2026, 10, 23, 3),
    ),
    AdminRequestSummary(
      id: 'demo-7',
      requestCode: 'DF000107',
      title: 'Quạt trần rung mạnh',
      roomCode: 'DEMO-B203',
      categoryName: 'Điện',
      studentName: 'Vũ Lan',
      technicianName: null,
      status: RepairStatus.rejected,
      createdAt: DateTime.utc(2026, 10, 21, 3),
      updatedAt: DateTime.utc(2026, 10, 21, 4),
    ),
    AdminRequestSummary(
      id: 'demo-8',
      requestCode: 'DF000108',
      title: 'Bản lề cửa bị lỏng',
      roomCode: 'DEMO-C302',
      categoryName: 'Nội thất',
      studentName: 'Mai Minh',
      technicianName: null,
      status: RepairStatus.cancelled,
      createdAt: DateTime.utc(2026, 10, 20, 3),
      updatedAt: DateTime.utc(2026, 10, 20, 5),
    ),
  ];

  @override
  Future<AdminRequestFilterOptions> fetchFilterOptions() async =>
      const AdminRequestFilterOptions(
        rooms: [
          AdminRequestOption(
            id: 'room-a101',
            label: 'DEMO-A101',
            subtitle: 'Tòa demo',
          ),
          AdminRequestOption(
            id: 'room-a102',
            label: 'DEMO-A102',
            subtitle: 'Tòa demo',
          ),
          AdminRequestOption(
            id: 'room-b202',
            label: 'DEMO-B202',
            subtitle: 'Tòa B',
          ),
        ],
        categories: [
          AdminRequestOption(id: 'category-electric', label: 'Điện'),
          AdminRequestOption(id: 'category-water', label: 'Nước'),
          AdminRequestOption(id: 'category-furniture', label: 'Nội thất'),
        ],
        technicians: [
          AdminRequestOption(id: 'tech-active', label: 'Lê Cường'),
          AdminRequestOption(id: 'tech-locked', label: 'Võ Long'),
        ],
      );

  @override
  Future<List<AdminRequestOption>> fetchActiveTechnicians() async => const [
    AdminRequestOption(id: 'tech-active', label: 'Lê Cường'),
    AdminRequestOption(id: 'tech-first-login', label: 'Trần Minh'),
  ];

  @override
  Future<void> assignRequest(String requestId, String technicianId) async {}

  @override
  Future<void> rejectRequest(String requestId, String reason) async {}

  @override
  Future<void> transferRequest(
    String requestId,
    String technicianId,
    String reason,
  ) async {}

  @override
  Future<void> confirmForRevokedStudent(String requestId, String note) async {}

  @override
  Future<void> requestReworkForRevokedStudent(
    String requestId,
    String reason,
  ) async {}

  @override
  Future<List<AdminRequestSummary>> fetchRequests({
    required AdminRequestFilters filters,
    required int offset,
    required int limit,
  }) async {
    final filtered = _requests.where((request) {
      final roomMatches =
          filters.roomId == null ||
          (filters.roomId == 'room-a101' && request.roomCode == 'DEMO-A101') ||
          (filters.roomId == 'room-a102' && request.roomCode == 'DEMO-A102') ||
          (filters.roomId == 'room-b202' && request.roomCode == 'DEMO-B202');
      final categoryMatches =
          filters.categoryId == null ||
          (filters.categoryId == 'category-electric' &&
              request.categoryName == 'Điện') ||
          (filters.categoryId == 'category-water' &&
              request.categoryName == 'Nước') ||
          (filters.categoryId == 'category-furniture' &&
              request.categoryName == 'Nội thất');
      final technicianMatches =
          filters.technicianId == null ||
          (filters.technicianId == 'tech-active' &&
              request.technicianName == 'Lê Cường') ||
          (filters.technicianId == 'tech-locked' &&
              request.technicianName == 'Võ Long');
      final date = filters.dateField == AdminRequestDateField.createdAt
          ? request.createdAt
          : request.updatedAt;
      final dateMatches =
          !filters.hasDateRange ||
          (!date.isBefore(filters.from!) &&
              date.isBefore(filters.toExclusive!));
      return (filters.status == null || request.status == filters.status) &&
          roomMatches &&
          categoryMatches &&
          technicianMatches &&
          dateMatches;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<AdminRequestDetail> fetchRequestDetail(String requestId) async {
    final request = _requests.firstWhere((item) => item.id == requestId);
    final hasHistory = request.status != RepairStatus.pending;
    return AdminRequestDetail.fromJson({
      'request': {
        'id': request.id,
        'request_code': request.requestCode,
        'title': request.title,
        'description': 'Dữ liệu minh họa để kiểm tra màn hình chi tiết.',
        'room_code': request.roomCode,
        'building': 'Tòa demo',
        'category_name': request.categoryName,
        'status': request.status.databaseValue,
        'created_at': request.createdAt.toIso8601String(),
        'updated_at': request.updatedAt.toIso8601String(),
      },
      'student': {
        'full_name': request.studentName,
        'status': request.id == 'demo-4' || request.id == 'demo-5'
            ? 'revoked'
            : request.id == 'demo-3'
            ? 'locked'
            : 'active',
      },
      'technician': request.technicianName == null
          ? null
          : {
              'id': request.technicianName == 'VĂµ Long'
                  ? 'tech-locked'
                  : 'tech-active',
              'full_name': request.technicianName,
            },
      'attachments': [
        {
          'id': 'attachment-${request.id}',
          'request_id': request.id,
          'storage_path': 'mock/${request.id}.png',
          'mime_type': 'image/png',
          'size_bytes': 68,
          'result_id': null,
          'feedback_id': null,
          'uploaded_by': 'mock-student',
          'created_at': request.createdAt.toIso8601String(),
        },
      ],
      'results': [
        if (request.status == RepairStatus.awaitingConfirmation ||
            request.status == RepairStatus.awaitingRework ||
            request.status == RepairStatus.completed)
          {
            'id': 'result-${request.id}',
            'content': 'Đã kiểm tra và xử lý sự cố minh họa.',
            'submitted_at': request.updatedAt.toIso8601String(),
            'technician_name': request.technicianName ?? 'Kỹ thuật viên mẫu',
          },
      ],
      'feedback': [
        if (request.status == RepairStatus.awaitingRework)
          {
            'id': 'feedback-${request.id}',
            'kind': 'rework',
            'reason': 'Ảnh minh họa cần được kiểm tra lại.',
            'created_at': request.updatedAt.toIso8601String(),
            'author_name': 'Sinh viên mẫu',
          },
      ],
      'history': [
        {
          'id': 'history-created-${request.id}',
          'action': 'created',
          'actor_name': request.studentName,
          'old_status': null,
          'new_status': 'pending',
          'note': 'Sinh viên gửi yêu cầu.',
          'occurred_at': request.createdAt.toIso8601String(),
        },
        if (hasHistory)
          {
            'id': 'history-current-${request.id}',
            'action': 'status_changed',
            'actor_name': request.technicianName ?? 'Quản trị viên',
            'old_status': 'pending',
            'new_status': request.status.databaseValue,
            'note': 'Cập nhật trạng thái mẫu.',
            'occurred_at': request.updatedAt.toIso8601String(),
          },
      ],
      'assignments': [
        if (request.technicianName != null)
          {
            'id': 'assignment-${request.id}',
            'technician_id': request.technicianName == 'Võ Long'
                ? 'tech-locked'
                : 'tech-active',
            'technician_name': request.technicianName,
            'assigned_by_name': 'Admin Demo',
            'assigned_at': request.createdAt.toIso8601String(),
            'ended_at': null,
            'transfer_reason': null,
            'end_reason': null,
          },
      ],
    });
  }

  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    Map<String, dynamic> attachment,
  ) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Z0cAAAAASUVORK5CYII=',
  );
}
