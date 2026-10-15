import 'dart:async';
import 'dart:typed_data';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/technician_jobs/data/technician_jobs_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_job.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'app opens injected technician data and closes detail on expiry',
    (tester) async {
      final auth = _TestAuthRepository();
      final jobs = _TestJobsRepository();
      await tester.pumpWidget(
        DormFixApp(authRepository: auth, technicianJobsRepository: jobs),
      );
      await tester.pumpAndSettle();

      expect(find.text('DormFix - Kỹ thuật viên'), findsOneWidget);
      expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
      expect(jobs.listCalls, 1);
      await tester.tap(find.text('Vòi nước rò rỉ'));
      await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.textContaining('Điện thoại: 0900000001'),
      find.byKey(const Key('technician-job-detail')),
      const Offset(0, -200),
    );
    expect(find.textContaining('Họ tên: Sinh viên kiểm thử'), findsOneWidget);
    expect(find.textContaining('Điện thoại: 0900000001'), findsOneWidget);
      expect(jobs.detailCalls, 1);

      auth.expire();
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập DormFix'), findsOneWidget);
    expect(find.textContaining('Sinh viên kiểm thử'), findsNothing);
    expect(find.textContaining('0900000001'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập DormFix'), findsOneWidget);
      expect(find.text('Vòi nước rò rỉ'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets('password-gated technician cannot load job data', (tester) async {
    final auth = _TestAuthRepository(mustChangePassword: true);
    final jobs = _TestJobsRepository();
    await tester.pumpWidget(
      DormFixApp(authRepository: auth, technicianJobsRepository: jobs),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cần đổi mật khẩu'), findsOneWidget);
    expect(find.text('DormFix - Kỹ thuật viên'), findsNothing);
    expect(jobs.listCalls, 0);
    expect(jobs.detailCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await auth.close();
  });
}

class _TestAuthRepository implements AuthRepository {
  _TestAuthRepository({this.mustChangePassword = false});

  final bool mustChangePassword;
  final _changes = StreamController<bool>.broadcast(sync: true);
  bool _hasSession = true;

  @override
  bool get hasSession => _hasSession;

  @override
  Stream<bool> get sessionChanges => _changes.stream;

  @override
  Future<UserProfile> loadProfile() async => UserProfile(
    id: 'technician-integration-test',
    identityCode: 'KTV-INTEGRATION',
    fullName: 'Kỹ thuật viên kiểm thử',
    email: 'technician-integration@example.test',
    phone: '0900000002',
    role: AppRole.technician,
    status: 'active',
    room: null,
    mustChangePassword: mustChangePassword,
    canAccess: !mustChangePassword,
  );

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    _hasSession = true;
    _changes.add(true);
    return loadProfile();
  }

  void expire() {
    _hasSession = false;
    _changes.add(false);
  }

  @override
  Future<void> signOut() async => expire();

  Future<void> close() => _changes.close();
}

class _TestJobsRepository implements TechnicianJobsRepository {
  int listCalls = 0;
  int detailCalls = 0;

  static final _job = TechnicianJob(
    id: 'request-integration-test',
    requestCode: 'DF000001',
    title: 'Vòi nước rò rỉ',
    description: 'Vòi nước trong phòng rò rỉ.',
    roomCode: 'A101',
    building: 'A',
    categoryName: 'Nước',
    status: RepairStatus.awaitingRework,
    createdAt: DateTime.utc(2026, 10, 12),
    updatedAt: DateTime.utc(2026, 10, 15),
    version: 2,
  );

  @override
  Future<List<TechnicianJob>> fetchJobs() async {
    listCalls++;
    return [_job];
  }

  @override
  Future<TechnicianJobDetail> fetchJobDetail(String requestId) async {
    detailCalls++;
    return TechnicianJobDetail(
      job: _job,
      studentName: 'Sinh viên kiểm thử',
      studentPhone: '0900000001',
      attachments: const [],
      results: const [],
      feedback: const [],
      history: const [],
      assignments: const [],
    );
  }

  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    JobAttachment attachment,
  ) async => throw StateError('Fixture has no attachments');
}
