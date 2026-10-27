import 'dart:async';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:dormfix/features/student_requests/presentation/student_shell_screen.dart';
import 'package:dormfix/features/student_requests/presentation/widgets/request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expiry removes the cancellation dialog and its private draft', (
    tester,
  ) async {
    final auth = _StudentAuthRepository();
    await _openAuthenticatedDetail(tester, auth);
    await _openCancelDialog(tester);
    await tester.enterText(
      find.byType(TextField),
      'Lý do riêng của sinh viên A',
    );

    auth.expire();
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập DormFix'), findsOneWidget);
    _expectOldCancellationGone();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập DormFix'), findsOneWidget);
    _expectOldCancellationGone();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching students discards the cancellation dialog and draft', (
    tester,
  ) async {
    final auth = _StudentAuthRepository();
    await _openAuthenticatedDetail(tester, auth);
    await _openCancelDialog(tester);
    await tester.enterText(
      find.byType(TextField),
      'Lý do riêng của sinh viên A',
    );

    auth.switchStudent(_studentB);
    await tester.pumpAndSettle();

    _expectOldCancellationGone();
    expect(find.text('Yêu cầu của tôi'), findsOneWidget);
    expect(find.text('DEMO-B202'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _expectOldCancellationGone();
    expect(find.text('DEMO-B202'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'system back closes only the cancellation dialog without writing',
    (tester) async {
      final repository = _TrackingRepository('DEMO-A101');
      await _openShellDetail(tester, repository);
      await _openCancelDialog(tester);
      await tester.enterText(find.byType(TextField), 'Chưa đồng ý hủy');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(RequestDetailScreen), findsOneWidget);
      expect(repository.cancelCalls, 0);
      expect(
        (await repository.fetchRequestDetail('mock-2')).request.status,
        RepairStatus.assigned,
      );
      await _openCancelDialog(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text ?? '',
        isEmpty,
      );
      expect(find.text('Chưa đồng ý hủy'), findsNothing);
    },
  );

  testWidgets(
    'cancel is single flight and returning to the list reloads status',
    (tester) async {
      final gate = Completer<void>();
      final repository = _TrackingRepository('DEMO-A101', gate: gate);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await _openShellDetail(tester, repository);
      final listReadsBeforeCancel = repository.listReads;
      await _openCancelDialog(tester);
      await tester.enterText(find.byType(TextField), '  Tôi tự sửa được rồi  ');

      // Two queued taps before rebuilding must still send just one operation.
      await tester.tap(find.text('Xác nhận hủy'));
      await tester.tap(find.text('Xác nhận hủy'));
      await tester.pump();

      expect(repository.cancelCalls, 1);
      expect(repository.lastReason, 'Tôi tự sửa được rồi');
      final cancelIcon = find.widgetWithIcon(IconButton, Icons.cancel_outlined);
      if (cancelIcon.evaluate().isNotEmpty) {
        expect(tester.widget<IconButton>(cancelIcon).onPressed, isNull);
      }
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(RequestDetailScreen), findsOneWidget);
      expect(repository.cancelCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();

      expect(repository.cancelCalls, 1);
      final detail = await repository.fetchRequestDetail('mock-2');
      expect(detail.request.status, RepairStatus.cancelled);
      expect(detail.history.last.note, contains('Tôi tự sửa được rồi'));
      expect(find.byType(RequestDetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(repository.listReads, greaterThan(listReadsBeforeCancel));
      final card = tester.widget<RequestCard>(
        find.ancestor(
          of: find.text('Vòi nước rò rỉ'),
          matching: find.byType(RequestCard),
        ),
      );
      expect(card.request.status, RepairStatus.cancelled);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'late cancel ${fail ? 'failure' : 'success'} cannot alter a replacement student session',
      (tester) async {
        final gate = Completer<void>();
        final oldRepository = _TrackingRepository('DEMO-A101', gate: gate);
        final newRepository = _TrackingRepository('DEMO-B202');
        final session = ValueNotifier(oldRepository);
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          session.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<_TrackingRepository>(
              valueListenable: session,
              builder: (context, repository, _) => Navigator(
                key: ValueKey(repository),
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => StudentShellScreen(
                    repository: repository,
                    name: repository == oldRepository
                        ? 'Sinh viên A'
                        : 'Sinh viên B',
                    roomCode: repository.roomCode,
                    onSignOut: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vòi nước rò rỉ'));
        await tester.pumpAndSettle();
        await _openCancelDialog(tester);
        await tester.enterText(
          find.byType(TextField),
          'Lý do riêng của sinh viên A',
        );
        await tester.tap(find.text('Xác nhận hủy'));
        await tester.pump();
        expect(oldRepository.cancelCalls, 1);

        // Match the production keyed Home lifetime: replacing its identity
        // disposes the old nested navigator, detail and pending-operation UI.
        session.value = newRepository;
        await tester.pumpAndSettle();
        expect(find.byType(RequestDetailScreen), findsNothing);
        expect(find.text('Yêu cầu của tôi'), findsOneWidget);
        final newSessionReads = newRepository.listReads;
        if (fail) {
          gate.completeError(StateError('Lỗi riêng của phiên sinh viên A'));
        } else {
          gate.complete();
        }
        await tester.pumpAndSettle();

        expect(newRepository.cancelCalls, 0);
        expect(newRepository.listReads, newSessionReads);
        expect(
          (await newRepository.fetchRequestDetail('mock-2')).request.status,
          RepairStatus.assigned,
        );
        expect(find.text('Đã hủy yêu cầu sửa chữa'), findsNothing);
        expect(
          find.textContaining('Lý do riêng của sinh viên A'),
          findsNothing,
        );
        expect(
          find.textContaining('Lỗi riêng của phiên sinh viên A'),
          findsNothing,
        );
        expect(find.byType(RequestDetailScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _openAuthenticatedDetail(
  WidgetTester tester,
  _StudentAuthRepository auth,
) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.close();
  });
  await tester.pumpWidget(DormFixApp(authRepository: auth));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Vòi nước rò rỉ'));
  await tester.pumpAndSettle();
  expect(find.byType(RequestDetailScreen), findsOneWidget);
}

Future<void> _openShellDetail(
  WidgetTester tester,
  _TrackingRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StudentShellScreen(
        repository: repository,
        name: 'Sinh viên A',
        roomCode: repository.roomCode,
        onSignOut: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Vòi nước rò rỉ'));
  await tester.pumpAndSettle();
}

Future<void> _openCancelDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Hủy yêu cầu'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  expect(find.text('Xác nhận hủy'), findsOneWidget);
}

void _expectOldCancellationGone() {
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byType(RequestDetailScreen), findsNothing);
  expect(find.text('Xác nhận hủy'), findsNothing);
  expect(find.textContaining('Lý do riêng của sinh viên A'), findsNothing);
  expect(find.textContaining('0987 111 222'), findsNothing);
  expect(find.text('DEMO-A101'), findsNothing);
}

class _TrackingRepository extends MockRequestRepository {
  _TrackingRepository(String room, {this.gate})
    : super(roomCode: room, delay: Duration.zero);

  final Completer<void>? gate;
  int cancelCalls = 0;
  int listReads = 0;
  String? lastReason;

  @override
  Future<List<RepairRequest>> fetchMyRequests() {
    listReads++;
    return super.fetchMyRequests();
  }

  @override
  Future<void> cancelRequest({
    required String requestId,
    required String reason,
  }) async {
    cancelCalls++;
    lastReason = reason;
    if (gate != null) await gate!.future;
    await super.cancelRequest(requestId: requestId, reason: reason);
  }
}

const _studentA = UserProfile(
  id: 'student-a',
  identityCode: 'SV-A',
  fullName: 'Sinh viên A',
  email: 'student-a@example.test',
  phone: '0900000001',
  role: AppRole.student,
  status: 'active',
  room: RoomProfile(
    id: 'room-a',
    code: 'DEMO-A101',
    building: 'A',
    isActive: true,
  ),
  mustChangePassword: false,
  canAccess: true,
);

const _studentB = UserProfile(
  id: 'student-b',
  identityCode: 'SV-B',
  fullName: 'Sinh viên B',
  email: 'student-b@example.test',
  phone: '0900000002',
  role: AppRole.student,
  status: 'active',
  room: RoomProfile(
    id: 'room-b',
    code: 'DEMO-B202',
    building: 'B',
    isActive: true,
  ),
  mustChangePassword: false,
  canAccess: true,
);

class _StudentAuthRepository implements AuthRepository {
  final _changes = StreamController<bool>.broadcast(sync: true);
  UserProfile _profile = _studentA;
  bool _hasSession = true;

  @override
  bool get hasSession => _hasSession;

  @override
  Stream<bool> get sessionChanges => _changes.stream;

  @override
  Future<UserProfile> loadProfile() async => _profile;

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    _hasSession = true;
    _changes.add(true);
    return _profile;
  }

  void expire() {
    _hasSession = false;
    _changes.add(false);
  }

  void switchStudent(UserProfile profile) {
    _profile = profile;
    _hasSession = true;
    _changes.add(true);
  }

  @override
  Future<void> signOut() async => expire();

  @override
  Future<UserProfile> changePassword({required String newPassword}) async =>
      throw UnimplementedError('Password change is outside these tests.');

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      throw UnimplementedError('Password change is outside these tests.');

  Future<void> close() => _changes.close();
}
