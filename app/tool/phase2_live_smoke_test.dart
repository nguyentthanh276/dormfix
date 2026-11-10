// Manual, opt-in integration check. Not collected by `flutter test` under test/.
// Creates one clearly named demo request on the configured DormFix project.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/admin_requests/data/admin_request_repository.dart';
import 'package:dormfix/features/notifications/data/supabase_notification_repository.dart';
import 'package:dormfix/features/notifications/models/app_notification.dart';
import 'package:dormfix/features/student_confirmation/models/student_confirmation_submission.dart';
import 'package:dormfix/features/student_requests/data/request_repository.dart';
import 'package:dormfix/features/student_requests/data/supabase_request_repository.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/models/student_request_id.dart';
import 'package:dormfix/features/technician_jobs/data/technician_jobs_repository.dart';
import 'package:dormfix/features/technician_jobs/data/technician_tracking_repository.dart';
import 'package:dormfix/features/technician_jobs/data/technician_workflow_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_workflow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final enabled = Platform.environment['DORMFIX_RUN_LIVE_DEMO'] == '1';
  test(
    'three real roles complete a two-round repair through SDK repositories',
    () async {
      final password = Platform.environment['DORMFIX_DEMO_PASSWORD'];
      expect(
        password,
        isNotNull,
        reason: 'Set DORMFIX_DEMO_PASSWORD explicitly.',
      );
      expect(password, isNotEmpty);
      final config =
          jsonDecode(await File('config/local.json').readAsString()) as Map;
      expect(
        config['SUPABASE_URL'],
        'https://nxobutgnhceyabjbiiya.supabase.co',
      );
      final clients = <SupabaseClient>[];
      Future<SupabaseClient> login(String email) async {
        final client = SupabaseClient(
          config['SUPABASE_URL'] as String,
          config['SUPABASE_PUBLISHABLE_KEY'] as String,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        clients.add(client);
        await client.auth.signInWithPassword(email: email, password: password!);
        return client;
      }

      addTearDown(() async {
        for (final client in clients) {
          try {
            await client.auth.signOut(scope: SignOutScope.local);
          } finally {
            await client.dispose();
          }
        }
      });
      final studentClient = await login('student@example.com');
      final adminClient = await login('admin@example.com');
      final techClient = await login('technican@example.com');
      final student = SupabaseRequestRepository(studentClient);
      final admin = SupabaseAdminRequestRepository(adminClient);
      final jobs = SupabaseTechnicianJobsRepository(techClient);
      final workflow = SupabaseTechnicianWorkflowRepository(techClient);
      final tracking = SupabaseTechnicianTrackingRepository(techClient);
      final notifications = SupabaseNotificationRepository(
        client: studentClient,
      );
      final png = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
        ),
      );
      final category = (await student.fetchCategories()).first;
      final created = await student.createRequest(
        NewRepairRequest(
          requestId: createStudentRequestId(),
          title: '[PHAN 2 SDK DEMO] Kiểm tra ổ cắm và sửa lại',
          categoryId: category.id,
          description: 'Demo hai vòng xử lý bằng repository thật. Ảnh là PNG kiểm thử, không phải ảnh sự cố thực tế.',
        ),
      );
      await admin.assignRequest(created.id, techClient.auth.currentUser!.id);
      var job = await jobs.fetchJobDetail(created.id);
      expect(job.workflow.canStart, isTrue);
      await workflow.startJob(
        requestId: created.id,
        expectedVersion: job.job.version,
      );
      job = await jobs.fetchJobDetail(created.id);
      expect(job.workflow.canSubmitResult, isTrue);
      await workflow.submitResult(
        TechnicianResultSubmission.create(
          job: job.job,
          content: 'Lần 1: đã kiểm tra và thay đầu nối ổ cắm.',
          photos: [
            TechnicianResultPhoto.fromBytes(name: 'result-1.png', bytes: png),
          ],
        ),
      );
      var detail = await student.fetchRequestDetail(created.id);
      expect(detail.request.status, RepairStatus.awaitingConfirmation);
      expect(detail.results, hasLength(1));
      final firstVersion = detail.request.version;
      final rework = StudentConfirmationSubmission(
        actionId: createStudentRequestId(),
        requestId: created.id,
        expectedVersion: firstVersion,
        action: StudentResultAction.requestRework,
        note: 'Ổ cắm vẫn chập chờn khi cắm sạc, đề nghị kiểm tra lại.',
        attachments: [AttachmentDraft(name: 'feedback.png', bytes: png)],
      );
      final receipt = await student.submitConfirmation(rework);
      expect(receipt.status, RepairStatus.awaitingRework);
      expect(receipt.feedbackId, rework.actionId);
      expect((await student.submitConfirmation(rework)).replayed, isTrue);
      detail = await student.fetchRequestDetail(created.id);
      expect(detail.feedback, hasLength(1));
      final photo = detail.attachments.singleWhere(
        (p) => p.feedbackId == rework.actionId,
      );
      expect(
        await student.fetchAttachment(created.id, photo),
        orderedEquals(png),
      );
      job = await jobs.fetchJobDetail(created.id);
      expect(job.workflow.canContinue, isTrue);
      final techPhoto = job.attachments.singleWhere(
        (p) => p.feedbackId == rework.actionId,
      );
      expect(
        await jobs.fetchAttachment(created.id, techPhoto),
        orderedEquals(png),
      );
      final before = await tracking.fetchNotifications();
      expect(
        before.where(
          (n) => n.requestId == created.id && n.eventType == 'rework_requested',
        ),
        hasLength(1),
      );
      await expectLater(
        student.submitConfirmation(
          StudentConfirmationSubmission(
            actionId: createStudentRequestId(),
            requestId: created.id,
            expectedVersion: firstVersion,
            action: StudentResultAction.confirmFixed,
          ),
        ),
        throwsA(
          isA<RequestFailure>().having((e) => e.conflict, 'conflict', isTrue),
        ),
      );
      await workflow.continueJob(
        requestId: created.id,
        expectedVersion: job.job.version,
      );
      job = await jobs.fetchJobDetail(created.id);
      expect(job.workflow.canSubmitResult, isTrue);
      await workflow.submitResult(
        TechnicianResultSubmission.create(
          job: job.job,
          content: 'Lần 2: thay ổ cắm mới và thử tải ổn định.',
          photos: [
            TechnicianResultPhoto.fromBytes(name: 'result-2.png', bytes: png),
          ],
        ),
      );
      // An earlier action replay must not change a later repair round.
      expect(
        (await student.submitConfirmation(rework)).status,
        RepairStatus.awaitingRework,
      );
      detail = await student.fetchRequestDetail(created.id);
      expect(detail.request.status, RepairStatus.awaitingConfirmation);
      expect(detail.results, hasLength(2));
      final confirm = StudentConfirmationSubmission(
        actionId: createStudentRequestId(),
        requestId: created.id,
        expectedVersion: detail.request.version,
        action: StudentResultAction.confirmFixed,
        note: 'Đã kiểm tra sử dụng ổn định.',
      );
      expect(
        (await student.submitConfirmation(confirm)).status,
        RepairStatus.completed,
      );
      expect((await student.submitConfirmation(confirm)).replayed, isTrue);
      detail = await student.fetchRequestDetail(created.id);
      expect(detail.request.status, RepairStatus.completed);
      expect(detail.feedback, hasLength(1));
      expect(detail.results, hasLength(2));
      final raw = await studentClient.rpc(
        'student_get_request',
        params: {'p_request_id': created.id},
      ) as Map;
      final history = raw['history'] as List;
      expect(
        history.where((h) => h['action'] == 'student_confirmed'),
        hasLength(1),
      );
      expect(
        history.where((h) => h['action'] == 'student_rework_requested'),
        hasLength(1),
      );
      final adminDetail = await admin.fetchRequestDetail(created.id);
      final adminPhoto = adminDetail.attachments.singleWhere(
        (p) => p['feedback_id'] == rework.actionId,
      );
      expect(
        await admin.fetchAttachment(created.id, adminPhoto),
        orderedEquals(png),
      );
      final after = await tracking.fetchNotifications();
      expect(
        after.where(
          (n) => n.requestId == created.id && n.eventType == 'completed',
        ),
        hasLength(1),
      );
      final reported = (await notifications.fetchNotifications())
          .where(
            (n) =>
                n.requestId == created.id &&
                n.eventType == NotificationEventType.repairReported,
          )
          .toList();
      expect(reported, hasLength(2));
      await notifications.markAsRead(reported.first.id);
      expect(
        (await notifications.fetchNotifications())
            .singleWhere((n) => n.id == reported.first.id)
            .isRead,
        isTrue,
      );
      stdout.writeln(
        jsonEncode({
          'ok': true,
          'request_id': created.id,
          'request_code': created.requestCode,
          'status': detail.request.status.databaseValue,
          'repair_rounds': detail.results.length,
          'feedback_photo_private': true,
          'replayed_without_duplicate': true,
          'technician_notifications': true,
          'student_notifications': true,
        }),
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
