import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/features/student_confirmation/data/confirmation_repository.dart';
import 'package:dormfix/features/student_confirmation/presentation/awaiting_confirmation_screen.dart';
import 'package:dormfix/features/student_requests/data/request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/history_entry.dart';
import 'package:dormfix/features/student_requests/models/incident_category.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_detail.dart';
import 'package:dormfix/features/student_requests/presentation/create_request_screen.dart';
import 'package:dormfix/features/student_requests/presentation/my_requests_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:dormfix/features/student_requests/presentation/widgets/request_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _date = DateTime.utc(2026, 11, 10, 1);
const _requestId = '11111111-1111-4111-8111-111111111111';
const _attachment = RequestAttachment(
  id: 'photo-1',
  storagePath: 'student-requests/student/$_requestId/photo.png',
  mimeType: 'image/png',
  sizeBytes: 70,
);
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aB1sAAAAASUVORK5CYII=',
);

RepairRequest _request([RepairStatus status = RepairStatus.pending]) =>
    RepairRequest(
      id: _requestId,
      requestCode: 'DF000123',
      title: 'Yêu cầu thật của tôi',
      categoryName: 'Điện',
      roomCode: 'A101',
      status: status,
      createdAt: _date,
    );

class _LiveRepository extends RequestRepository {
  final access = StreamController<void>.broadcast(sync: true);
  List<RepairRequest> requests = [_request()];
  List<NewRepairRequest> attempts = [];
  bool firstCreateUncertain = false;
  bool hasPhoto = false;
  bool denyDetail = false;
  bool denyPhoto = false;
  Completer<Uint8List>? pendingPhoto;

  @override
  bool get supportsEditing => false;
  @override
  bool get supportsCancellation => false;
  @override
  bool get supportsConfirmationActions => false;
  @override
  bool get allowsDemoFallback => false;
  @override
  Stream<void> get accessChanges => access.stream;
  @override
  Future<List<RepairRequest>> fetchMyRequests() async => requests;
  @override
  Future<List<IncidentCategory>> fetchCategories() async => const [
    IncidentCategory(id: 'category', name: 'Điện'),
  ];
  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) async {
    if (denyDetail) {
      throw const RequestFailure('Không có quyền.', accessDenied: true);
    }
    return RequestDetail(
      request: requests.first,
      description: 'Mô tả thật',
      history: [
        HistoryEntry(
          status: RepairStatus.pending,
          note: 'Đã tạo trên database',
          createdAt: _date,
        ),
      ],
      attachments: hasPhoto ? [_attachment] : [],
      studentPhotos: hasPhoto ? [_attachment.storagePath] : [],
      results: [
        RepairResultItem(
          id: 'result-1',
          technicianName: 'Kỹ thuật viên có họ tên dài để kiểm tra xuống dòng',
          content: 'Kết quả sửa chữa thật',
          submittedAt: _date,
        ),
      ],
      feedback: [
        RequestFeedbackItem(
          id: 'feedback-1',
          kind: 'rework',
          reason: 'Phản hồi vòng trước được giữ nguyên',
          createdAt: _date,
          authorName: 'Sinh viên',
        ),
      ],
    );
  }

  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    RequestAttachment attachment,
  ) async {
    if (denyPhoto) {
      throw const RequestFailure('Access revoked', accessDenied: true);
    }
    return pendingPhoto?.future ?? _png;
  }

  @override
  Future<RepairRequest> createRequest(NewRepairRequest request) async {
    attempts.add(request);
    if (firstCreateUncertain && attempts.length == 1) {
      throw const RequestFailure('Transport response lost', uncertain: true);
    }
    return _request();
  }

  @override
  Future<void> updateRequest(EditRepairRequest request) async =>
      throw StateError('Not enabled');
  @override
  Future<void> cancelRequest({
    required String requestId,
    required String reason,
  }) async => throw StateError('Not enabled');
}

void main() {
  testWidgets('live pending detail hides unsupported edit and cancel actions', (
    tester,
  ) async {
    final repo = _LiveRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RequestDetailScreen(repository: repo, requestId: _requestId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mô tả thật'), findsOneWidget);
    expect(find.byTooltip('Chỉnh sửa yêu cầu'), findsNothing);
    expect(find.byTooltip('Hủy yêu cầu'), findsNothing);
    expect(find.text('Chỉnh sửa yêu cầu này'), findsNothing);
    expect(find.text('Hủy yêu cầu này'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.access.close();
  });

  testWidgets('photo authorization failure closes viewer and discards detail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _LiveRepository()..hasPhoto = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RequestDetailScreen(repository: repo, requestId: _requestId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(RequestPhoto),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    repo.denyPhoto = true;
    await tester.tap(find.byType(RequestPhoto));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Ảnh đính kèm'), findsNothing);
    expect(find.textContaining('không còn quyền'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.access.close();
  });

  test('real confirmation adapter never fabricates an empty inbox or missing detail', () async {
    final repo = _LiveRepository()..requests = [];
    final adapter = AdapterConfirmationRepository(repo);
    expect(await adapter.fetchAwaitingConfirmationRequests(), isEmpty);
    repo.denyDetail = true;
    await expectLater(
      adapter.fetchConfirmationDetail('foreign'),
      throwsA(isA<RequestFailure>()),
    );
    await repo.access.close();
  });

  testWidgets(
    'uncertain create freezes fields and retries the exact same request object and ID',
    (tester) async {
      final repo = _LiveRepository()..firstCreateUncertain = true;
      var created = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CreateRequestScreen(
            repository: repo,
            roomCode: 'A101',
            onCreated: () => created++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Điện'));
      await tester.enterText(find.byKey(const Key('titleField')), 'Đèn hỏng');
      await tester.enterText(find.byKey(const Key('descField')), 'Không sáng');
      await tester.ensureVisible(
        find.byKey(const Key('create-request-submit')),
      );
      await tester.tap(find.byKey(const Key('create-request-submit')));
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(repo.attempts, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('titleField')))
            .enabled,
        isFalse,
      );
      expect(find.text('Kiểm tra lại yêu cầu'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('create-request-submit')),
      );
      await tester.tap(find.byKey(const Key('create-request-submit')));
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(repo.attempts, hasLength(2));
      expect(identical(repo.attempts[0], repo.attempts[1]), isTrue);
      expect(
        repo.attempts.first.requestId,
        matches(RegExp(r'^[a-f0-9-]{36}$')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.access.close();
    },
  );

  for (final awaitingTab in [false, true]) {
    testWidgets(
      'live ${awaitingTab ? 'awaiting tab' : 'request list'} opens readonly detail with real results',
      (tester) async {
        final repo = _LiveRepository()
          ..requests = [_request(RepairStatus.awaitingConfirmation)];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: awaitingTab
                ? AwaitingConfirmationScreen(
                    repository: AdapterConfirmationRepository(repo),
                    requestRepository: repo,
                  )
                : MyRequestsScreen(repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yêu cầu thật của tôi'));
        await tester.pumpAndSettle();
        expect(find.byType(RequestDetailScreen), findsOneWidget);
        expect(find.text('Xác nhận hoàn tất'), findsNothing);
        expect(find.byTooltip('Chỉnh sửa yêu cầu'), findsNothing);
        expect(find.byTooltip('Hủy yêu cầu'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Kết quả sửa chữa thật'),
          180,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Kết quả sửa chữa thật'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await repo.access.close();
      },
    );
  }

  testWidgets(
    'private viewer and underlying detail clear on identity invalidation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _LiveRepository()..hasPhoto = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RequestDetailScreen(repository: repo, requestId: _requestId),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(RequestPhoto),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RequestPhoto));
      await tester.pumpAndSettle();
      expect(find.text('Ảnh đính kèm'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      repo.access.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(RequestPhoto), findsNothing);
      expect(find.textContaining('không còn quyền'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.access.close();
    },
  );

  testWidgets('late photo bytes cannot restore an invalidated detail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _LiveRepository()
      ..hasPhoto = true
      ..pendingPhoto = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RequestDetailScreen(repository: repo, requestId: _requestId),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byType(RequestPhoto),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    repo.access.add(null);
    await tester.pump();
    repo.pendingPhoto!.complete(_png);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('không còn quyền'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await repo.access.close();
  });
}
