import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/notifications/data/mock_notification_repository.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/history_entry.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_detail.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:dormfix/features/student_confirmation/presentation/request_confirmation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

final _serverRequest = RepairRequest(
  id: '11111111-1111-4111-8111-111111111111',
  requestCode: 'DF008888',
  title: 'Yêu cầu từ backend kiểm thử',
  categoryName: 'Điện',
  roomCode: 'Phòng cũ A101',
  status: RepairStatus.awaitingConfirmation,
  createdAt: DateTime.utc(2026, 11, 9),
);

class _ServerRequests extends MockRequestRepository {
  _ServerRequests({this.empty = false}) : super(delay: Duration.zero);
  final bool empty;
  int listCalls = 0;

  @override
  bool get allowsDemoFallback => false;
  @override
  bool get supportsEditing => false;
  @override
  bool get supportsCancellation => false;
  @override
  bool get supportsConfirmationActions => false;
  @override
  Future<List<RepairRequest>> fetchMyRequests() async {
    listCalls++;
    return empty ? [] : [_serverRequest];
  }

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) async =>
      RequestDetail(
        request: _serverRequest,
        description: 'Mô tả từ backend kiểm thử',
        results: [
          RepairResultItem(
            id: 'result-1',
            technicianName: 'KTV thật',
            content: 'Kết quả từ backend kiểm thử',
            submittedAt: DateTime.utc(2026, 11, 9),
          ),
        ],
        history: [
          HistoryEntry(
            status: RepairStatus.awaitingConfirmation,
            note: 'Lịch sử từ backend kiểm thử',
            createdAt: DateTime.utc(2026, 11, 9),
          ),
        ],
      );
}

Future<TechnicianTestAuthRepository> _open(
  WidgetTester tester,
  _ServerRequests requests,
) async {
  final auth = TechnicianTestAuthRepository()
    ..profile = const UserProfile(
      id: 'student-live-wiring',
      identityCode: 'SV001',
      fullName: 'Sinh viên thật',
      email: 'student@example.com',
      phone: '0901234567',
      role: AppRole.student,
      status: 'active',
      room: RoomProfile(
        id: 'room-new',
        code: 'B202',
        building: 'B',
        isActive: true,
      ),
      mustChangePassword: false,
      canAccess: true,
    );
  await tester.pumpWidget(
    DormFixApp(
      authRepository: auth,
      studentRequestRepository: requests,
      studentNotificationRepository: MockNotificationRepository(
        notifications: [],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets(
    'App uses injected student data and opens real awaiting detail read-only',
    (tester) async {
      final requests = _ServerRequests();
      final auth = await _open(tester, requests);
      expect(find.text(_serverRequest.title), findsOneWidget);
      expect(find.text('Vòi nước rò rỉ'), findsNothing);
      await tester.tap(find.text(_serverRequest.title));
      await tester.pumpAndSettle();
      expect(find.byType(RequestDetailScreen), findsOneWidget);
      expect(find.byType(RequestConfirmationScreen), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Kết quả từ backend kiểm thử'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RequestDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Kết quả từ backend kiểm thử'), findsOneWidget);
      expect(find.text('Chỉnh sửa yêu cầu'), findsNothing);
      expect(find.text('Hủy yêu cầu này'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(requests.listCalls, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.dispose();
    },
  );

  testWidgets(
    'App never invents an awaiting request when real inbox is empty',
    (tester) async {
      final requests = _ServerRequests(empty: true);
      final auth = await _open(tester, requests);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Chờ xác nhận'),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.listCalls, greaterThan(0));
      expect(find.text('DF000004'), findsNothing);
      expect(find.text('Bình nóng lạnh không vào điện'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.dispose();
    },
  );
}
