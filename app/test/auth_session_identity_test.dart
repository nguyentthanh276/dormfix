import 'dart:async';
import 'dart:convert';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/technician_jobs/data/technician_jobs_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userA = '11111111-1111-4111-8111-111111111111';
const _userB = '22222222-2222-4222-8222-222222222222';

void main() {
  final clients = <SupabaseClient>[];

  Future<SupabaseClient> open(
    Future<http.Response> Function(http.Request) handler, {
    String? initialUserId = _userA,
  }) async {
    final client = SupabaseClient(
      'https://dormfix.test',
      'sb_publishable_local_auth_identity_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    clients.add(client);
    if (initialUserId != null) await _setSession(client, initialUserId);
    return client;
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  test('SDK identity changes emit true while same-user token refresh is suppressed', () async {
    final client = await open(
      (_) async => http.Response('', 204),
      initialUserId: null,
    );
    final repository = SupabaseAuthRepository(client);
    final events = <bool>[];
    final subscription = repository.sessionChanges.listen(events.add);

    await _setSession(client, _userA);
    await _drainEvents();
    expect(events, [true]);
    await _setSession(client, _userA, revision: 2);
    await _drainEvents();
    expect(events, [true]);
    await _setSession(client, _userB);
    await _drainEvents();
    expect(events, [true, true]);
    await client.auth.signOut(scope: SignOutScope.local);
    await _drainEvents();
    expect(events, [true, true, false]);

    await subscription.cancel();
  });

  for (final mustChangePassword in [false, true]) {
    test(
      'revalidates a switched SDK user from ${mustChangePassword ? 'password gate' : 'authenticated state'}',
      () async {
        final startedB = Completer<void>();
        final responseB = Completer<http.Response>();
        final client = await open((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_my_profile');
          if (_requestUserId(request) == _userB) {
            startedB.complete();
            return responseB.future;
          }
          return _jsonResponse(
            _profileJson(_userA, mustChangePassword: mustChangePassword),
          );
        });
        final controller = AuthController(
          repository: SupabaseAuthRepository(client),
        );
        await controller.restoreSession();
        expect(controller.profile?.id, _userA);
        expect(
          controller.state,
          mustChangePassword
              ? AuthViewState.changePasswordRequired
              : AuthViewState.authenticated,
        );
        final acceptedB = Completer<void>();
        controller.addListener(() {
          if (controller.profile?.id == _userB && !acceptedB.isCompleted) {
            acceptedB.complete();
          }
        });

        await _setSession(client, _userB);
        await startedB.future;
        expect(controller.state, AuthViewState.checking);
        expect(controller.profile, isNull);
        responseB.complete(_jsonResponse(_profileJson(_userB)));
        await acceptedB.future;

        expect(controller.state, AuthViewState.authenticated);
        expect(controller.profile?.id, _userB);
        controller.dispose();
      },
    );
  }

  test(
    'same-user SDK token refresh does not reload a validated profile',
    () async {
      var profileCalls = 0;
      final client = await open((request) async {
        expect(request.url.path, '/rest/v1/rpc/get_my_profile');
        profileCalls++;
        return _jsonResponse(_profileJson(_userA));
      });
      final controller = AuthController(
        repository: SupabaseAuthRepository(client),
      );
      await controller.restoreSession();
      await _drainEvents();
      expect(profileCalls, 1);

      await _setSession(client, _userA, revision: 2);
      await _drainEvents();

      expect(profileCalls, 1);
      expect(controller.state, AuthViewState.authenticated);
      expect(controller.profile?.id, _userA);
      controller.dispose();
    },
  );

  for (final signOut in [false, true]) {
    test(
      'rejects an old get_my_profile response after SDK ${signOut ? 'logout' : 'account switch'}',
      () async {
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final client = await open((request) async {
          if (request.url.path == '/auth/v1/logout') {
            return http.Response('', 204);
          }
          started.complete();
          return response.future;
        });
        final repository = SupabaseAuthRepository(client);
        final pending = repository.loadProfile();
        final expectation = expectLater(pending, throwsA(_identityFailure));
        await started.future;

        if (signOut) {
          await client.auth.signOut(scope: SignOutScope.local);
        } else {
          await _setSession(client, _userB);
        }
        response.complete(_jsonResponse(_profileJson(_userA)));

        await expectation;
      },
    );
  }

  test(
    'rejects a profile payload whose identity differs from the SDK session',
    () async {
      final client = await open(
        (_) async => _jsonResponse(_profileJson(_userB)),
      );

      await expectLater(
        SupabaseAuthRepository(client).loadProfile(),
        throwsA(_identityFailure),
      );
    },
  );

  test('does not call get_my_profile without an SDK session', () async {
    var networkCalls = 0;
    final client = await open((_) async {
      networkCalls++;
      return _jsonResponse(_profileJson(_userA));
    }, initialUserId: null);

    await expectLater(
      SupabaseAuthRepository(client).loadProfile(),
      throwsA(_identityFailure),
    );
    expect(networkCalls, 0);
  });

  for (final mustChangePassword in [true, false]) {
    test(
      mustChangePassword
          ? 'keeps the password gate when confirmation fails and the profile is still gated'
          : 'reconciles a lost password confirmation with the server profile',
      () async {
        const newPassword = 'New-local-test-password-393';
        final requests = <http.Request>[];
        final client = await open((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/auth/v1/user' => _jsonResponse(_authUserJson(_userA)),
            '/rest/v1/rpc/complete_change_password' => _jsonResponse({
              'code': 'PGRST000',
              'message': 'Confirmation response unavailable',
            }, statusCode: 500),
            '/rest/v1/rpc/get_my_profile' => _jsonResponse(
              _profileJson(_userA, mustChangePassword: mustChangePassword),
            ),
            _ => throw StateError('Unexpected request ${request.url.path}'),
          };
        });
        final accessToken = client.auth.currentSession!.accessToken;
        final change = SupabaseAuthRepository(client)
            .changePassword(newPassword: newPassword);

        if (mustChangePassword) {
          await expectLater(
            change,
            throwsA(
              isA<AuthFailure>()
                  .having(
                    (failure) => failure.signOutRequired,
                    'signOutRequired',
                    isFalse,
                  )
                  .having(
                    (failure) => failure.message,
                    'message',
                    contains('Máy chủ chưa xác nhận đổi mật khẩu'),
                  ),
            ),
          );
        } else {
          final profile = await change;
          expect(profile.id, _userA);
          expect(profile.mustChangePassword, isFalse);
          expect(profile.canAccess, isTrue);
        }

        expect(requests.map((request) => request.url.path), [
          '/auth/v1/user',
          '/rest/v1/rpc/complete_change_password',
          '/rest/v1/rpc/get_my_profile',
        ]);
        expect(requests.map((request) => request.method), [
          'PUT',
          'POST',
          'POST',
        ]);
        expect(jsonDecode(requests.first.body), {'password': newPassword});
        expect(
          requests.map((request) => request.headers['authorization']),
          everyElement('Bearer $accessToken'),
        );
      },
    );
  }

  test(
    'logout during profile loading cannot restore the old protected state',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final client = await open((request) async {
        if (request.url.path == '/auth/v1/logout') {
          return http.Response('', 204);
        }
        started.complete();
        return response.future;
      });
      final controller = AuthController(
        repository: SupabaseAuthRepository(client),
      );
      final restoring = controller.restoreSession();
      await started.future;

      await client.auth.signOut(scope: SignOutScope.local);
      await _drainEvents();
      expect(controller.state, AuthViewState.signedOut);
      expect(controller.profile, isNull);
      response.complete(_jsonResponse(_profileJson(_userA)));
      await restoring;

      expect(controller.state, AuthViewState.signedOut);
      expect(controller.profile, isNull);
      expect(client.auth.currentSession, isNull);
      controller.dispose();
    },
  );

  test(
    'legacy Stream<bool> fakes keep the normal sign-in and restore behavior',
    () async {
      final repository = _LegacyAuthRepository();
      final controller = AuthController(repository: repository);

      await controller.signIn(
        email: 'user@example.com',
        password: 'test-password',
      );
      expect(controller.state, AuthViewState.authenticated);
      expect(repository.signInCalls, 1);
      expect(repository.profileCalls, 0);
      await controller.restoreSession();
      expect(controller.state, AuthViewState.authenticated);
      expect(repository.profileCalls, 1);
      await controller.signOut();
      expect(controller.state, AuthViewState.signedOut);
      expect(controller.profile, isNull);

      controller.dispose();
      await repository.dispose();
    },
  );

  testWidgets(
    'SDK account switch removes cached technician jobs before opening the new Home',
    (tester) async {
      final profileBStarted = Completer<void>();
      final profileBResponse = Completer<http.Response>();
      final profileReads = <String>[];
      final jobReads = <String>[];
      final client = (await tester.runAsync(
        () => open((request) async {
          final userId = _requestUserId(request);
          if (request.url.path == '/rest/v1/rpc/get_my_profile') {
            profileReads.add(userId);
            if (userId == _userB) {
              profileBStarted.complete();
              return profileBResponse.future;
            }
            return _jsonResponse(_profileJson(userId));
          }
          expect(request.url.path, '/rest/v1/rpc/technician_list_jobs');
          jobReads.add(userId);
          return _jsonResponse([_jobJson(userId)]);
        }),
      ))!;
      await tester.pumpWidget(
        DormFixApp(
          authRepository: SupabaseAuthRepository(client),
          technicianJobsRepository: SupabaseTechnicianJobsRepository(client),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Công việc riêng của A').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('Công việc riêng của A'), findsOneWidget);

      await _setSession(client, _userB);
      await _pumpUntil(tester, () => profileBStarted.isCompleted);
      expect(find.text('Công việc riêng của A'), findsNothing);
      expect(find.text('Đang kiểm tra phiên đăng nhập...'), findsOneWidget);
      profileBResponse.complete(_jsonResponse(_profileJson(_userB)));
      await _pumpUntil(
        tester,
        () => find.text('Công việc riêng của B').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.text('Công việc riêng của A'), findsNothing);
      expect(find.text('Công việc riêng của B'), findsOneWidget);
      expect(profileReads, [_userA, _userB]);
      expect(jobReads, [_userA, _userB]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        clients.remove(client);
        await client.dispose();
      });
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

final _identityFailure = isA<AuthFailure>()
    .having((failure) => failure.signOutRequired, 'signOutRequired', isTrue)
    .having((failure) => failure.message, 'message', isNot(contains(_userA)))
    .having((failure) => failure.message, 'message', isNot(contains(_userB)));

Future<void> _drainEvents() => Future<void>.delayed(Duration.zero);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 20 && !condition(); i++) {
    await tester.pump();
    await tester.runAsync(_drainEvents);
  }
  expect(
    condition(),
    isTrue,
    reason: 'Expected SDK and widget events to settle.',
  );
  await tester.pump();
}

Future<void> _setSession(
  SupabaseClient client,
  String userId, {
  int revision = 1,
}) => client.auth.setInitialSession(
  jsonEncode({
    'access_token': _jwt(userId, revision),
    'token_type': 'bearer',
    'refresh_token': 'local-test-refresh-token',
    'user': _authUserJson(userId),
  }),
);

Map<String, Object> _authUserJson(String userId) => {
  'id': userId,
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'aud': 'authenticated',
  'created_at': '2026-10-15T00:00:00Z',
};

String _jwt(String userId, int revision) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiresAt =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': userId, 'role': 'authenticated', 'exp': expiresAt, 'revision': revision})}.'
      'local-test-signature';
}

String _requestUserId(http.Request request) {
  final token = request.headers['authorization']!.substring('Bearer '.length);
  final payload = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
  ) as Map<String, dynamic>;
  return payload['sub'] as String;
}

http.Response _jsonResponse(Object value, {int statusCode = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _profileJson(
  String userId, {
  bool mustChangePassword = false,
}) => {
  'id': userId,
  'identity_code': userId == _userA ? 'KTV001' : 'KTV002',
  'full_name': userId == _userA ? 'Kỹ thuật viên A' : 'Kỹ thuật viên B',
  'email': userId == _userA ? 'a@example.com' : 'b@example.com',
  'phone': '0900000001',
  'role': 'technician',
  'status': 'active',
  'room': null,
  'must_change_password': mustChangePassword,
  'can_access': !mustChangePassword,
};

Map<String, dynamic> _jobJson(String userId) => {
  'id': userId == _userA ? 'job-a' : 'job-b',
  'request_code': userId == _userA ? 'DF000001' : 'DF000002',
  'title': userId == _userA ? 'Công việc riêng của A' : 'Công việc riêng của B',
  'description': 'Kiểm tra đèn trong phòng.',
  'room_code': 'A101',
  'building': 'Tòa A',
  'category_name': 'Điện',
  'status': 'assigned',
  'created_at': '2026-10-15T02:00:00Z',
  'updated_at': '2026-10-15T02:00:00Z',
  'version': 1,
};

class _LegacyAuthRepository implements AuthRepository {
  final _changes = StreamController<bool>.broadcast(sync: true);
  @override
  bool hasSession = false;
  int signInCalls = 0;
  int profileCalls = 0;

  @override
  Stream<bool> get sessionChanges => _changes.stream;

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    hasSession = true;
    _changes.add(true);
    return UserProfile.fromJson(_profileJson(_userA));
  }

  @override
  Future<UserProfile> loadProfile() async {
    profileCalls++;
    return UserProfile.fromJson(_profileJson(_userA));
  }

  @override
  Future<void> signOut() async {
    hasSession = false;
    _changes.add(false);
  }

  @override
  Future<UserProfile> changePassword({required String newPassword}) async =>
      UserProfile.fromJson(_profileJson(_userA));

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  Future<void> dispose() => _changes.close();
}
