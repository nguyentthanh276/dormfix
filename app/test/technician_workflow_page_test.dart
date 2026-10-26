import 'dart:async';
import 'dart:typed_data';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/technician_jobs/data/technician_workflow_repository.dart';
import 'package:dormfix/features/technician_jobs/data/technician_jobs_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_job.dart';
import 'package:dormfix/features/technician_jobs/models/technician_workflow.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_result_form.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_job_detail_page.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_job_photo.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_job_widgets.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'helpers/technician_jobs_fakes.dart';

const _jobId = '10000000-0000-4000-8000-000000000001';

TechnicianJob _job(RepairStatus status, {int version = 2}) => TechnicianJob(
  id: _jobId,
  requestCode: 'DF000001',
  title: 'Vòi nước phòng A101 rò rỉ',
  description: 'Ống nối bị nứt.',
  roomCode: 'A101',
  building: 'A',
  categoryName: 'Nước',
  status: status,
  createdAt: technicianTestDate,
  updatedAt: technicianTestDate,
  version: version,
);

TechnicianJobDetail _detail(
  RepairStatus status, {
  int version = 2,
  bool canStart = false,
  bool canContinue = false,
  bool canConfirmTransfer = false,
  bool canSubmit = false,
  List<JobAttachment> attachments = const [],
  List<JobResult> results = const [],
  List<JobFeedback> feedback = const [],
  List<JobHistoryEntry> history = const [],
  String? blockedReason,
  TechnicianWorkflowCapabilities? workflow,
}) => TechnicianJobDetail(
  job: _job(status, version: version),
  studentName: 'Sinh viên Nguyễn An',
  studentPhone: '0901234567',
  attachments: attachments,
  results: results,
  feedback: feedback,
  history: history,
  assignments: const [],
  workflow:
      workflow ??
      TechnicianWorkflowCapabilities(
        canStart: canStart,
        canContinue: canContinue,
        canConfirmTransfer: canConfirmTransfer,
        canSubmitResult: canSubmit,
        blockedReason: blockedReason,
      ),
);

JobResult _result(String id, String content) => JobResult(
  id: id,
  content: content,
  submittedAt: technicianTestDate,
  technicianName: 'Kỹ thuật viên Bình',
);

class _Workflow implements TechnicianWorkflowRepository {
  final starts = <({String requestId, int version})>[];
  final continuations = <({String requestId, int version})>[];
  final transferConfirmations = <({String requestId, int version})>[];
  final submissions = <TechnicianResultSubmission>[];
  Future<TechnicianWriteReceipt> Function()? onStart;
  Future<TechnicianWriteReceipt> Function()? onContinue;
  Future<TechnicianWriteReceipt> Function(int expectedVersion)?
  onConfirmTransfer;
  Future<TechnicianWriteReceipt> Function(TechnicianResultSubmission)? onSubmit;

  @override
  Future<TechnicianWriteReceipt> startJob({
    required String requestId,
    required int expectedVersion,
  }) async {
    starts.add((requestId: requestId, version: expectedVersion));
    return await onStart!();
  }

  @override
  Future<TechnicianWriteReceipt> continueJob({
    required String requestId,
    required int expectedVersion,
  }) async {
    continuations.add((requestId: requestId, version: expectedVersion));
    return await onContinue!();
  }

  @override
  Future<TechnicianWriteReceipt> confirmTransfer({
    required String requestId,
    required int expectedVersion,
  }) async {
    transferConfirmations.add((requestId: requestId, version: expectedVersion));
    return await onConfirmTransfer!(expectedVersion);
  }

  @override
  Future<TechnicianWriteReceipt> submitResult(
    TechnicianResultSubmission submission,
  ) async {
    submissions.add(submission);
    return await onSubmit!(submission);
  }
}

TechnicianWriteReceipt _receipt(
  RepairStatus status, {
  int version = 3,
  String? resultId,
}) => TechnicianWriteReceipt(
  requestId: _jobId,
  status: status,
  version: version,
  resultId: resultId,
);

typedef _Body = Future<void> Function(
  WidgetTester tester,
  TechnicianTestAuthRepository auth,
  TechnicianTestJobsRepository jobs,
  _Workflow workflow,
);

void _test(String name, _Body body) => testWidgets(name, (tester) async {
  final auth = TechnicianTestAuthRepository();
  final jobs = TechnicianTestJobsRepository();
  final workflow = _Workflow();
  try {
    await body(tester, auth, jobs, workflow);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await auth.dispose();
  }
});

Future<void> _mount(
  WidgetTester tester,
  TechnicianTestAuthRepository auth,
  TechnicianTestJobsRepository jobs,
  _Workflow? workflow,
) async {
  jobs.jobs = [jobs.detail.job];
  await tester.pumpWidget(
    DormFixApp(
      authRepository: auth,
      technicianJobsRepository: jobs,
      technicianWorkflowRepository: workflow,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(jobs.detail.job.title));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key, {bool settle = true}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pump();
  final target = find.byKey(Key(key));
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _openForm(
  WidgetTester tester, {
  String content = 'Đã thay van.',
}) async {
  await _tap(tester, 'technician-open-result-form');
  await tester.enterText(
    find.byKey(const Key('technician-result-content')),
    content,
  );
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target,
  double delta, {
  bool settle = true,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 35,
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  _test(
    'transfer confirmation requires in-progress status and server capability',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(
        RepairStatus.inProgress,
        workflow: TechnicianWorkflowCapabilities.fromJson({
          'can_start': false,
          'can_continue': false,
          'can_submit_result': false,
          'blocked_reason': 'TRANSFER_CONFIRMATION_REQUIRED',
        }),
      );
      await _mount(tester, auth, jobs, workflow);
      expect(
        find.byKey(const Key('technician-confirm-transfer')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsNothing,
      );
      expect(
        find.text(
          'Cần xác nhận công việc được chuyển đến trước khi gửi kết quả.',
        ),
        findsOneWidget,
      );
      for (final status in RepairStatus.values.where(
        (status) => status != RepairStatus.inProgress,
      )) {
        jobs.detail = _detail(status, canConfirmTransfer: true);
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('technician-confirm-transfer')),
          findsNothing,
        );
      }
      expect(workflow.transferConfirmations, isEmpty);
      expect(workflow.submissions, isEmpty);
    },
  );

  _test(
    'transfer confirmation stays unavailable without a workflow repository',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.inProgress, canConfirmTransfer: true);
      await _mount(tester, auth, jobs, null);
      expect(
        find.byKey(const Key('technician-confirm-transfer')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsNothing,
      );
      expect(find.text('Chi tiết công việc · Chỉ xem'), findsOneWidget);
      expect(workflow.transferConfirmations, isEmpty);
    },
  );

  _test(
    'confirmation waits for polling, is single-flight and refreshes unchanged status',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.inProgress, canConfirmTransfer: true);
      final pending = Completer<TechnicianWriteReceipt>();
      workflow.onConfirmTransfer = (_) => pending.future;
      await _mount(tester, auth, jobs, workflow);
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsNothing,
      );
      final poll = Completer<TechnicianJobDetail>();
      jobs.loadDetail = () => poll.future;
      await tester.pump(const Duration(seconds: 15));
      await _tap(tester, 'technician-confirm-transfer', settle: false);
      expect(workflow.transferConfirmations, isEmpty);
      poll.complete(
        _detail(RepairStatus.inProgress, version: 3, canConfirmTransfer: true),
      );
      await tester.pumpAndSettle();
      jobs.loadDetail = null;
      await _tap(tester, 'technician-confirm-transfer', settle: false);
      await _tap(tester, 'technician-confirm-transfer', settle: false);
      expect(workflow.transferConfirmations, [(requestId: _jobId, version: 3)]);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('technician-confirm-transfer')),
            )
            .onPressed,
        isNull,
      );
      final calls = jobs.detailCalls;
      await tester.pump(const Duration(seconds: 15));
      expect(
        jobs.detailCalls,
        calls,
        reason: 'Polling waits for confirmation.',
      );
      jobs.detail = _detail(RepairStatus.inProgress, version: 4);
      jobs.jobs = [jobs.detail.job];
      pending.complete(_receipt(RepairStatus.inProgress, version: 4));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('technician-confirm-transfer')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsNothing,
      );
      expect(find.text('Đang xử lý'), findsOneWidget);
      expect(find.text('Đã xác nhận tiếp tục công việc.'), findsOneWidget);
      expect(jobs.detailCalls, greaterThan(calls));
      expect(jobs.listCalls, 2);
      jobs.detail = _detail(
        RepairStatus.inProgress,
        version: 4,
        canSubmit: true,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      await _openForm(tester);
      expect(find.byKey(const Key('technician-result-form')), findsOneWidget);
      expect(workflow.starts, isEmpty);
      expect(workflow.continuations, isEmpty);
      expect(workflow.submissions, isEmpty);
    },
  );

  _test(
    'reassignment with unchanged status rejects the old version until an explicit new confirmation',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.inProgress, canConfirmTransfer: true);
      final acceptedVersions = <int>[];
      workflow.onConfirmTransfer = (version) async {
        if (version != jobs.detail.job.version) {
          throw const TechnicianWorkflowFailure(
            'Phân công đã thay đổi.',
            conflict: true,
          );
        }
        acceptedVersions.add(version);
        jobs.detail = _detail(
          RepairStatus.inProgress,
          version: version + 1,
          canSubmit: true,
        );
        return _receipt(RepairStatus.inProgress, version: version + 1);
      };
      await _mount(tester, auth, jobs, workflow);
      jobs.detail = _detail(
        RepairStatus.inProgress,
        version: 3,
        canConfirmTransfer: true,
      );
      await _tap(tester, 'technician-confirm-transfer');
      expect(workflow.transferConfirmations, [(requestId: _jobId, version: 2)]);
      expect(acceptedVersions, isEmpty);
      expect(find.text('Phân công đã thay đổi.'), findsOneWidget);
      expect(find.text('Đã xác nhận tiếp tục công việc.'), findsNothing);
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('technician-confirm-transfer')),
        findsOneWidget,
      );
      await _tap(tester, 'technician-confirm-transfer');
      expect(workflow.transferConfirmations, [
        (requestId: _jobId, version: 2),
        (requestId: _jobId, version: 3),
      ]);
      expect(acceptedVersions, [3]);
      expect(
        find.byKey(const Key('technician-confirm-transfer')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsOneWidget,
      );
    },
  );

  _test('continue requires rework status and an explicit server capability', (
    tester,
    auth,
    jobs,
    workflow,
  ) async {
    jobs.detail = _detail(
      RepairStatus.awaitingRework,
      workflow: TechnicianWorkflowCapabilities.fromJson({
        'can_start': false,
        'can_submit_result': false,
        'blocked_reason': 'CONTINUE_REQUIRED',
      }),
    );
    await _mount(tester, auth, jobs, workflow);
    expect(find.byKey(const Key('technician-continue-job')), findsNothing);
    expect(
      find.text('Cần xác nhận tiếp tục xử lý trước khi gửi kết quả mới.'),
      findsOneWidget,
    );
    for (final status in RepairStatus.values.where(
      (status) => status != RepairStatus.awaitingRework,
    )) {
      jobs.detail = _detail(status, canContinue: true);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('technician-continue-job')), findsNothing);
    }
    expect(workflow.continuations, isEmpty);
  });

  _test('continue stays unavailable without a workflow repository', (
    tester,
    auth,
    jobs,
    workflow,
  ) async {
    jobs.detail = _detail(RepairStatus.awaitingRework, canContinue: true);
    await _mount(tester, auth, jobs, null);
    expect(find.byKey(const Key('technician-continue-job')), findsNothing);
    expect(find.text('Chi tiết công việc · Chỉ xem'), findsOneWidget);
    expect(workflow.continuations, isEmpty);
  });

  _test(
    'continue waits for polling, is single-flight and refreshes server capabilities',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.awaitingRework, canContinue: true);
      final pending = Completer<TechnicianWriteReceipt>();
      workflow.onContinue = () => pending.future;
      await _mount(tester, auth, jobs, workflow);
      final poll = Completer<TechnicianJobDetail>();
      jobs.loadDetail = () => poll.future;
      await tester.pump(const Duration(seconds: 15));
      await _tap(tester, 'technician-continue-job', settle: false);
      expect(workflow.continuations, isEmpty);
      poll.complete(
        _detail(RepairStatus.awaitingRework, version: 3, canContinue: true),
      );
      await tester.pumpAndSettle();
      jobs.loadDetail = null;
      await _tap(tester, 'technician-continue-job', settle: false);
      await _tap(tester, 'technician-continue-job', settle: false);
      expect(workflow.continuations, [(requestId: _jobId, version: 3)]);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('technician-continue-job')),
            )
            .onPressed,
        isNull,
      );
      final calls = jobs.detailCalls;
      await tester.pump(const Duration(seconds: 15));
      expect(jobs.detailCalls, calls, reason: 'Polling waits for a write.');
      jobs.detail = _detail(RepairStatus.inProgress, version: 4);
      jobs.jobs = [jobs.detail.job];
      pending.complete(_receipt(RepairStatus.inProgress, version: 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('technician-continue-job')), findsNothing);
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsNothing,
      );
      expect(find.text('Đã tiếp tục xử lý công việc.'), findsOneWidget);
      expect(jobs.detailCalls, greaterThan(calls));
      expect(jobs.listCalls, 2);
      jobs.detail = _detail(
        RepairStatus.inProgress,
        version: 4,
        canSubmit: true,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      await _openForm(tester);
      expect(find.byKey(const Key('technician-result-form')), findsOneWidget);
      expect(workflow.starts, isEmpty);
      expect(workflow.submissions, isEmpty);
    },
  );

  for (final action in ['continue', 'confirm transfer']) {
    _test(
      '$action preserves old results, feedback and photo groups while pending and after refresh',
      (tester, auth, jobs, workflow) async {
        final isConfirm = action == 'confirm transfer';
        final actionKey = isConfirm
            ? 'technician-confirm-transfer'
            : 'technician-continue-job';
        final previous = technicianDetail(withPhotos: true);
        final event = JobHistoryEntry(
          id: 'new-workflow-history',
          action: isConfirm ? 'transfer_confirmed' : 'continued',
          actorName: 'Kỹ thuật viên Bình',
          oldStatus: isConfirm ? 'in_progress' : 'awaiting_rework',
          newStatus: 'in_progress',
          note: null,
          occurredAt: technicianTestDate.add(const Duration(hours: 1)),
        );
        TechnicianJobDetail context({bool finished = false}) => _detail(
          isConfirm || finished
              ? RepairStatus.inProgress
              : RepairStatus.awaitingRework,
          version: finished ? 3 : 2,
          canContinue: !isConfirm && !finished,
          canConfirmTransfer: isConfirm && !finished,
          canSubmit: finished,
          attachments: previous.attachments,
          results: previous.results,
          feedback: previous.feedback,
          history: [...previous.history, if (finished) event],
        );
        Future<void> expectContext({bool settle = true}) async {
          for (final section in [
            (title: 'Ảnh sự cố', photo: 'request-photo'),
            (title: 'Kết quả sửa chữa', photo: 'result-photo'),
            (title: 'Phản hồi của sinh viên', photo: 'feedback-photo'),
          ]) {
            await _scrollTo(
              tester,
              find.text(section.title),
              250,
              settle: settle,
            );
            final card = find.ancestor(
              of: find.text(section.title),
              matching: find.byType(Card),
            );
            expect(
              tester
                  .widgetList<TechnicianJobPhoto>(
                    find.descendant(
                      of: card,
                      matching: find.byType(TechnicianJobPhoto),
                    ),
                  )
                  .map((photo) => photo.attachment.id),
              [section.photo],
            );
            if (section.photo == 'result-photo') {
              expect(
                find.text(previous.results.single.content),
                findsOneWidget,
              );
            } else if (section.photo == 'feedback-photo') {
              expect(
                find.text(previous.feedback.single.reason),
                findsOneWidget,
              );
            }
          }
        }

        jobs.detail = context();
        final pending = Completer<TechnicianWriteReceipt>();
        workflow.onContinue = () => pending.future;
        workflow.onConfirmTransfer = (_) => pending.future;
        await _mount(tester, auth, jobs, workflow);
        await expectContext();
        await _scrollTo(tester, find.byKey(Key(actionKey)), -350);
        await _tap(tester, actionKey, settle: false);
        await expectContext(settle: false);
        jobs.detail = context(finished: true);
        jobs.jobs = [jobs.detail.job];
        pending.complete(_receipt(RepairStatus.inProgress));
        await tester.pumpAndSettle();
        await expectContext();
        await _scrollTo(tester, find.text('Lịch sử xử lý'), 250);
        expect(
          find.text(isConfirm ? 'Xác nhận tiếp tục' : 'Tiếp tục xử lý'),
          findsOneWidget,
        );
        expect(
          find.text('${event.actorName} · ${technicianDate(event.occurredAt)}'),
          findsOneWidget,
        );
        expect(
          find.text(
            isConfirm
                ? 'Đang xử lý → Đang xử lý'
                : 'Chờ xử lý lại → Đang xử lý',
          ),
          findsOneWidget,
        );
        expect(
          jobs.attachmentCalls,
          containsAll(['request-photo', 'result-photo', 'feedback-photo']),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final action in ['continue', 'confirm transfer']) {
    for (final uncertain in [false, true]) {
      _test(
        '${uncertain ? 'uncertain' : 'conflicting'} $action refreshes authoritative status',
        (tester, auth, jobs, workflow) async {
          final isConfirm = action == 'confirm transfer';
          final actionKey = isConfirm
              ? 'technician-confirm-transfer'
              : 'technician-continue-job';
          jobs.detail = _detail(
            isConfirm ? RepairStatus.inProgress : RepairStatus.awaitingRework,
            canContinue: !isConfirm,
            canConfirmTransfer: isConfirm,
          );
          Future<TechnicianWriteReceipt> failAfterServerChange() async {
            jobs.detail = _detail(
              RepairStatus.inProgress,
              version: 3,
              canSubmit: true,
            );
            jobs.jobs = [jobs.detail.job];
            throw TechnicianWorkflowFailure(
              uncertain
                  ? 'Mất phản hồi. Kiểm tra trạng thái mới.'
                  : 'Công việc đã thay đổi.',
              uncertain: uncertain,
              conflict: !uncertain,
            );
          }

          workflow.onContinue = failAfterServerChange;
          workflow.onConfirmTransfer = (_) => failAfterServerChange();
          await _mount(tester, auth, jobs, workflow);
          await _tap(tester, actionKey);
          expect(
            isConfirm ? workflow.transferConfirmations : workflow.continuations,
            [(requestId: _jobId, version: 2)],
          );
          expect(find.byKey(Key(actionKey)), findsNothing);
          expect(
            find.byKey(const Key('technician-open-result-form')),
            findsOneWidget,
          );
          expect(
            find.text(
              uncertain
                  ? 'Mất phản hồi. Kiểm tra trạng thái mới.'
                  : 'Công việc đã thay đổi.',
            ),
            findsOneWidget,
          );
          expect(jobs.detailCalls, 2);
          expect(jobs.listCalls, 2);
        },
      );
    }
  }

  for (final action in ['continue', 'confirm transfer']) {
    _test('denied $action removes contact, feedback and private photos', (
      tester,
      auth,
      jobs,
      workflow,
    ) async {
      final isConfirm = action == 'confirm transfer';
      final previous = technicianDetail(withPhotos: true);
      jobs.detail = _detail(
        isConfirm ? RepairStatus.inProgress : RepairStatus.awaitingRework,
        canContinue: !isConfirm,
        canConfirmTransfer: isConfirm,
        attachments: previous.attachments,
        results: previous.results,
        feedback: previous.feedback,
      );
      workflow.onContinue = () async => throw const TechnicianWorkflowFailure(
        'Không còn quyền.',
        accessDenied: true,
      );
      workflow.onConfirmTransfer = (_) async =>
          throw const TechnicianWorkflowFailure(
            'Không còn quyền.',
            accessDenied: true,
          );
      await _mount(tester, auth, jobs, workflow);
      await _tap(
        tester,
        isConfirm ? 'technician-confirm-transfer' : 'technician-continue-job',
      );
      expect(find.byKey(const Key('technician-job-detail')), findsNothing);
      expect(
        find.textContaining('Bạn không còn quyền xem công việc này'),
        findsOneWidget,
      );
      expect(find.textContaining('0901234567'), findsNothing);
      expect(find.text(previous.feedback.single.reason), findsNothing);
      expect(find.byType(TechnicianJobPhoto), findsNothing);
      expect(jobs.detailCalls, 1);
    });
  }

  _test(
    'start is single-flight, uses current version and refreshes list/detail',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.assigned, canStart: true);
      final pending = Completer<TechnicianWriteReceipt>();
      workflow.onStart = () => pending.future;
      await _mount(tester, auth, jobs, workflow);
      await _tap(tester, 'technician-start-job', settle: false);
      await _tap(tester, 'technician-start-job', settle: false);
      expect(workflow.starts, [(requestId: _jobId, version: 2)]);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('technician-start-job')))
            .onPressed,
        isNull,
      );
      final calls = jobs.detailCalls;
      await tester.pump(const Duration(seconds: 15));
      expect(jobs.detailCalls, calls, reason: 'Polling waits for a write.');
      jobs.detail = _detail(
        RepairStatus.inProgress,
        version: 3,
        canSubmit: true,
      );
      jobs.jobs = [jobs.detail.job];
      pending.complete(_receipt(RepairStatus.inProgress));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('technician-start-job')), findsNothing);
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsOneWidget,
      );
      expect(find.text('Đã bắt đầu xử lý công việc.'), findsOneWidget);
      expect(jobs.detailCalls, greaterThan(calls));
      expect(jobs.listCalls, 2);
    },
  );

  _test('status and backend capabilities both gate writes', (
    tester,
    auth,
    jobs,
    workflow,
  ) async {
    jobs.detail = _detail(RepairStatus.inProgress);
    await _mount(tester, auth, jobs, workflow);
    expect(find.byKey(const Key('technician-open-result-form')), findsNothing);
    for (final status in [
      RepairStatus.awaitingRework,
      RepairStatus.completed,
      RepairStatus.cancelled,
      RepairStatus.awaitingConfirmation,
    ]) {
      jobs.detail = _detail(status, canStart: true, canSubmit: true);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('technician-start-job')), findsNothing);
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsNothing,
      );
    }
    expect(workflow.starts, isEmpty);
    expect(workflow.submissions, isEmpty);
  });

  _test(
    'start failure revalidates; conflict shows new status without stale action',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.assigned, canStart: true);
      workflow.onStart = () async =>
          throw const TechnicianWorkflowFailure('Mất kết nối.');
      await _mount(tester, auth, jobs, workflow);
      await _tap(tester, 'technician-start-job');
      expect(find.text('Mất kết nối.'), findsOneWidget);
      expect(jobs.detailCalls, 2);
      workflow.onStart = () async {
        jobs.detail = _detail(
          RepairStatus.inProgress,
          version: 3,
          canSubmit: true,
        );
        throw const TechnicianWorkflowFailure(
          'Công việc đã được cập nhật.',
          conflict: true,
        );
      };
      await _tap(tester, 'technician-start-job');
      expect(find.text('Công việc đã được cập nhật.'), findsOneWidget);
      expect(find.byKey(const Key('technician-start-job')), findsNothing);
      expect(
        find.byKey(const Key('technician-open-result-form')),
        findsOneWidget,
      );
    },
  );

  _test(
    'result requires trimmed text; single submit refreshes status and keeps history',
    (tester, auth, jobs, workflow) async {
      final old = _result('old-result', 'Kết quả cũ được giữ nguyên.');
      jobs.detail = _detail(
        RepairStatus.inProgress,
        canSubmit: true,
        results: [old],
      );
      final pending = Completer<TechnicianWriteReceipt>();
      workflow.onSubmit = (_) => pending.future;
      await _mount(tester, auth, jobs, workflow);
      await _openForm(tester, content: '   ');
      await _tap(tester, 'technician-submit-result');
      expect(find.text('Vui lòng nhập kết quả sửa chữa.'), findsOneWidget);
      expect(workflow.submissions, isEmpty);
      await tester.enterText(
        find.byKey(const Key('technician-result-content')),
        '  Đã thay van.  ',
      );
      await _tap(tester, 'technician-submit-result', settle: false);
      await _tap(tester, 'technician-submit-result', settle: false);
      expect(workflow.submissions, hasLength(1));
      final submission = workflow.submissions.single;
      expect(submission.content, 'Đã thay van.');
      expect(submission.photos, isEmpty);
      expect(submission.expectedVersion, 2);
      jobs.detail = _detail(
        RepairStatus.awaitingConfirmation,
        version: 3,
        results: [old, _result(submission.resultId, submission.content)],
      );
      pending.complete(
        _receipt(
          RepairStatus.awaitingConfirmation,
          resultId: submission.resultId,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('technician-result-form')), findsNothing);
      expect(
        find.text('Đã gửi kết quả. Đang chờ sinh viên xác nhận.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text(old.content),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(old.content), findsOneWidget);
      expect(jobs.listCalls, 2);
    },
  );

  _test(
    'uncertain result retry retains identical immutable submission and frozen draft',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.inProgress, canSubmit: true);
      workflow.onSubmit = (submission) async {
        if (workflow.submissions.length == 1) {
          throw const TechnicianWorkflowFailure(
            'Chưa xác nhận lần gửi.',
            uncertain: true,
          );
        }
        jobs.detail = _detail(
          RepairStatus.awaitingConfirmation,
          version: 3,
          results: [_result(submission.resultId, submission.content)],
        );
        return _receipt(
          RepairStatus.awaitingConfirmation,
          resultId: submission.resultId,
        );
      };
      await _mount(tester, auth, jobs, workflow);
      await _openForm(tester);
      await _tap(tester, 'technician-submit-result');
      expect(find.text('Gửi lại cùng kết quả'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('technician-result-content')),
            )
            .enabled,
        isFalse,
      );
      await _tap(tester, 'technician-submit-result');
      expect(workflow.submissions, hasLength(2));
      expect(
        identical(workflow.submissions[0], workflow.submissions[1]),
        isTrue,
      );
      expect(find.byKey(const Key('technician-result-form')), findsNothing);
    },
  );

  _test(
    'lost response reconciles submitted result from refreshed detail without retry',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.inProgress, canSubmit: true);
      workflow.onSubmit = (submission) async {
        jobs.detail = _detail(
          RepairStatus.awaitingConfirmation,
          version: 3,
          results: [_result(submission.resultId, submission.content)],
        );
        throw const TechnicianWorkflowFailure(
          'Chưa xác nhận.',
          uncertain: true,
        );
      };
      await _mount(tester, auth, jobs, workflow);
      await _openForm(tester);
      await _tap(tester, 'technician-submit-result');
      expect(workflow.submissions, hasLength(1));
      expect(find.byKey(const Key('technician-result-form')), findsNothing);
      expect(
        find.text('Đã gửi kết quả. Đang chờ sinh viên xác nhận.'),
        findsOneWidget,
      );
    },
  );

  _test(
    'version change discards draft; denied write removes detail and draft',
    (tester, auth, jobs, workflow) async {
      jobs.detail = _detail(RepairStatus.inProgress, canSubmit: true);
      await _mount(tester, auth, jobs, workflow);
      await _openForm(tester, content: 'Nội dung riêng tư');
      jobs.detail = _detail(
        RepairStatus.inProgress,
        version: 3,
        canSubmit: true,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('technician-result-form')), findsNothing);
      expect(find.text('Nội dung riêng tư'), findsNothing);
      await _openForm(tester);
      workflow.onSubmit = (_) async => throw const TechnicianWorkflowFailure(
        'Không còn quyền.',
        accessDenied: true,
      );
      await _tap(tester, 'technician-submit-result');
      expect(find.byKey(const Key('technician-result-form')), findsNothing);
      expect(find.text('Sinh viên Nguyễn An'), findsNothing);
      expect(
        find.textContaining('Bạn không còn quyền xem công việc này'),
        findsOneWidget,
      );
    },
  );

  _test('submit conflict clears form and fetches latest version', (
    tester,
    auth,
    jobs,
    workflow,
  ) async {
    jobs.detail = _detail(RepairStatus.inProgress, canSubmit: true);
    workflow.onSubmit = (_) async {
      jobs.detail = _detail(RepairStatus.awaitingConfirmation, version: 3);
      throw const TechnicianWorkflowFailure(
        'Dữ liệu đã thay đổi.',
        conflict: true,
      );
    };
    await _mount(tester, auth, jobs, workflow);
    await _openForm(tester);
    await _tap(tester, 'technician-submit-result');
    expect(find.byKey(const Key('technician-result-form')), findsNothing);
    expect(find.byKey(const Key('technician-open-result-form')), findsNothing);
    expect(find.text('Dữ liệu đã thay đổi.'), findsOneWidget);
    expect(jobs.detailCalls, 2);
  });

  for (final action in ['submit', 'continue', 'confirm transfer']) {
    for (final leave in ['back', 'logout']) {
      _test(
        '$leave during $action cannot restore private data after completion',
        (tester, auth, jobs, workflow) async {
          final isContinue = action == 'continue';
          final isConfirm = action == 'confirm transfer';
          jobs.detail = _detail(
            isContinue ? RepairStatus.awaitingRework : RepairStatus.inProgress,
            canContinue: isContinue,
            canConfirmTransfer: isConfirm,
            canSubmit: !isContinue && !isConfirm,
            results: [
              _result('old-private-result', 'Kết quả riêng tư trước đó'),
            ],
          );
          final pending = Completer<TechnicianWriteReceipt>();
          workflow.onContinue = () => pending.future;
          workflow.onConfirmTransfer = (_) => pending.future;
          workflow.onSubmit = (_) => pending.future;
          await _mount(tester, auth, jobs, workflow);
          if (isConfirm) {
            await _tap(tester, 'technician-confirm-transfer', settle: false);
          } else if (isContinue) {
            await _tap(tester, 'technician-continue-job', settle: false);
          } else {
            await _openForm(tester, content: 'Nội dung riêng tư');
            await _tap(tester, 'technician-submit-result', settle: false);
          }
          if (leave == 'back') {
            await tester.tap(find.byType(BackButton));
          } else {
            await tester.tap(find.text('Đăng xuất'));
          }
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('technician-result-form')), findsNothing);
          pending.complete(
            _receipt(
              isContinue || isConfirm
                  ? RepairStatus.inProgress
                  : RepairStatus.awaitingConfirmation,
              resultId: isContinue || isConfirm
                  ? null
                  : workflow.submissions.single.resultId,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Nội dung riêng tư'), findsNothing);
          expect(find.text('Kết quả riêng tư trước đó'), findsNothing);
          expect(find.textContaining('0901234567'), findsNothing);
          expect(find.byKey(const Key('technician-job-detail')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final outcome in [
    'start',
    'continue',
    'confirm transfer',
    'submit',
    'uncertain',
  ]) {
    _test('back during $outcome refreshes Home after pending write completes', (
      tester,
      auth,
      jobs,
      workflow,
    ) async {
      final isStart = outcome == 'start';
      final isContinue = outcome == 'continue';
      final isConfirm = outcome == 'confirm transfer';
      jobs.detail = isStart
          ? _detail(RepairStatus.assigned, canStart: true)
          : isContinue
          ? _detail(RepairStatus.awaitingRework, canContinue: true)
          : isConfirm
          ? _detail(RepairStatus.inProgress, canConfirmTransfer: true)
          : _detail(RepairStatus.inProgress, canSubmit: true);
      final pending = Completer<TechnicianWriteReceipt>();
      workflow.onStart = () => pending.future;
      workflow.onContinue = () => pending.future;
      workflow.onConfirmTransfer = (_) => pending.future;
      workflow.onSubmit = (_) => pending.future;
      await _mount(tester, auth, jobs, workflow);
      if (isStart) {
        await _tap(tester, 'technician-start-job', settle: false);
      } else if (isContinue) {
        await _tap(tester, 'technician-continue-job', settle: false);
      } else if (isConfirm) {
        await _tap(tester, 'technician-confirm-transfer', settle: false);
      } else {
        await _openForm(tester);
        await _tap(tester, 'technician-submit-result', settle: false);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(jobs.listCalls, 2);
      expect(
        find.text(
          isStart
              ? 'Đã phân công'
              : isContinue
              ? 'Chờ xử lý lại'
              : 'Đang xử lý',
        ),
        findsOneWidget,
      );
      final nextStatus = isStart || isContinue || isConfirm
          ? RepairStatus.inProgress
          : RepairStatus.awaitingConfirmation;
      jobs.jobs = [_job(nextStatus, version: 3)];
      if (outcome == 'uncertain') {
        pending.completeError(
          const TechnicianWorkflowFailure('Mất phản hồi.', uncertain: true),
        );
      } else {
        pending.complete(
          _receipt(
            nextStatus,
            resultId: isStart || isContinue || isConfirm
                ? null
                : workflow.submissions.single.resultId,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(
        jobs.listCalls,
        3,
        reason: 'The disposed detail still notifies its original Home once.',
      );
      expect(find.text(nextStatus.label), findsOneWidget);
      expect(find.byKey(const Key('technician-job-detail')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['submit', 'continue', 'confirm transfer']) {
    _test(
      'old $action completion cannot refresh a newly signed-in technician Home',
      (tester, auth, jobs, workflow) async {
        final isContinue = action == 'continue';
        final isConfirm = action == 'confirm transfer';
        jobs.detail = _detail(
          isContinue ? RepairStatus.awaitingRework : RepairStatus.inProgress,
          canContinue: isContinue,
          canConfirmTransfer: isConfirm,
          canSubmit: !isContinue && !isConfirm,
          results: [_result('old-account-result', 'Kết quả của tài khoản cũ')],
        );
        final pending = Completer<TechnicianWriteReceipt>();
        workflow.onContinue = () => pending.future;
        workflow.onConfirmTransfer = (_) => pending.future;
        workflow.onSubmit = (_) => pending.future;
        await _mount(tester, auth, jobs, workflow);
        final controller = tester
            .widget<TechnicianHomePage>(find.byType(TechnicianHomePage))
            .controller;
        if (isConfirm) {
          await _tap(tester, 'technician-confirm-transfer', settle: false);
        } else if (isContinue) {
          await _tap(tester, 'technician-continue-job', settle: false);
        } else {
          await _openForm(tester, content: 'Nội dung của tài khoản cũ');
          await _tap(tester, 'technician-submit-result', settle: false);
        }
        await tester.tap(find.text('Đăng xuất'));
        await tester.pumpAndSettle();
        auth.profile = technicianProfile(id: 'technician-2');
        jobs.jobs = [
          technicianJob(id: 'new-job', title: 'Công việc của tài khoản mới'),
        ];
        await controller.signIn(
          email: 'new@example.com',
          password: 'temporary',
        );
        await tester.pumpAndSettle();
        final calls = jobs.listCalls;
        expect(find.text('Công việc của tài khoản mới'), findsOneWidget);
        pending.complete(
          _receipt(
            isContinue || isConfirm
                ? RepairStatus.inProgress
                : RepairStatus.awaitingConfirmation,
            resultId: isContinue || isConfirm
                ? null
                : workflow.submissions.single.resultId,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          jobs.listCalls,
          calls,
          reason: 'Old callbacks cannot read the new account.',
        );
        expect(find.text('Công việc của tài khoản mới'), findsOneWidget);
        expect(find.text('Nội dung của tài khoản cũ'), findsNothing);
        expect(find.text('Kết quả của tài khoản cũ'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'system photo picker keeps hidden draft until resumed access check',
    (tester) async {
      final jobs = TechnicianTestJobsRepository()
        ..detail = _detail(RepairStatus.inProgress, canSubmit: true);
      final workflow = _Workflow();
      final picker = Completer<List<XFile>>();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TechnicianJobDetailPage(
                requestId: _jobId,
                repository: jobs,
                workflowRepository: workflow,
                onAccessDenied: () {},
                pickResultImages: () => picker.future,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _openForm(tester, content: 'Nội dung đang nhập');
        await _tap(tester, 'technician-add-result-photos', settle: false);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(find.text('Nội dung đang nhập'), findsNothing);
        final validation = Completer<TechnicianJobDetail>();
        jobs.loadDetail = () => validation.future;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        picker.complete([
          XFile.fromData(
            technicianPng(),
            path: 'picked.png',
            name: 'picked.png',
          ),
        ]);
        await tester.pump();
        expect(find.byKey(const Key('technician-result-form')), findsNothing);
        expect(find.text('picked.png'), findsNothing);
        validation.complete(jobs.detail);
        await tester.pumpAndSettle();
        expect(find.text('Nội dung đang nhập'), findsOneWidget);
        expect(find.text('picked.png'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(jobs.detailCalls, 2);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  for (final outcome in ['denied', 'changed']) {
    testWidgets(
      'picker resume $outcome discards private draft and late photos',
      (tester) async {
        final jobs = TechnicianTestJobsRepository()
          ..detail = _detail(RepairStatus.inProgress, canSubmit: true);
        final picker = Completer<List<XFile>>();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TechnicianJobDetailPage(
                  requestId: _jobId,
                  repository: jobs,
                  workflowRepository: _Workflow(),
                  onAccessDenied: () {},
                  pickResultImages: () => picker.future,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _openForm(tester, content: 'Nội dung riêng tư đang nhập');
          await _tap(tester, 'technician-add-result-photos', settle: false);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          jobs.loadDetail = () async {
            if (outcome == 'denied') {
              throw const TechnicianJobsFailure(
                'Không còn quyền.',
                accessDenied: true,
              );
            }
            return _detail(
              RepairStatus.inProgress,
              version: 3,
              canSubmit: true,
            );
          };
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          picker.complete([
            XFile.fromData(
              technicianPng(),
              path: 'private.png',
              name: 'private.png',
            ),
          ]);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('technician-result-form')), findsNothing);
          expect(find.text('Nội dung riêng tư đang nhập'), findsNothing);
          expect(find.text('private.png'), findsNothing);
          expect(find.byType(Image), findsNothing);
          if (outcome == 'denied') {
            expect(
              find.textContaining('Bạn không còn quyền xem công việc này'),
              findsOneWidget,
            );
          } else {
            await _openForm(tester, content: '');
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const Key('technician-result-content')),
                  )
                  .controller!
                  .text,
              isEmpty,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }

  testWidgets(
    'result photos validate batch count, actual type, size and allow removal',
    (tester) async {
      var selected = <XFile>[];
      final submitted = <TechnicianResultSubmission>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TechnicianResultForm(
                job: _job(RepairStatus.inProgress),
                pickImages: () async => selected,
                onSubmit: (submission) async => submitted.add(submission),
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      selected = List.generate(
        6,
        (i) => XFile.fromData(technicianPng(), name: '$i.png'),
      );
      await _tap(tester, 'technician-add-result-photos');
      expect(find.text('Chỉ được đính kèm tối đa 5 ảnh.'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      selected = [
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fake.png'),
      ];
      await _tap(tester, 'technician-add-result-photos');
      expect(
        find.text('Chỉ nhận ảnh JPG, PNG hoặc WebP hợp lệ.'),
        findsOneWidget,
      );
      selected = [
        XFile.fromData(
          Uint8List(TechnicianResultPhoto.maxBytes + 1),
          name: 'large.png',
        ),
      ];
      await _tap(tester, 'technician-add-result-photos');
      expect(find.text('Mỗi ảnh tối đa 5 MB.'), findsOneWidget);
      selected = [
        XFile.fromData(technicianPng(), path: 'repair.png', name: 'repair.png'),
      ];
      await _tap(tester, 'technician-add-result-photos');
      expect(find.text('repair.png'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Xóa ảnh repair.png'));
      await tester.tap(find.byTooltip('Xóa ảnh repair.png'));
      await tester.pumpAndSettle();
      expect(find.text('repair.png'), findsNothing);
      selected = List.generate(
        5,
        (i) => XFile.fromData(technicianPng(), name: '$i.png'),
      );
      await _tap(tester, 'technician-add-result-photos');
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('technician-add-result-photos')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('technician-result-content')),
      );
      await tester.enterText(
        find.byKey(const Key('technician-result-content')),
        ' Đã sửa. ',
      );
      await _tap(tester, 'technician-submit-result');
      expect(submitted.single.photos, hasLength(5));
      expect(submitted.single.content, 'Đã sửa.');
      final previews = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .toList();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final preview in previews) {
        expect(
          PaintingBinding.instance.imageCache.statusForKey(preview).untracked,
          isTrue,
          reason: 'Disposed drafts evict preview images.',
        );
      }
    },
  );
}
