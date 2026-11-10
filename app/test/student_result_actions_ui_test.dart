import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/features/student_confirmation/data/confirmation_repository.dart';
import 'package:dormfix/features/student_confirmation/models/student_confirmation_submission.dart';
import 'package:dormfix/features/student_confirmation/presentation/awaiting_confirmation_screen.dart';
import 'package:dormfix/features/student_confirmation/presentation/request_confirmation_screen.dart';
import 'package:dormfix/features/student_confirmation/presentation/student_result_action_form.dart';
import 'package:dormfix/features/student_requests/data/request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/incident_category.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_detail.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '11111111-1111-4111-8111-111111111111';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aB1sAAAAASUVORK5CYII=',
);

class _Repository extends RequestRepository {
  final access = StreamController<void>.broadcast(sync: true);
  final submissions = <StudentConfirmationSubmission>[];
  RepairStatus status = RepairStatus.awaitingConfirmation;
  int version = 4;
  int reads = 0;
  bool deny = false;
  Future<StudentConfirmationReceipt> Function(StudentConfirmationSubmission)?
  submit;

  @override
  bool get supportsEditing => false;
  @override
  bool get supportsCancellation => false;
  @override
  bool get allowsDemoFallback => false;
  @override
  bool get supportsConfirmationActions => true;
  @override
  Stream<void> get accessChanges => access.stream;

  RequestDetail get detail => RequestDetail(
    request: RepairRequest(
      id: _id,
      requestCode: 'DF000287',
      title: 'Quạt trong phòng chưa chạy',
      categoryName: 'Điện',
      roomCode: 'A101',
      status: status,
      createdAt: DateTime.utc(2026, 11, 10),
      version: version,
    ),
    description: 'Quạt không quay dù đã bật công tắc.',
    history: const [],
    technicianName: 'Kỹ thuật viên',
    results: [
      RepairResultItem(
        id: 'result',
        technicianName: 'Kỹ thuật viên',
        content: 'Đã thay tụ điện và kiểm tra quạt chạy ổn định.',
        submittedAt: DateTime.utc(2026, 11, 10),
      ),
    ],
  );

  StudentConfirmationReceipt receipt(
    StudentConfirmationSubmission value, {
    String? feedbackId,
  }) => StudentConfirmationReceipt(
    requestId: value.requestId,
    actionId: value.actionId,
    status: value.action == StudentResultAction.confirmFixed
        ? RepairStatus.completed
        : RepairStatus.awaitingRework,
    version: value.expectedVersion + 1,
    replayed: false,
    feedbackId: value.action == StudentResultAction.requestRework
        ? feedbackId ?? value.actionId
        : null,
  );

  @override
  Future<StudentConfirmationReceipt> submitConfirmation(
    StudentConfirmationSubmission value,
  ) async {
    submissions.add(value);
    if (submit != null) return submit!(value);
    final result = receipt(value);
    status = result.status;
    version = result.version;
    return result;
  }

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) async {
    reads++;
    if (deny) {
      throw const RequestFailure('Không còn quyền.', accessDenied: true);
    }
    return detail;
  }

  @override
  Future<List<RepairRequest>> fetchMyRequests() async =>
      status == RepairStatus.awaitingConfirmation ? [detail.request] : [];
  @override
  Future<List<IncidentCategory>> fetchCategories() async => [];
  @override
  Future<RepairRequest> createRequest(NewRepairRequest request) async =>
      throw StateError('Not supported');
  @override
  Future<void> updateRequest(EditRepairRequest request) async =>
      throw StateError('Not supported');
  @override
  Future<void> cancelRequest({
    required String requestId,
    required String reason,
  }) async => throw StateError('Not supported');
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _form(
  WidgetTester tester,
  _Repository repo,
  StudentResultAction action, {
  Future<List<AttachmentDraft>> Function()? picker,
  ValueChanged<StudentConfirmationReceipt?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final receipt = await Navigator.of(context)
                  .push<StudentConfirmationReceipt>(
                    MaterialPageRoute(
                      builder: (_) => StudentResultActionForm(
                        repository: repo,
                        detail: repo.detail,
                        action: action,
                        pickAttachments: picker,
                      ),
                    ),
                  );
              onResult?.call(receipt);
            },
            child: const Text('Mở biểu mẫu'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Mở biểu mẫu'));
}

void main() {
  testWidgets(
    'real awaiting inbox uses full detail and refreshes after a verified confirmation',
    (tester) async {
      final repo = _Repository();
      addTearDown(repo.access.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AwaitingConfirmationScreen(
            repository: AdapterConfirmationRepository(repo),
            requestRepository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Quạt trong phòng chưa chạy'));
      expect(find.byType(RequestDetailScreen), findsOneWidget);
      expect(find.byType(RequestConfirmationScreen), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('student-confirm-fixed')),
        350,
      );
      await _tap(tester, find.byKey(const Key('student-confirm-fixed')));
      await _tap(tester, find.byKey(const Key('student-result-submit')));
      expect(repo.submissions.single.action, StudentResultAction.confirmFixed);
      expect(repo.submissions.single.note, isNull);
      expect(find.byType(StudentResultActionForm), findsNothing);
      await tester.scrollUntilVisible(find.text('Hoàn tất'), -350);
      expect(find.text('Hoàn tất'), findsOneWidget);
      expect(find.byKey(const Key('student-confirm-fixed')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Không có yêu cầu nào chờ xác nhận'), findsOneWidget);
    },
  );

  testWidgets(
    'rework validates reason and accepts, previews, removes and limits images on 320px mobile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Repository();
      addTearDown(repo.access.close);
      var picks = 0;
      StudentConfirmationReceipt? result;
      await _form(
        tester,
        repo,
        StudentResultAction.requestRework,
        picker: () async {
          picks++;
          return picks == 1
              ? [
                  AttachmentDraft(name: 'not-an-image.pdf', bytes: _png),
                  AttachmentDraft(
                    name: 'huge.png',
                    bytes: Uint8List(5 * 1024 * 1024 + 1),
                  ),
                ]
              : List.generate(
                  6,
                  (i) => AttachmentDraft(name: 'photo$i.png', bytes: _png),
                );
        },
        onResult: (value) => result = value,
      );
      await _tap(tester, find.byKey(const Key('student-result-submit')));
      expect(find.text('Vui lòng nhập lý do sửa lại.'), findsOneWidget);
      expect(repo.submissions, isEmpty);
      await _tap(tester, find.byKey(const Key('student-result-add-photos')));
      expect(find.text('Mỗi ảnh tối đa 5 MB'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await _tap(tester, find.byKey(const Key('student-result-add-photos')));
      expect(find.byType(Image), findsNWidgets(5));
      expect(find.text('Chỉ được đính kèm tối đa 5 ảnh'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('student-result-remove-0')));
      expect(find.byType(Image), findsNWidgets(4));
      await tester.enterText(
        find.byKey(const Key('student-result-note')),
        '  Quạt vẫn rung và kêu lớn.  ',
      );
      await _tap(tester, find.byKey(const Key('student-result-submit')));
      expect(repo.submissions.single.note, 'Quạt vẫn rung và kêu lớn.');
      expect(repo.submissions.single.attachments, hasLength(4));
      expect(result?.status, RepairStatus.awaitingRework);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain response freezes fields and retries the identical action only after explicit tap',
    (tester) async {
      final repo = _Repository();
      addTearDown(repo.access.close);
      repo.submit = (value) async {
        if (repo.submissions.length == 1) {
          throw const RequestFailure('Lost response', uncertain: true);
        }
        return repo.receipt(value);
      };
      StudentConfirmationReceipt? result;
      await _form(
        tester,
        repo,
        StudentResultAction.requestRework,
        onResult: (value) => result = value,
      );
      await tester.enterText(
        find.byKey(const Key('student-result-note')),
        'Vẫn chưa khắc phục.',
      );
      await _tap(tester, find.byKey(const Key('student-result-submit')));
      expect(result, isNull);
      expect(repo.submissions, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('student-result-note')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('student-result-add-photos')),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(repo.submissions, hasLength(1));
      await _tap(tester, find.text('Kiểm tra lại'));
      expect(repo.submissions, hasLength(2));
      expect(identical(repo.submissions[0], repo.submissions[1]), isTrue);
      expect(result?.actionId, repo.submissions.first.actionId);
    },
  );

  testWidgets('a mismatched feedback receipt never reports success', (
    tester,
  ) async {
    final repo = _Repository();
    addTearDown(repo.access.close);
    repo.submit = (value) async =>
        repo.receipt(value, feedbackId: 'other-feedback');
    StudentConfirmationReceipt? result;
    await _form(
      tester,
      repo,
      StudentResultAction.requestRework,
      onResult: (value) => result = value,
    );
    await tester.enterText(
      find.byKey(const Key('student-result-note')),
      'Chưa sửa xong.',
    );
    await _tap(tester, find.byKey(const Key('student-result-submit')));
    expect(result, isNull);
    expect(find.byType(StudentResultActionForm), findsOneWidget);
    expect(find.text('Kiểm tra lại'), findsOneWidget);
  });

  testWidgets(
    'pending request blocks double submit and back; revoked session discards late receipt and draft',
    (tester) async {
      final repo = _Repository();
      addTearDown(repo.access.close);
      final pending = Completer<StudentConfirmationReceipt>();
      repo.submit = (_) => pending.future;
      StudentConfirmationReceipt? result;
      await _form(
        tester,
        repo,
        StudentResultAction.requestRework,
        onResult: (value) => result = value,
      );
      await tester.enterText(
        find.byKey(const Key('student-result-note')),
        'Nội dung riêng tư.',
      );
      await tester.ensureVisible(
        find.byKey(const Key('student-result-submit')),
      );
      await tester.tap(find.byKey(const Key('student-result-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('student-result-submit')));
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(repo.submissions, hasLength(1));
      expect(find.byType(StudentResultActionForm), findsOneWidget);
      repo.access.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Nội dung riêng tư.'), findsNothing);
      expect(find.byKey(const Key('student-result-note')), findsNothing);
      pending.complete(repo.receipt(repo.submissions.single));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Quay lại chi tiết'), findsOneWidget);
    },
  );

  testWidgets(
    'session loss while picker is open discards returned private photo bytes',
    (tester) async {
      final repo = _Repository();
      addTearDown(repo.access.close);
      final picked = Completer<List<AttachmentDraft>>();
      await _form(
        tester,
        repo,
        StudentResultAction.requestRework,
        picker: () => picked.future,
      );
      await tester.ensureVisible(
        find.byKey(const Key('student-result-add-photos')),
      );
      await tester.tap(find.byKey(const Key('student-result-add-photos')));
      await tester.pump();
      repo.access.add(null);
      await tester.pumpAndSettle();
      picked.complete([AttachmentDraft(name: 'private.png', bytes: _png)]);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byKey(const Key('student-result-note')), findsNothing);
      expect(repo.submissions, isEmpty);
    },
  );

  testWidgets(
    'dirty back asks before discarding and conflict refresh cannot send stale action',
    (tester) async {
      final repo = _Repository();
      addTearDown(repo.access.close);
      repo.submit = (_) async =>
          throw const RequestFailure('Trạng thái đã thay đổi.', conflict: true);
      await _form(tester, repo, StudentResultAction.requestRework);
      await tester.enterText(
        find.byKey(const Key('student-result-note')),
        'Cần kiểm tra lại.',
      );
      await _tap(tester, find.byType(BackButton));
      expect(find.text('Bỏ nội dung đang nhập?'), findsOneWidget);
      await _tap(tester, find.text('Tiếp tục nhập'));
      expect(find.text('Cần kiểm tra lại.'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('student-result-submit')));
      expect(find.text('Trạng thái đã thay đổi.'), findsOneWidget);
      expect(find.byKey(const Key('student-result-submit')), findsNothing);
      await _tap(tester, find.text('Quay lại chi tiết'));
      expect(find.byType(StudentResultActionForm), findsNothing);
    },
  );

  testWidgets(
    'inactive app hides private form and resumed stale version requires refreshed detail',
    (tester) async {
      final repo = _Repository();
      addTearDown(repo.access.close);
      await _form(tester, repo, StudentResultAction.requestRework);
      await tester.enterText(
        find.byKey(const Key('student-result-note')),
        'Nội dung riêng tư.',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(const Key('student-result-note')), findsNothing);
      repo.version++;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Yêu cầu đã thay đổi. Hãy tải lại chi tiết trước khi thao tác.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('student-result-submit')), findsNothing);
      expect(repo.submissions, isEmpty);
    },
  );

  testWidgets(
    'resuming during a pending write rechecks read access before accepting its receipt',
    (tester) async {
      final repo = _Repository();
      addTearDown(repo.access.close);
      final pending = Completer<StudentConfirmationReceipt>();
      repo.submit = (_) => pending.future;
      StudentConfirmationReceipt? result;
      await _form(
        tester,
        repo,
        StudentResultAction.confirmFixed,
        onResult: (value) => result = value,
      );
      await tester.tap(find.byKey(const Key('student-result-submit')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      repo.deny = true;
      pending.complete(repo.receipt(repo.submissions.single));
      await tester.pumpAndSettle();
      expect(repo.reads, 1);
      expect(result, isNull);
      expect(find.text('Quay lại chi tiết'), findsOneWidget);
      expect(find.byType(StudentResultActionForm), findsOneWidget);
    },
  );
}
