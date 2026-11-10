import 'dart:async';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/app/startup_page.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/profile/data/profile_repository.dart';
import 'package:dormfix/features/profile/presentation/profile_page.dart';
import 'package:dormfix/features/student_requests/presentation/create_request_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('personal tab mounts lazily and refreshes on activation', (
    tester,
  ) async {
    final auth = _StudentAuthRepository();
    final profiles = _CountingProfileRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    });
    await tester.pumpWidget(
      DormFixApp(authRepository: auth, profileRepository: profiles),
    );
    await tester.pumpAndSettle();
    expect(profiles.reads, 0);
    expect(find.byType(ProfilePage, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Thông báo'));
    await tester.pumpAndSettle();
    expect(profiles.reads, 0);
    expect(find.byType(ProfilePage, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Cá nhân'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    await tester.tap(find.text('Yêu cầu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cá nhân'));
    await tester.pumpAndSettle();
    expect(profiles.reads, 1);
  });

  testWidgets('expiry removes the create draft and its discard dialog', (
    tester,
  ) async {
    final auth = _StudentAuthRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    });
    await tester.pumpWidget(DormFixApp(authRepository: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('student-create-request')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('titleField')),
      'Private draft',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    auth.expire();
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập DormFix'), findsOneWidget);
    expect(find.byType(CreateRequestScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Private draft'), findsNothing);
    expect(find.byType(CreateRequestScreen), findsNothing);
  });

  testWidgets(
    'session expiry removes student detail and back cannot restore it',
    (tester) async {
      final auth = _StudentAuthRepository();
      await _openStudentDetail(tester, auth);

      auth.expire();
      await tester.pumpAndSettle();

      await _expectSignedOutWithoutDetail(tester);
    },
  );

  testWidgets('session expiry removes the open student photo dialog', (
    tester,
  ) async {
    final auth = _StudentAuthRepository();
    await _openStudentDetail(tester, auth);
    await _openStudentPhoto(tester);

    auth.expire();
    await tester.pumpAndSettle();

    _expectNoStudentPhoto();
    await _expectSignedOutWithoutDetail(tester);
    _expectNoStudentPhoto();
  });

  testWidgets(
    'explicit logout removes student detail and back cannot restore it',
    (tester) async {
      final auth = _StudentAuthRepository();
      await _openStudentDetail(tester, auth);
      final startup = tester.widget<StartupPage>(
        find.byType(StartupPage, skipOffstage: false),
      );

      await startup.controller.signOut();
      await tester.pumpAndSettle();

      expect(auth.signOutCalls, 1);
      await _expectSignedOutWithoutDetail(tester);
    },
  );

  testWidgets(
    'switching students discards old detail and the old room repository',
    (tester) async {
      final auth = _StudentAuthRepository();
      await _openStudentDetail(tester, auth);

      // An immediately available new profile can skip rendering the intermediate
      // checking frame. The student Home must still reset by authenticated ID.
      auth.switchStudent(_studentB);
      await tester.pumpAndSettle();

      expect(find.byType(RequestDetailScreen), findsNothing);
      expect(find.text('Tiến trình xử lý'), findsNothing);
      expect(find.text('DEMO-A101'), findsNothing);
      expect(find.text('Yêu cầu của tôi'), findsOneWidget);
      expect(find.text('DEMO-B202'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RequestDetailScreen), findsNothing);
      expect(find.text('DEMO-A101'), findsNothing);
      expect(find.text('DEMO-B202'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      expect(find.text('Sinh viên B'), findsOneWidget);
      expect(find.text('DEMO-B202'), findsOneWidget);
      expect(find.text('Sinh viên A'), findsNothing);
    },
  );

  testWidgets('switching students removes the previous student photo dialog', (
    tester,
  ) async {
    final auth = _StudentAuthRepository();
    await _openStudentDetail(tester, auth);
    await _openStudentPhoto(tester);

    auth.switchStudent(_studentB);
    await tester.pumpAndSettle();

    _expectNoStudentPhoto();
    expect(find.byType(RequestDetailScreen), findsNothing);
    expect(find.text('DEMO-A101'), findsNothing);
    expect(find.text('Yêu cầu của tôi'), findsOneWidget);
    expect(find.text('DEMO-B202'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    _expectNoStudentPhoto();
    expect(find.byType(RequestDetailScreen), findsNothing);
    expect(find.text('DEMO-B202'), findsOneWidget);
  });

  for (final systemBack in [false, true]) {
    testWidgets(
      '${systemBack ? 'system' : 'app bar'} back returns from student detail to the request list',
      (tester) async {
        await _openStudentDetail(tester, _StudentAuthRepository());

        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byType(BackButton));
        }
        await tester.pumpAndSettle();

        expect(find.byType(RequestDetailScreen), findsNothing);
        expect(find.text('Yêu cầu của tôi'), findsOneWidget);
        expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
      },
    );
  }
}

Future<void> _openStudentPhoto(WidgetTester tester) async {
  final photo = find.text('anh_voi_nuoc_ro_ri_1.jpg');
  await tester.scrollUntilVisible(photo, 250);
  await tester.tap(photo);
  await tester.pumpAndSettle();

  expect(find.byType(AlertDialog), findsOneWidget);
  expect(find.text('Tệp: anh_voi_nuoc_ro_ri_1.jpg'), findsOneWidget);
}

void _expectNoStudentPhoto() {
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.textContaining('anh_voi_nuoc_ro_ri_1.jpg'), findsNothing);
}

Future<void> _openStudentDetail(
  WidgetTester tester,
  _StudentAuthRepository auth,
) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.close();
  });
  await tester.pumpWidget(DormFixApp(authRepository: auth));
  await tester.pumpAndSettle();
  expect(find.text('Yêu cầu của tôi'), findsOneWidget);

  await tester.tap(find.text('Vòi nước rò rỉ'));
  await tester.pumpAndSettle();
  expect(find.byType(RequestDetailScreen), findsOneWidget);
  expect(find.text('Tiến trình xử lý'), findsOneWidget);
  expect(find.text('DEMO-A101'), findsOneWidget);
}

Future<void> _expectSignedOutWithoutDetail(WidgetTester tester) async {
  expect(find.text('Đăng nhập DormFix'), findsOneWidget);
  expect(find.byType(RequestDetailScreen), findsNothing);
  expect(find.text('Tiến trình xử lý'), findsNothing);
  expect(find.text('DEMO-A101'), findsNothing);
  expect(find.textContaining('0987 111 222'), findsNothing);

  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  expect(find.text('Đăng nhập DormFix'), findsOneWidget);
  expect(find.byType(RequestDetailScreen), findsNothing);
  expect(find.text('DEMO-A101'), findsNothing);
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

class _CountingProfileRepository implements ProfileRepository {
  int reads = 0;

  @override
  Future<UserProfile> getProfile() async {
    reads++;
    return _studentA;
  }

  @override
  Future<UserProfile> updatePhone({required String phone}) async =>
      _studentA.copyWith(phone: phone);
}

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
  int signOutCalls = 0;

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
  Future<void> signOut() async {
    signOutCalls++;
    expire();
  }

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
