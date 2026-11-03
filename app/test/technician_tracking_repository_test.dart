import 'dart:async';
import 'dart:convert';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/technician_jobs/data/technician_tracking_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_tracking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _technicianId = '33333333-3333-4333-8333-333333333333';
const _requestId = '11111111-1111-4111-8111-111111111111';
const _notificationId = '22222222-2222-4222-8222-222222222222';

void main() {
  final clients = <SupabaseClient>[];

  Future<({SupabaseTechnicianTrackingRepository repo, SupabaseClient client})>
  open(
    Future<http.Response> Function(http.Request) handler, {
    bool withSession = true,
    bool expired = false,
  }) async {
    final client = SupabaseClient(
      'https://dormfix.test',
      'sb_publishable_tracking_test',
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
    return (repo: SupabaseTechnicianTrackingRepository(client), client: client);
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  test('history distinguishes current detail from frozen former summaries', () {
    final current = TechnicianWorkHistoryEntry.fromJson(_history());
    final former = TechnicianWorkHistoryEntry.fromJson(
      _history(current: false),
    );
    expect(current.status, RepairStatus.completed);
    expect(current.requestId, _requestId);
    expect(current.assignedAt, DateTime.utc(2026, 11, 1, 2));
    expect(former.canOpenDetail, isFalse);
    expect(former.requestId, isNull);
    expect(former.status, isNull);
    expect(former.title, 'Đèn phòng không sáng');
    expect(former.endedAt, DateTime.utc(2026, 11, 2, 3));
  });

  test('history rejects contradictory access and invalid times/status', () {
    for (final payload in [
      _history()..['can_open_detail'] = 'true',
      _history()..['request_id'] = null,
      _history()..['status'] = 'unknown',
      _history()..['ended_at'] = '2026-11-02T03:00:00Z',
      _history(current: false)..['request_id'] = _requestId,
      _history(current: false)..['status'] = 'completed',
      _history(current: false)..['ended_at'] = '2026-10-01T00:00:00Z',
      _history()..['assigned_at'] = '2026-11-01T09:00:00',
      _history()..remove('status'),
    ]) {
      expect(
        () => TechnicianWorkHistoryEntry.fromJson(payload),
        throwsFormatException,
      );
    }
  });

  test('notification read copy preserves the server access decision', () {
    final item = TechnicianNotification.fromJson(_notification(open: false));
    final read = item.copyWithReadAt(DateTime.utc(2026, 11, 3));
    expect(item.readAt, isNull);
    expect(read.readAt, DateTime.utc(2026, 11, 3));
    expect(read.canOpenDetail, isFalse);
    expect(read.requestId, isNull);
    for (final payload in [
      _notification()..['can_open_detail'] = false,
      _notification(open: false)..['request_id'] = _requestId,
      _notification()..['event_type'] = 'private_future_event',
      _notification()..remove('read_at'),
    ]) {
      expect(
        () => TechnicianNotification.fromJson(payload),
        throwsFormatException,
      );
    }
  });

  test(
    'reads both RPCs with session JWT and preserves server ordering',
    () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        return _json(
          request.url.path.endsWith('technician_list_work_history')
              ? [_history(current: false), _history()]
              : [_notification(open: false), _notification()],
        );
      });
      final history = await opened.repo.fetchWorkHistory();
      final notifications = await opened.repo.fetchNotifications();
      expect(history.map((item) => item.canOpenDetail), [false, true]);
      expect(notifications.map((item) => item.canOpenDetail), [false, true]);
      expect(() => history.clear(), throwsUnsupportedError);
      expect(() => notifications.clear(), throwsUnsupportedError);
      expect(requests.map((request) => request.url.path), [
        '/rest/v1/rpc/technician_list_work_history',
        '/rest/v1/rpc/technician_list_notifications',
      ]);
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), isNull);
        expect(request.headers['authorization'], startsWith('Bearer '));
      }
    },
  );

  test(
    'mark-read sends only notification ID and returns trusted time',
    () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        return _json({
          'id': _notificationId,
          'read_at': '2026-11-03T10:00:00+07:00',
        });
      });
      expect(
        await opened.repo.markNotificationRead(_notificationId),
        DateTime.utc(2026, 11, 3, 3),
      );
      expect(
        requests.single.url.path,
        endsWith('/technician_mark_notification_read'),
      );
      expect(jsonDecode(requests.single.body), {
        'p_notification_id': _notificationId,
      });
    },
  );

  test(
    'wrong mark receipt cannot mark a different local notification',
    () async {
      final opened = await open(
        (_) async =>
            _json({'id': 'another-id', 'read_at': '2026-11-03T03:00:00Z'}),
      );
      await expectLater(
        opened.repo.markNotificationRead(_notificationId),
        throwsA(_denied),
      );
    },
  );

  for (final expired in [false, true]) {
    test(
      'missing/expired session sends no tracking API requests ($expired)',
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
        await expectLater(opened.repo.fetchWorkHistory(), throwsA(_denied));
        await expectLater(opened.repo.fetchNotifications(), throwsA(_denied));
        await expectLater(
          opened.repo.markNotificationRead(_notificationId),
          throwsA(_denied),
        );
        expect(calls, 0);
      },
    );
  }

  for (final operation in ['history', 'notifications', 'mark']) {
    test('discards in-flight $operation after switching accounts', () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final opened = await open((_) async {
        started.complete();
        return response.future;
      });
      final Future<Object?> pending = switch (operation) {
        'history' => opened.repo.fetchWorkHistory(),
        'notifications' => opened.repo.fetchNotifications(),
        _ => opened.repo.markNotificationRead(_notificationId),
      };
      final expectation = expectLater(pending, throwsA(_denied));
      await started.future;
      await opened.client.auth.setInitialSession(
        _session(userId: '44444444-4444-4444-8444-444444444444'),
      );
      response.complete(
        _json(switch (operation) {
          'history' => [_history()],
          'notifications' => [_notification()],
          _ => {'id': _notificationId, 'read_at': '2026-11-03T03:00:00Z'},
        }),
      );
      await expectation;
    });
  }

  test(
    'redacts access failures, malformed contracts and transport errors',
    () async {
      final responses = <Object>[
        _json({
          'code': '42501',
          'message': 'private phone and SQL',
        }, status: 403),
        _json([_history()..['request_id'] = null]),
        http.ClientException('private token and phone'),
      ];
      final opened = await open((_) async {
        final next = responses.removeAt(0);
        if (next is http.Response) return next;
        throw next;
      });
      await expectLater(opened.repo.fetchWorkHistory(), throwsA(_denied));
      for (var i = 0; i < 2; i++) {
        await expectLater(
          opened.repo.fetchWorkHistory(),
          throwsA(
            isA<TechnicianTrackingFailure>().having(
              (failure) => failure.message,
              'safe message',
              'Không thể tải lịch sử công việc. Vui lòng thử lại.',
            ),
          ),
        );
      }
    },
  );
}

final _denied = isA<TechnicianTrackingFailure>().having(
  (failure) => failure.accessDenied,
  'accessDenied',
  isTrue,
);

Map<String, dynamic> _history({bool current = true}) => {
  'assignment_id': 'assignment-1',
  'request_id': current ? _requestId : null,
  'request_code': 'DF000001',
  'title': 'Đèn phòng không sáng',
  'room_code': 'A101',
  'assigned_at': '2026-11-01T09:00:00+07:00',
  'ended_at': current ? null : '2026-11-02T03:00:00Z',
  'status': current ? 'completed' : null,
  'can_open_detail': current,
};

Map<String, dynamic> _notification({bool open = true}) => {
  'id': _notificationId,
  'event_type': open ? 'completed' : 'transferred_out',
  'message': 'Thông báo công việc.',
  'created_at': '2026-11-03T01:00:00Z',
  'read_at': null,
  'request_id': open ? _requestId : null,
  'can_open_detail': open,
};

http.Response _json(Object? body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _session({bool expired = false, String userId = _technicianId}) {
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
      'test-signature';
  return jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'refresh_token': 'tracking-test-refresh',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-11-01T00:00:00Z',
    },
  });
}
