import 'dart:async';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/admin_requests/data/admin_request_repository.dart';
import 'package:dormfix/features/admin_requests/data/mock_admin_request_repository.dart';
import 'package:dormfix/features/admin_requests/models/admin_request.dart';
import 'package:dormfix/features/admin_requests/presentation/admin_requests_page.dart';
import 'package:dormfix/features/admin_requests/presentation/admin_request_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-043/044 Admin repair request read/filter', () {
    test('date range includes both Vietnam calendar days', () {
      final filters = AdminRequestFilters.forSaigonDateRange(
        dateField: AdminRequestDateField.createdAt,
        fromDate: DateTime(2026, 10, 26),
        toDate: DateTime(2026, 10, 27),
      );

      expect(filters.from, DateTime.utc(2026, 10, 25, 17));
      expect(filters.toExclusive, DateTime.utc(2026, 10, 27, 17));
      expect(
        () => AdminRequestFilters.forSaigonDateRange(
          dateField: AdminRequestDateField.updatedAt,
          fromDate: DateTime(2026, 10, 28),
          toDate: DateTime(2026, 10, 27),
        ),
        throwsArgumentError,
      );
    });

    test(
      'combines status, room, category, current technician and date with AND',
      () async {
        const repository = MockAdminRequestRepository();
        final filters = AdminRequestFilters.forSaigonDateRange(
          status: RepairStatus.assigned,
          roomId: 'room-a101',
          categoryId: 'category-water',
          technicianId: 'tech-active',
          dateField: AdminRequestDateField.createdAt,
          fromDate: DateTime(2026, 10, 26),
          toDate: DateTime(2026, 10, 26),
        );

        final result = await repository.fetchRequests(
          filters: filters,
          offset: 0,
          limit: 20,
        );

        expect(result.map((request) => request.id), ['demo-2']);
      },
    );

    testWidgets('blocks non-admin without requesting data', (tester) async {
      final repository = _RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestsPage(
            repository: repository,
            isAdmin: false,
            onSignOut: () {},
          ),
        ),
      );

      expect(
        find.text('Bạn không có quyền truy cập màn hình này.'),
        findsOneWidget,
      );
      expect(repository.listCalls, 0);
      expect(repository.optionCalls, 0);
    });

    testWidgets('shows requests and detail history and feedback', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestsPage(
            repository: const MockAdminRequestRepository(),
            isAdmin: true,
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DF000101'), findsOneWidget);
      expect(find.text('DF000108'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('DF000105'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('DF000105'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Mô tả sự cố'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Mô tả sự cố'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Yêu cầu sửa lại'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Yêu cầu sửa lại'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Lịch sử yêu cầu'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Lịch sử yêu cầu'), findsOneWidget);
    });

    testWidgets('shows empty state and retries a failed request load', (
      tester,
    ) async {
      final repository = _RecordingRepository()..failNextList = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestsPage(
            repository: repository,
            isAdmin: true,
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lỗi tải dữ liệu'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Thử lại'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('DF000101'), findsOneWidget);

      repository.returnEmpty = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestsPage(
            key: const ValueKey('empty-state'),
            repository: repository,
            isAdmin: true,
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa có yêu cầu sửa chữa nào.'), findsOneWidget);
    });

    testWidgets('a slower response cannot replace newer combined filters', (
      tester,
    ) async {
      final repository = _RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestsPage(
            repository: repository,
            isAdmin: true,
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final oldResponse = Completer<void>();
      repository.pauseNextList = oldResponse.future;
      await tester.tap(find.byType(DropdownButtonFormField<RepairStatus?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chờ tiếp nhận').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('DEMO-B202').last);
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy yêu cầu phù hợp.'), findsOneWidget);

      oldResponse.complete();
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy yêu cầu phù hợp.'), findsOneWidget);
      expect(find.text('DF000101'), findsNothing);
    });

    testWidgets('refresh removes a filter whose last assignment transferred', (
      tester,
    ) async {
      final repository = _RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestsPage(
            repository: repository,
            isAdmin: true,
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final technician = find
          .widgetWithText(
            DropdownButtonFormField<String?>,
            'Tất cả Kỹ thuật viên',
          )
          .first;
      await tester.tap(technician);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lê Cường').last);
      await tester.pumpAndSettle();
      expect(repository.lastFilters?.technicianId, 'tech-active');

      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      await refresh();
      await tester.pumpAndSettle();
      expect(repository.lastFilters?.technicianId, 'tech-active');

      repository.replacementOptions = const AdminRequestFilterOptions(
        rooms: [],
        categories: [],
        technicians: [
          AdminRequestOption(id: 'tech-first-login', label: 'Trần Minh'),
        ],
      );
      await refresh();
      await tester.pumpAndSettle();
      expect(repository.lastFilters?.technicianId, isNull);
      expect(repository.optionCalls, 3);

      await tester.tap(technician);
      await tester.pumpAndSettle();
      expect(find.text('Trần Minh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('loads requests when filter options fail', (tester) async {
    final repository = _RecordingRepository()..failNextOptions = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminRequestsPage(
          repository: repository,
          isAdmin: true,
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DF000101'), findsOneWidget);
    expect(find.text('Lá»—i táº£i bá»™ lá»c'), findsOneWidget);
    expect(repository.listCalls, 1);
    expect(repository.optionCalls, 1);
  });

  group('DF-045/046/047/048 Admin request actions', () {
    testWidgets('shows only actions allowed by request and student status', (
      tester,
    ) async {
      const repository = MockAdminRequestRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestDetailPage(
            key: const ValueKey('demo-1'),
            repository: repository,
            requestId: 'demo-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Phân công Kỹ thuật viên'), findsOneWidget);
      expect(find.text('Từ chối yêu cầu'), findsOneWidget);
      expect(find.text('Đổi Kỹ thuật viên'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestDetailPage(
            key: const ValueKey('demo-3'),
            repository: repository,
            requestId: 'demo-3',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đổi Kỹ thuật viên'), findsOneWidget);
      expect(find.text('Xác nhận hoàn tất'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestDetailPage(
            key: const ValueKey('demo-4'),
            repository: repository,
            requestId: 'demo-4',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận hoàn tất'), findsOneWidget);
      expect(find.text('Yêu cầu sửa lại'), findsOneWidget);
    });

    testWidgets('requires a reason before opening reject mutation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestDetailPage(
            repository: const MockAdminRequestRepository(),
            requestId: 'demo-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Từ chối yêu cầu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập Lý do từ chối.'), findsOneWidget);
    });

    testWidgets('submits the transfer reason with a small keyboard viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final repository = _RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestDetailPage(
            repository: repository,
            requestId: 'demo-3',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đổi Kỹ thuật viên'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trần Minh').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '  Đổi ca trực  ');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(repository.transferReason, 'Đổi ca trực');
      expect(repository.newTechnicianId, 'tech-first-login');
      expect(tester.takeException(), isNull);
    });

    testWidgets('submits an Admin rework reason after dismissing the dialog', (
      tester,
    ) async {
      final repository = _RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminRequestDetailPage(
            repository: repository,
            requestId: 'demo-4',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yêu cầu sửa lại'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '  Kiểm tra lại  ');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      expect(repository.reworkReason, 'Kiểm tra lại');
      expect(tester.takeException(), isNull);
    });
  });
}

class _RecordingRepository implements AdminRequestRepository {
  final _delegate = const MockAdminRequestRepository();
  int optionCalls = 0;
  int listCalls = 0;
  bool failNextList = false;
  bool failNextOptions = false;
  bool returnEmpty = false;
  Future<void>? pauseNextList;
  AdminRequestFilters? lastFilters;
  AdminRequestFilterOptions? replacementOptions;
  String? transferReason;
  String? newTechnicianId;
  String? reworkReason;

  @override
  Future<List<AdminRequestOption>> fetchActiveTechnicians() =>
      _delegate.fetchActiveTechnicians();

  @override
  Future<void> assignRequest(String requestId, String technicianId) =>
      _delegate.assignRequest(requestId, technicianId);

  @override
  Future<void> rejectRequest(String requestId, String reason) =>
      _delegate.rejectRequest(requestId, reason);

  @override
  Future<void> transferRequest(
    String requestId,
    String technicianId,
    String reason,
  ) async {
    transferReason = reason;
    newTechnicianId = technicianId;
  }

  @override
  Future<void> confirmForRevokedStudent(String requestId, String note) =>
      _delegate.confirmForRevokedStudent(requestId, note);

  @override
  Future<void> requestReworkForRevokedStudent(
    String requestId,
    String reason,
  ) async {
    reworkReason = reason;
  }

  @override
  Future<AdminRequestFilterOptions> fetchFilterOptions() async {
    optionCalls++;
    if (failNextOptions) {
      failNextOptions = false;
      throw const AdminRequestFailure('Lá»—i táº£i bá»™ lá»c');
    }
    return replacementOptions ?? await _delegate.fetchFilterOptions();
  }

  @override
  Future<List<AdminRequestSummary>> fetchRequests({
    required AdminRequestFilters filters,
    required int offset,
    required int limit,
  }) async {
    listCalls++;
    lastFilters = filters;
    final pause = pauseNextList;
    pauseNextList = null;
    if (pause != null) await pause;
    if (failNextList) {
      failNextList = false;
      throw const AdminRequestFailure('Lỗi tải dữ liệu');
    }
    if (returnEmpty) return const [];
    return _delegate.fetchRequests(
      filters: filters,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<AdminRequestDetail> fetchRequestDetail(String requestId) =>
      _delegate.fetchRequestDetail(requestId);

  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    Map<String, dynamic> attachment,
  ) => _delegate.fetchAttachment(requestId, attachment);
}
