import 'dart:async';
import 'dart:convert';

import 'package:dormfix/features/notifications/data/supabase_notification_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _studentId = '33333333-3333-4333-8333-333333333333';
const _otherStudentId = '44444444-4444-4444-8444-444444444444';
const _notificationId = '22222222-2222-4222-8222-222222222222';
const _requestId = '11111111-1111-4111-8111-111111111111';

void main() {
  final clients = <SupabaseClient>[];

  Future<({SupabaseNotificationRepository repo, SupabaseClient client})> open(
    Future<http.Response> Function(http.Request) handler, {
    bool withSession = true,
    bool expired = false,
  }) async {
    final client = SupabaseClient(
      'https://dormfix.test',
      'sb_publishable_notifications_test',
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    clients.add(client);
    if (withSession) {
      await client.auth.setInitialSession(_session(expired: expired));
    }
    return (
      repo: SupabaseNotificationRepository(client: client),
      client: client,
    );
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  test(
    'reads/counts only the signed-in recipient using the session JWT',
    () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        if (request.method == 'HEAD') {
          return http.Response('', 200, headers: {'content-range': '0-1/2'});
        }
        return _json([_notification()]);
      });

      final notifications = await opened.repo.fetchNotifications();
      expect(notifications.single.recipientId, _studentId);
      expect(notifications.single.createdAt, DateTime.utc(2026, 11, 3, 3));
      expect(notifications.single.isRead, isFalse);
      expect(await opened.repo.getUnreadCount(), 2);
      expect(requests.map((request) => request.method), ['GET', 'HEAD']);
      for (final request in requests) {
        expect(request.url.path, '/rest/v1/notifications');
        expect(request.url.queryParameters['recipient_id'], 'eq.$_studentId');
        expect(request.headers['authorization'], startsWith('Bearer '));
      }
      expect(
        requests.first.url.queryParameters['order'],
        'created_at.desc.nullslast,id.desc.nullslast',
      );
      expect(requests.last.url.queryParameters['read_at'], 'is.null');
    },
  );

  test(
    'read mutations use only RPCs and never send a recipient or client time',
    () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        return _json(
          request.url.path.endsWith('student_mark_notification_read')
              ? _singleReceipt()
              : _allReceipt(),
        );
      });

      await opened.repo.markAsRead(_notificationId);
      await opened.repo.markAllAsRead();
      expect(requests.map((request) => request.url.path), [
        '/rest/v1/rpc/student_mark_notification_read',
        '/rest/v1/rpc/student_mark_all_notifications_read',
      ]);
      expect(requests.every((request) => request.method == 'POST'), isTrue);
      expect(jsonDecode(requests.first.body), {
        'p_notification_id': _notificationId,
      });
      expect(jsonDecode(requests.last.body), isNull);
    },
  );

  test('accepts a valid zero-update mark-all receipt', () async {
    final opened = await open((_) async => _json(_allReceipt(count: 0)));
    await opened.repo.markAllAsRead();
  });

  test('rejects mismatched, missing or malformed mutation receipts', () async {
    final invalidSingle = [
      null,
      [],
      _singleReceipt()..['id'] = _otherStudentId,
      _singleReceipt()..remove('read_at'),
      _singleReceipt()..['read_at'] = '2026-11-03T10:00:00',
      _singleReceipt()..['read_at'] = null,
      _singleReceipt()..['extra'] = 'private payload',
    ];
    final invalidAll = [
      null,
      _allReceipt(count: -1),
      _allReceipt()..['updated_count'] = '2',
      _allReceipt()..['updated_count'] = 1.5,
      _allReceipt()..remove('read_at'),
      _allReceipt()..['read_at'] = 'not a timestamp',
      _allReceipt()..['extra'] = 'private payload',
    ];
    final responses = [...invalidSingle, ...invalidAll];
    final opened = await open((_) async => _json(responses.removeAt(0)));
    for (final _ in invalidSingle) {
      await expectLater(
        opened.repo.markAsRead(_notificationId),
        throwsA(_safeFailure('Không thể đánh dấu đã đọc. Vui lòng thử lại.')),
      );
    }
    for (final _ in invalidAll) {
      await expectLater(
        opened.repo.markAllAsRead(),
        throwsA(
          _safeFailure('Không thể đánh dấu tất cả đã đọc. Vui lòng thử lại.'),
        ),
      );
    }
  });

  test('rejects foreign rows and malformed read payloads', () async {
    final responses = [
      [_notification()..['recipient_id'] = _otherStudentId],
      [_notification()..['created_at'] = '2026-11-03T10:00:00'],
      [_notification()..remove('read_at')],
    ];
    final opened = await open((_) async => _json(responses.removeAt(0)));
    await expectLater(opened.repo.fetchNotifications(), throwsA(_denied));
    for (var i = 0; i < 2; i++) {
      await expectLater(
        opened.repo.fetchNotifications(),
        throwsA(_safeFailure('Không thể tải thông báo. Vui lòng thử lại.')),
      );
    }
  });

  for (final expired in [false, true]) {
    test(
      'missing/expired session sends no notification requests ($expired)',
      () async {
        var calls = 0;
        final opened = await open(
          (_) async {
            calls++;
            return _json([]);
          },
          withSession: expired,
          expired: expired,
        );
        await expectLater(opened.repo.fetchNotifications(), throwsA(_denied));
        await expectLater(opened.repo.getUnreadCount(), throwsA(_denied));
        await expectLater(
          opened.repo.markAsRead(_notificationId),
          throwsA(_denied),
        );
        await expectLater(opened.repo.markAllAsRead(), throwsA(_denied));
        expect(calls, 0);
      },
    );
  }

  for (final operation in ['fetch', 'count', 'single', 'all']) {
    for (final switchBack in [false, true]) {
      test(
        'discards in-flight $operation after account switch (back=$switchBack)',
        () async {
          final started = Completer<void>();
          final response = Completer<http.Response>();
          final opened = await open((_) async {
            started.complete();
            return response.future;
          });
          final Future<Object?> pending = switch (operation) {
            'fetch' => opened.repo.fetchNotifications(),
            'count' => opened.repo.getUnreadCount(),
            'single' => opened.repo.markAsRead(_notificationId),
            _ => opened.repo.markAllAsRead(),
          };
          final expectation = expectLater(pending, throwsA(_denied));
          await started.future;
          await opened.client.auth.setInitialSession(
            _session(userId: _otherStudentId),
          );
          if (switchBack) {
            await opened.client.auth.setInitialSession(_session());
          }
          response.complete(
            operation == 'count'
                ? http.Response('', 200, headers: {'content-range': '0-1/2'})
                : _json(switch (operation) {
                    'fetch' => [_notification()],
                    'single' => _singleReceipt(),
                    _ => _allReceipt(),
                  }),
          );
          await expectation;
        },
      );
    }
  }

  test('same-user token renewal keeps a valid response usable', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final opened = await open((_) async {
      started.complete();
      return response.future;
    });
    final pending = opened.repo.fetchNotifications();
    await started.future;
    await opened.client.auth.setInitialSession(
      _session(signature: 'renewed-signature'),
    );
    response.complete(_json([_notification()]));
    expect((await pending).single.id, _notificationId);
  });

  test('redacts permission, not-found, server and transport errors', () async {
    final responses = <Object>[
      for (final code in ['42501', 'P0002', 'PGRST301'])
        _json({'code': code, 'message': 'private SQL and token'}, status: 403),
      _json({'code': 'XX000', 'message': 'private SQL and token'}, status: 500),
      http.ClientException('private token and phone'),
    ];
    final opened = await open((_) async {
      final next = responses.removeAt(0);
      if (next is http.Response) return next;
      throw next;
    });
    for (var i = 0; i < 3; i++) {
      await expectLater(
        opened.repo.markAsRead(_notificationId),
        throwsA(_denied),
      );
    }
    for (var i = 0; i < 2; i++) {
      await expectLater(
        opened.repo.markAsRead(_notificationId),
        throwsA(_safeFailure('Không thể đánh dấu đã đọc. Vui lòng thử lại.')),
      );
    }
  });
}

final _denied = isA<NotificationFailure>().having(
  (failure) => failure.accessDenied,
  'accessDenied',
  isTrue,
);

Matcher _safeFailure(String message) => isA<NotificationFailure>().having(
  (failure) => failure.message,
  'safe message',
  message,
);

Map<String, dynamic> _notification() => {
  'id': _notificationId,
  'recipient_id': _studentId,
  'request_id': _requestId,
  'event_type': 'repair_reported',
  'message': 'Yêu cầu sửa chữa đã có kết quả, vui lòng xác nhận.',
  'created_at': '2026-11-03T10:00:00+07:00',
  'read_at': null,
};

Map<String, dynamic> _singleReceipt() => {
  'id': _notificationId,
  'read_at': '2026-11-03T10:00:00+07:00',
};

Map<String, dynamic> _allReceipt({int count = 2}) => {
  'updated_count': count,
  'read_at': '2026-11-03T03:00:00Z',
};

http.Response _json(Object? body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _session({
  bool expired = false,
  String userId = _studentId,
  String signature = 'test-signature',
}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry =
      DateTime.now()
          .add(expired ? const Duration(hours: -1) : const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  final token =
      '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': userId, 'role': 'authenticated', 'exp': expiry})}.'
      '$signature';
  return jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'refresh_token': 'notifications-test-refresh',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-11-01T00:00:00Z',
    },
  });
}
