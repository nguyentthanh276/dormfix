import 'dart:async';
import 'dart:convert';

import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/admin_accounts/data/admin_account_lifecycle_repository.dart';
import 'package:dormfix/features/admin_accounts/data/admin_account_management_repository.dart';
import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/account_lifecycle_action.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _admin = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _room = '44444444-4444-4444-8444-444444444444';
const _temporaryPassword = 'TestOnly-Pass92';

void main() {
  Future<SupabaseClient> client(
    FutureOr<http.Response> Function(http.Request) handler, {
    bool signedIn = true,
  }) async {
    final client = SupabaseClient(
      'https://dormfix.test',
      'sb_publishable_account_test',
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
    addTearDown(client.dispose);
    if (signedIn) await client.auth.setInitialSession(_session());
    return client;
  }

  test('creates a student via authorized Edge only and accepts its password-gated profile', () async {
    var calls = 0;
    final supabase = await client((request) {
      calls++;
      expect(request.url.path, '/functions/v1/admin-create-account');
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer ${_token(_admin)}');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.remove('temporary_password') == _temporaryPassword, isTrue);
      expect(body, {
        'identity_code': 'SV100',
        'full_name': 'Sinh viên kiểm thử',
        'email': 'sample@example.com',
        'phone': '0901234567',
        'role': 'student',
        'room_id': _room,
      });
      return _json({'account': _account()}, status: 201);
    });
    final AdminAccountManagementRepository repository =
        SupabaseAdminAccountsRepository(supabase);
    final details = await repository.createAccount(_input());
    expect(details.id, _accountId);
    expect(details.role, AppRole.student);
    expect(details.status, AccountStatus.active);
    expect(details.roomId, _room);
    expect(details.mustChangePassword, isTrue);
    expect(calls, 1);
  });

  test('technician provisioning has no room', () async {
    final supabase = await client((request) {
      final body = jsonDecode(request.body);
      expect(body['role'], 'technician');
      expect(body.containsKey('room_id'), isTrue);
      expect(body['room_id'], isNull);
      return _json({'account': _account(role: AppRole.technician)});
    });
    final repository = SupabaseAdminAccountsRepository(supabase);
    expect(
      (await repository.createAccount(
        _input(role: AppRole.technician, roomId: null),
      )).roomId,
      isNull,
    );
  });

  test(
    'detail preserves identity and update sends only editable profile fields',
    () async {
      final calls = <List<Object?>>[];
      final supabase = await client((request) {
        final function = request.url.pathSegments.last;
        expect(request.url.path, '/rest/v1/rpc/$function');
        expect(request.headers['authorization'], 'Bearer ${_token(_admin)}');
        calls.add([function, jsonDecode(request.body)]);
        if (function == 'admin_get_account') return _json(_account());
        return _json({..._account(fullName: 'Tên mới'), 'changed': false});
      });
      final repository = SupabaseAdminAccountsRepository(supabase);
      final original = await repository.fetchDetails(' sv100 ');
      expect(original.identityCode, 'SV100');
      final updated = await repository.updateAccount(
        UpdateManagedAccount(
          id: original.id,
          fullName: ' Tên mới ',
          phone: '090.123.4567',
          roomId: original.roomId,
        ),
      );
      expect(updated.fullName, 'Tên mới');
      expect(updated.email, original.email);
      expect(updated.mustChangePassword, isTrue);
      expect(calls, [
        [
          'admin_get_account',
          {'p_identity_code': 'sv100'},
        ],
        [
          'admin_update_account',
          {
            'p_account_id': _accountId,
            'p_full_name': 'Tên mới',
            'p_phone': '0901234567',
            'p_room_id': _room,
          },
        ],
      ]);
    },
  );

  test('invalid create and update inputs stop before transport', () async {
    var calls = 0;
    final supabase = await client((_) {
      calls++;
      return _json({});
    });
    final repository = SupabaseAdminAccountsRepository(supabase);
    for (final input in [
      _input(role: AppRole.admin, roomId: null),
      _input(role: AppRole.technician),
      _input(roomId: null),
      _input(roomId: 'not-a-room-id'),
      _input(email: 'not-an-email'),
      _input(phone: 'invalid'),
      _input(password: 'short'),
      _input(password: '      '),
      _input(password: 'á' * 37),
    ]) {
      await expectLater(repository.createAccount(input), throwsA(_failure));
    }
    await expectLater(
      repository.updateAccount(
        const UpdateManagedAccount(
          id: 'invalid',
          fullName: 'name',
          phone: '0901234567',
        ),
      ),
      throwsA(_failure),
    );
    expect(calls, 0);
  });

  test('no session stops account list, details and writes', () async {
    var calls = 0;
    final supabase = await client((_) {
      calls++;
      return _json({});
    }, signedIn: false);
    final repository = SupabaseAdminAccountsRepository(supabase);
    await expectLater(
      repository.list(query: '', offset: 0, limit: 20),
      throwsA(_denied),
    );
    await expectLater(repository.fetchDetails('SV100'), throwsA(_denied));
    await expectLater(repository.createAccount(_input()), throwsA(_denied));
    await expectLater(repository.updateAccount(_update), throwsA(_denied));
    await expectLater(
      repository.changeAccountStatus(
        accountId: _accountId,
        expectedStatus: AccountStatus.active,
        action: AccountLifecycleAction.lock,
        reason: 'Lý do',
      ),
      throwsA(_denied),
    );
    await expectLater(
      repository.resetTemporaryPassword(
        accountId: _accountId,
        expectedStatus: AccountStatus.active,
        temporaryPassword: _temporaryPassword,
      ),
      throwsA(_denied),
    );
    expect(calls, 0);
  });

  test(
    'status actions pin the Admin JWT and send state, reason and room',
    () async {
      const changes = [
        (AccountLifecycleAction.lock, AccountStatus.active, 'Tạm nghỉ', null),
        (AccountLifecycleAction.unlock, AccountStatus.locked, null, null),
        (AccountLifecycleAction.revoke, AccountStatus.locked, 'Rời KTX', null),
        (AccountLifecycleAction.restore, AccountStatus.revoked, null, _room),
      ];
      var call = 0;
      final supabase = await client((request) {
        final (action, status, reason, room) = changes[call++];
        expect(request.url.path, '/rest/v1/rpc/admin_change_account_status');
        expect(request.headers['authorization'], 'Bearer ${_token(_admin)}');
        expect(jsonDecode(request.body), {
          'p_account_id': _accountId,
          'p_expected_status': status.databaseValue,
          'p_action': action.name,
          'p_reason': reason,
          'p_room_id': room,
        });
        return _json({
          ..._account(),
          'status': action.resultingStatus.databaseValue,
          'changed': true,
        });
      });
      final AdminAccountLifecycleRepository repository =
          SupabaseAdminAccountsRepository(supabase);
      for (final (action, status, reason, room) in changes) {
        final account = await repository.changeAccountStatus(
          accountId: _accountId,
          expectedStatus: status,
          action: action,
          reason: reason == null ? null : '  $reason  ',
          roomId: room,
        );
        expect(account.status, action.resultingStatus);
        expect(account.roomId, _room);
      }
      expect(call, changes.length);
    },
  );

  test(
    'reset sends the temporary password to Edge only and checks the gate',
    () async {
      var call = 0;
      final supabase = await client((request) {
        call++;
        expect(request.url.path, '/functions/v1/admin-reset-account-password');
        expect(request.headers['authorization'], 'Bearer ${_token(_admin)}');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.remove('temporary_password') == _temporaryPassword, isTrue);
        expect(body, {'account_id': _accountId, 'expected_status': 'locked'});
        return _json({
          'account': {
            ..._account(),
            'status': 'locked',
            'must_change_password': call == 1,
          },
        });
      });
      final repository = SupabaseAdminAccountsRepository(supabase);
      Future<ManagedAccountDetails> reset() =>
          repository.resetTemporaryPassword(
            accountId: _accountId,
            expectedStatus: AccountStatus.locked,
            temporaryPassword: _temporaryPassword,
          );
      expect((await reset()).mustChangePassword, isTrue);
      await expectLater(reset(), throwsA(_uncertain));
      expect(call, 2);
    },
  );

  test('invalid lifecycle drafts stop before transport', () async {
    var call = 0;
    final supabase = await client((_) {
      call++;
      return _json({});
    });
    final repository = SupabaseAdminAccountsRepository(supabase);
    for (final note in ['  ', 'ế' * 501]) {
      await expectLater(
        repository.changeAccountStatus(
          accountId: _accountId,
          expectedStatus: AccountStatus.active,
          action: AccountLifecycleAction.revoke,
          reason: note,
        ),
        throwsA(
          _failure.having(
            (e) => e.message.toLowerCase(),
            'reason error',
            contains('lý do'),
          ),
        ),
      );
    }
    await expectLater(
      repository.resetTemporaryPassword(
        accountId: _accountId,
        expectedStatus: AccountStatus.revoked,
        temporaryPassword: _temporaryPassword,
      ),
      throwsA(_conflict),
    );
    await expectLater(
      repository.resetTemporaryPassword(
        accountId: _accountId,
        expectedStatus: AccountStatus.active,
        temporaryPassword: 'ế' * 37,
      ),
      throwsA(_failure),
    );
    expect(call, 0);
  });

  test(
    'lifecycle conflicts and uncertain reset results are sanitized',
    () async {
      final replies = [
        for (final code in ['ACCOUNT_HAS_OPEN_JOBS', 'ACCOUNT_STATUS_CHANGED'])
          _json({
            'code': 'P0001',
            'message': code,
            'details': _temporaryPassword,
          }, status: 400),
        _json({'error': 'ACCOUNT_RESET_IN_PROGRESS'}, status: 409),
        _json({'error': 'ACCOUNT_NOT_FOUND'}, status: 404),
        _json({'error': 'INVALID_TEMPORARY_PASSWORD'}, status: 422),
        _json({
          'error': 'ACCOUNT_RESET_NOT_CONFIRMED',
          'details': _temporaryPassword,
        }, status: 502),
      ];
      final supabase = await client((_) => replies.removeAt(0));
      final repository = SupabaseAdminAccountsRepository(supabase);
      for (final message in ['chưa hoàn tất', 'không còn phù hợp']) {
        await expectLater(
          repository.changeAccountStatus(
            accountId: _accountId,
            expectedStatus: AccountStatus.active,
            action: AccountLifecycleAction.revoke,
            reason: 'Rời KTX',
          ),
          throwsA(
            _conflict.having(
              (e) => e.message,
              'explanation',
              contains(message),
            ),
          ),
        );
      }
      for (final matcher in [
        _conflict.having(
          (e) => e.message,
          'reset pending',
          contains('đang được đặt lại'),
        ),
        _conflict.having(
          (e) => e.message,
          'not found',
          contains('Không tìm thấy'),
        ),
        _failure.having(
          (e) => e.message,
          'invalid password',
          contains('Mật khẩu tạm'),
        ),
        _uncertain,
      ]) {
        await expectLater(
          repository.resetTemporaryPassword(
            accountId: _accountId,
            expectedStatus: AccountStatus.active,
            temporaryPassword: _temporaryPassword,
          ),
          throwsA(matcher),
        );
      }
      expect(replies, isEmpty);
    },
  );

  test('Edge and SQL errors use allowlisted safe messages and flags', () async {
    final replies = [
      _json({
        'error': 'ADMIN_ACCESS_DENIED',
        'details': _temporaryPassword,
      }, status: 403),
      _json({'error': 'ACCOUNT_EMAIL_ALREADY_EXISTS'}, status: 409),
      _json({'error': 'ACCOUNT_IDENTITY_ALREADY_EXISTS'}, status: 409),
      _json({'error': 'ACTIVE_ROOM_REQUIRED'}, status: 409),
      _json({'error': 'INVALID_TEMPORARY_PASSWORD'}, status: 422),
      _json({'error': 'ACCOUNT_SERVICE_UNAVAILABLE'}, status: 503),
      _json({
        'error': 'ACCOUNT_CREATE_NOT_CONFIRMED',
        'details': _temporaryPassword,
      }, status: 502),
      _json({'code': 'P0002', 'message': 'ACCOUNT_NOT_FOUND'}, status: 404),
      _json({
        'code': '22023',
        'message': 'ACTIVE_STUDENT_ROOM_REQUIRED',
      }, status: 400),
      _json({'code': '42501', 'message': _temporaryPassword}, status: 403),
    ];
    final supabase = await client((_) => replies.removeAt(0));
    final repository = SupabaseAdminAccountsRepository(supabase);
    for (final matcher in [
      _denied,
      _failure.having((e) => e.message, 'email duplicate', contains('Email')),
      _failure.having(
        (e) => e.message,
        'ID duplicate',
        contains('Mã định danh'),
      ),
      _conflict,
      _failure.having(
        (e) => e.message,
        'password guidance',
        contains('Mật khẩu tạm'),
      ),
      _failure.having((e) => e.uncertain, 'before write', isFalse),
      _uncertain,
    ]) {
      await expectLater(repository.createAccount(_input()), throwsA(matcher));
    }
    await expectLater(repository.fetchDetails('SV100'), throwsA(_conflict));
    await expectLater(repository.updateAccount(_update), throwsA(_conflict));
    await expectLater(repository.updateAccount(_update), throwsA(_denied));
    expect(replies, isEmpty);
  });

  test('missing or mismatched write receipts and network errors require reconciliation', () async {
    var call = 0;
    final supabase = await client((_) {
      call++;
      return switch (call) {
        1 => _json({
          'account': {..._account(), 'must_change_password': false},
        }),
        2 => _json({'account': _account(fullName: 'wrong name')}),
        3 => _json(_account()),
        4 => throw http.ClientException(_temporaryPassword),
        _ => throw StateError('Unexpected RPC.'),
      };
    });
    final repository = SupabaseAdminAccountsRepository(supabase);
    await expectLater(repository.createAccount(_input()), throwsA(_uncertain));
    await expectLater(repository.createAccount(_input()), throwsA(_uncertain));
    await expectLater(repository.updateAccount(_update), throwsA(_uncertain));
    await expectLater(repository.createAccount(_input()), throwsA(_uncertain));
    expect(call, 4);
  });

  test('ignores Edge result after Admin switches away and back during provisioning', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final supabase = await client((request) {
      expect(request.headers['authorization'], 'Bearer ${_token(_admin)}');
      started.complete();
      return response.future;
    });
    final repository = SupabaseAdminAccountsRepository(supabase);
    final pending = repository.createAccount(_input());
    final denied = expectLater(pending, throwsA(_denied));
    await started.future;
    await supabase.auth.setInitialSession(_session(userId: _other));
    await supabase.auth.setInitialSession(_session());
    response.complete(_json({'account': _account()}));
    await denied;
  });
}

final _failure = isA<AdminAccountsFailure>().having(
  (e) => e.toString().contains(_temporaryPassword),
  'contains raw password',
  isFalse,
);
final _denied = _failure.having((e) => e.accessDenied, 'accessDenied', isTrue);
final _conflict = _failure.having((e) => e.conflict, 'conflict', isTrue);
final _uncertain = _failure.having((e) => e.uncertain, 'uncertain', isTrue);

const _update = UpdateManagedAccount(
  id: _accountId,
  fullName: 'Sinh viên kiểm thử',
  phone: '0901234567',
  roomId: _room,
);

CreateManagedAccount _input({
  AppRole role = AppRole.student,
  String? roomId = _room,
  String email = ' Sample@Example.COM ',
  String phone = ' 090-123-4567 ',
  String password = _temporaryPassword,
}) => CreateManagedAccount(
  role: role,
  identityCode: ' SV100 ',
  fullName: ' Sinh viên kiểm thử ',
  email: email,
  phone: phone,
  temporaryPassword: password,
  roomId: roomId,
);

Map<String, dynamic> _account({
  AppRole role = AppRole.student,
  String fullName = 'Sinh viên kiểm thử',
}) => {
  'id': _accountId,
  'identity_code': 'SV100',
  'full_name': fullName,
  'email': 'sample@example.com',
  'phone': '0901234567',
  'role': role.databaseValue,
  'status': 'active',
  'room_id': role == AppRole.student ? _room : null,
  'must_change_password': true,
};

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _session({String userId = _admin}) => jsonEncode({
  'access_token': _token(userId),
  'token_type': 'bearer',
  'refresh_token': 'test-refresh',
  'user': {
    'id': userId,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-11-09T00:00:00Z',
  },
});

String _token(String userId) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return "${part({'alg': 'HS256'})}.${part({'sub': userId, 'exp': 2147483647})}.accounts-test";
}
