import 'dart:async';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_detail.dart';
import 'package:dormfix/features/student_requests/presentation/edit_request_screen.dart';
import 'package:dormfix/features/student_requests/presentation/my_requests_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

const _oldTitle = 'Cửa sổ cần chỉnh sửa';
const _newTitle = 'Cửa sổ cần thay chốt mới';
const _input = NewRepairRequest(
  title: _oldTitle,
  categoryId: 'cat-noithat',
  description: 'Chốt cửa bị kẹt.',
);

class _TrackedRepository extends MockRequestRepository {
  _TrackedRepository()
    : super(
        delay: Duration.zero,
        studentId: 'student-a',
        studentName: 'Sinh viên A',
      );

  int listCalls = 0;
  int detailCalls = 0;
  int updateCalls = 0;
  Completer<void>? writeGate;

  @override
  Future<List<RepairRequest>> fetchMyRequests() {
    listCalls++;
    return super.fetchMyRequests();
  }

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) {
    detailCalls++;
    return super.fetchRequestDetail(requestId);
  }

  @override
  Future<void> updateRequest(EditRepairRequest request) async {
    updateCalls++;
    if (writeGate case final gate?) await gate.future;
    await super.updateRequest(request);
  }
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text(_oldTitle));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Chỉnh sửa yêu cầu'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, _oldTitle),
    _newTitle,
  );
}

Future<void> _save(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pump();
  await tester.scrollUntilVisible(
    find.text('Lưu thay đổi'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(find.text('Lưu thay đổi'));
  await tester.pump();
}

Future<TechnicianTestAuthRepository> _openAuthenticatedEditor(
  WidgetTester tester,
) async {
  final auth = TechnicianTestAuthRepository()..profile = _student;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.dispose();
  });
  await tester.pumpWidget(DormFixApp(authRepository: auth));
  await tester.pumpAndSettle();
  final repository = tester
      .widget<MyRequestsScreen>(find.byType(MyRequestsScreen))
      .repository;
  final created = repository.createRequest(_input);
  await tester.pump(const Duration(milliseconds: 300));
  await created;
  // Returning to the list tab reloads the newly created request.
  await tester.tap(find.text('Cá nhân'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Yêu cầu'));
  await tester.pumpAndSettle();
  await _openEditor(tester);
  return auth;
}

void main() {
  testWidgets(
    'save refreshes detail once and list when returning from detail',
    (tester) async {
      final repository = _TrackedRepository();
      await repository.createRequest(_input);
      await tester.pumpWidget(
        MaterialApp(home: MyRequestsScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      await _openEditor(tester);
      await _save(tester);
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(repository.detailCalls, 2);
      expect(find.byType(EditRequestScreen), findsNothing);
      expect(find.byType(RequestDetailScreen), findsOneWidget);
      expect(find.text(_newTitle), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sinh viên chỉnh sửa thông tin yêu cầu'),
        250,
      );
      expect(find.text('Sinh viên A'), findsWidgets);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(repository.listCalls, 2);
      expect(find.byType(RequestDetailScreen), findsNothing);
      expect(find.text(_newTitle), findsOneWidget);
      expect(find.text(_oldTitle), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final systemBack in [false, true]) {
    testWidgets(
      '${systemBack ? 'system' : 'app bar'} Back waits for a pending save in the student navigator',
      (tester) async {
        await _openAuthenticatedEditor(tester);
        await _save(tester);
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byType(BackButton));
        }
        await tester.pump();
        expect(find.byType(EditRequestScreen), findsOneWidget);
        await tester.pumpAndSettle();

        expect(find.byType(EditRequestScreen), findsNothing);
        expect(find.byType(RequestDetailScreen), findsOneWidget);
        expect(find.text(_newTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('disposed editor skips completion callback and navigation', (
    tester,
  ) async {
    final repository = _TrackedRepository();
    final request = await repository.createRequest(_input);
    final detail = await repository.fetchRequestDetail(request.id);
    final gate = Completer<void>();
    repository.writeGate = gate;
    var callbacks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditRequestScreen(
          repository: repository,
          detail: detail,
          onUpdated: () => callbacks++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester);
    expect(repository.updateCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pumpAndSettle();

    expect(callbacks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'session expiry during save cannot restore the editor or detail',
    (tester) async {
      final auth = await _openAuthenticatedEditor(tester);
      await _save(tester);
      auth.hasSession = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Đăng nhập DormFix'), findsOneWidget);
      expect(find.byType(EditRequestScreen), findsNothing);
      expect(find.byType(RequestDetailScreen), findsNothing);
      expect(find.text(_newTitle), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập DormFix'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

const _student = UserProfile(
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
