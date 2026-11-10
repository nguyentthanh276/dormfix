import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/features/student_confirmation/models/student_confirmation_submission.dart';
import 'package:dormfix/features/student_confirmation/presentation/student_result_action_form.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/data/request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/history_entry.dart';
import 'package:dormfix/features/student_requests/models/incident_category.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_detail.dart';
import 'package:dormfix/features/student_requests/models/student_request_mutation.dart';
import 'package:dormfix/features/student_requests/presentation/edit_request_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'request-id';
const _initialTitle = 'Quạt trong phòng không chạy';
final _date = DateTime.utc(2026, 11, 10);
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aB1sAAAAASUVORK5CYII=',
);
const _photos = [
  RequestAttachment(
    id: 'first-photo',
    storagePath: 'first.png',
    mimeType: 'image/png',
    sizeBytes: 70,
  ),
  RequestAttachment(
    id: 'second-photo',
    storagePath: 'second.png',
    mimeType: 'image/png',
    sizeBytes: 70,
  ),
];

class _LiveRepository extends MockRequestRepository {
  final changes = StreamController<void>.broadcast(sync: true);
  final attempts = <StudentRequestMutation>[];
  RepairStatus status = RepairStatus.pending;
  bool allowEdit = true;
  bool allowCancel = true;
  bool allowReopen = false;
  int version = 7;
  String title = _initialTitle;
  String description = 'Quạt vẫn im dù đã bật công tắc.';
  Future<StudentConfirmationReceipt> Function(StudentRequestMutation)? send;

  @override
  bool get supportsVersionedMutations => true;
  @override
  bool get supportsReopening => true;
  @override
  bool get allowsDemoFallback => false;
  @override
  Stream<void> get accessChanges => changes.stream;

  RequestDetail get detail => RequestDetail(
    request: RepairRequest(
      id: _id,
      requestCode: 'DF000123',
      title: title,
      categoryName: 'Tên cũ của loại Điện',
      roomCode: 'A101',
      status: status,
      createdAt: _date,
      version: version,
    ),
    description: description,
    history: [
      HistoryEntry(
        status: RepairStatus.pending,
        note: 'Đã tạo yêu cầu ban đầu',
        createdAt: _date,
      ),
    ],
    categoryId: 'category-electricity',
    canEdit: allowEdit && status == RepairStatus.pending,
    canCancel:
        allowCancel &&
        (status == RepairStatus.pending || status == RepairStatus.assigned),
    canReopen: allowReopen,
    studentPhotos: _photos.map((p) => p.storagePath).toList(),
    attachments: _photos,
  );

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) async => detail;
  @override
  Future<List<IncidentCategory>> fetchCategories() async => const [
    IncidentCategory(id: 'category-electricity', name: 'Điện'),
  ];
  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    RequestAttachment attachment,
  ) async => _png;
  @override
  Future<void> updateRequest(EditRepairRequest request) async =>
      throw StateError('Legacy edit called');
  @override
  Future<void> cancelRequest({
    required String requestId,
    required String reason,
  }) async => throw StateError('Legacy cancel called');
  @override
  Future<StudentConfirmationReceipt> submitMutation(
    StudentRequestMutation draft,
  ) async {
    attempts.add(draft);
    return send == null ? commit(draft) : send!(draft);
  }

  StudentConfirmationReceipt commit(StudentRequestMutation draft) {
    version++;
    status = draft.kind == StudentRequestMutationKind.cancel
        ? RepairStatus.cancelled
        : RepairStatus.pending;
    if (draft.kind == StudentRequestMutationKind.edit) {
      title = draft.title!;
      description = draft.description!;
    }
    return StudentConfirmationReceipt(
      requestId: _id,
      actionId: draft.actionId,
      status: status,
      version: version,
      replayed: false,
      feedbackId: draft.kind == StudentRequestMutationKind.reopen
          ? draft.actionId
          : null,
    );
  }
}

Future<void> _openDetail(
  WidgetTester tester,
  _LiveRepository repository, {
  VoidCallback? changed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: RequestDetailScreen(
        repository: repository,
        requestId: _id,
        onRequestChanged: changed,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      260,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pending server detail gates edit and cancel even if the repository supports both',
    (tester) async {
      final repo = _LiveRepository()
        ..allowEdit = false
        ..allowCancel = false;
      addTearDown(repo.changes.close);
      await _openDetail(tester, repo);
      expect(find.byTooltip('Chỉnh sửa yêu cầu'), findsNothing);
      expect(find.byTooltip('Hủy yêu cầu'), findsNothing);
      expect(find.byKey(const Key('student-reopen-request')), findsNothing);
    },
  );

  testWidgets(
    'versioned edit preserves server category and kept photo ID through identical retry',
    (tester) async {
      final repo = _LiveRepository();
      addTearDown(repo.changes.close);
      var changed = 0;
      repo.send = (draft) async {
        if (repo.attempts.length == 1) {
          throw const RequestFailure('Lost response', uncertain: true);
        }
        return repo.commit(draft);
      };
      await _openDetail(tester, repo, changed: () => changed++);
      await _tap(tester, find.byTooltip('Chỉnh sửa yêu cầu'));
      expect(find.byType(EditRequestScreen), findsOneWidget);
      expect(find.text('A101'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('student-edit-title')),
        '  Quạt ngừng chạy khi bật  ',
      );
      final remove = find.byKey(
        const ValueKey('student-edit-remove-existing-0'),
      );
      await _scrollTo(tester, remove);
      expect(
        find.byKey(const ValueKey('request-photo-first-photo')),
        findsOneWidget,
      );
      await _tap(tester, remove);
      final save = find.text('Lưu thay đổi');
      await _scrollTo(tester, save);
      await _tap(tester, save);
      expect(changed, 0);
      expect(repo.attempts.single.keepAttachmentIds, ['second-photo']);
      expect(repo.attempts.single.title, 'Quạt ngừng chạy khi bật');
      expect(repo.attempts.single.categoryId, 'category-electricity');
      expect(repo.attempts.single.expectedVersion, 7);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('student-edit-title')))
            .enabled,
        isFalse,
      );
      await _tap(tester, find.text('Kiểm tra lại'));
      expect(identical(repo.attempts.first, repo.attempts.last), isTrue);
      expect(changed, 1);
      expect(find.byType(EditRequestScreen), findsNothing);
      expect(find.text('DF000123'), findsOneWidget);
      expect(find.text('Quạt ngừng chạy khi bật'), findsOneWidget);
    },
  );

  testWidgets(
    'editor previews a new private photo and submits it with the kept attachment IDs',
    (tester) async {
      final repo = _LiveRepository();
      addTearDown(repo.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EditRequestScreen(
                      repository: repo,
                      detail: repo.detail,
                      pickAttachments: () async => [
                        AttachmentDraft(name: 'updated.png', bytes: _png),
                      ],
                    ),
                  ),
                ),
                child: const Text('Mở biểu mẫu'),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('Mở biểu mẫu'));
      final addPhoto = find.byKey(const Key('student-edit-add-photos'));
      await _scrollTo(tester, addPhoto);
      await _tap(tester, addPhoto);
      expect(
        find.byKey(const ValueKey('student-edit-remove-new-0')),
        findsOneWidget,
      );
      final save = find.text('Lưu thay đổi');
      await _scrollTo(tester, save);
      await _tap(tester, save);
      expect(repo.attempts.single.keepAttachmentIds, [
        'first-photo',
        'second-photo',
      ]);
      expect(repo.attempts.single.attachments.single.name, 'updated.png');
      expect(
        repo.attempts.single.attachments.single.bytes,
        orderedEquals(_png),
      );
    },
  );

  testWidgets(
    'assigned cancellation requires a reason and updates detail after receipt',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _LiveRepository()..status = RepairStatus.assigned;
      addTearDown(repo.changes.close);
      var changed = 0;
      await _openDetail(tester, repo, changed: () => changed++);
      expect(find.byTooltip('Chỉnh sửa yêu cầu'), findsNothing);
      await _tap(tester, find.byTooltip('Hủy yêu cầu'));
      final submit = find.byKey(const Key('student-result-submit'));
      await _tap(tester, submit);
      expect(find.text('Vui lòng nhập lý do hủy.'), findsOneWidget);
      expect(repo.attempts, isEmpty);
      expect(find.byKey(const Key('student-result-add-photos')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('student-result-note')),
        '  Thiết bị đã hoạt động lại.  ',
      );
      await _tap(tester, submit);
      expect(repo.attempts.single.kind, StudentRequestMutationKind.cancel);
      expect(repo.attempts.single.reason, 'Thiết bị đã hoạt động lại.');
      expect(find.text('Đã hủy'), findsOneWidget);
      expect(find.byTooltip('Hủy yêu cầu'), findsNothing);
      expect(changed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed detail only shows reopening when current-room capability is granted',
    (tester) async {
      final oldRoom = _LiveRepository()..status = RepairStatus.completed;
      final currentRoom = _LiveRepository()
        ..status = RepairStatus.completed
        ..allowReopen = true;
      addTearDown(oldRoom.changes.close);
      addTearDown(currentRoom.changes.close);
      final reopen = find.byKey(const Key('student-reopen-request'));
      await _openDetail(tester, oldRoom);
      await tester.scrollUntilVisible(find.text('Kết quả sửa chữa'), 200);
      expect(reopen, findsNothing);
      await _openDetail(tester, currentRoom);
      await _scrollTo(tester, reopen);
      await _tap(tester, reopen);
      final submit = find.byKey(const Key('student-result-submit'));
      await _tap(tester, submit);
      expect(find.text('Vui lòng nhập lý do mở lại.'), findsOneWidget);
      expect(currentRoom.attempts, isEmpty);
      await tester.enterText(
        find.byKey(const Key('student-result-note')),
        'Quạt lại ngừng chạy.',
      );
      await _tap(tester, submit);
      expect(
        currentRoom.attempts.single.kind,
        StudentRequestMutationKind.reopen,
      );
      expect(currentRoom.attempts.single.reason, 'Quạt lại ngừng chạy.');
      await tester.scrollUntilVisible(find.text('Chờ tiếp nhận'), -250);
      expect(find.text('Chờ tiếp nhận'), findsOneWidget);
      expect(find.text('DF000123'), findsOneWidget);
      expect(reopen, findsNothing);
    },
  );

  testWidgets(
    'late editor receipt after access invalidation never restores draft or completes navigation',
    (tester) async {
      final repo = _LiveRepository();
      addTearDown(repo.changes.close);
      final pending = Completer<StudentConfirmationReceipt>();
      repo.send = (_) => pending.future;
      var changed = 0;
      await _openDetail(tester, repo, changed: () => changed++);
      await _tap(tester, find.byTooltip('Chỉnh sửa yêu cầu'));
      await tester.enterText(
        find.byKey(const Key('student-edit-title')),
        'Nội dung riêng tư',
      );
      final save = find.text('Lưu thay đổi');
      await _scrollTo(tester, save);
      await tester.tap(save);
      await tester.pump();
      repo.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Nội dung riêng tư'), findsNothing);
      expect(find.text('Quay lại chi tiết'), findsOneWidget);
      pending.complete(repo.commit(repo.attempts.single));
      await tester.pumpAndSettle();
      expect(find.byType(EditRequestScreen), findsOneWidget);
      expect(find.byType(StudentResultActionForm), findsNothing);
      expect(changed, 0);
    },
  );
}
