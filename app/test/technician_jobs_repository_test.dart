import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/technician_jobs/data/technician_jobs_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_job.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _requestId = '11111111-1111-4111-8111-111111111111';
const _attachmentId = '22222222-2222-4222-8222-222222222222';
const _technicianId = '33333333-3333-4333-8333-333333333333';
const _storagePath = 'requests/$_requestId/$_attachmentId.png';
const _apiKey = 'sb_publishable_local_repository_test';

void main() {
  final clients = <SupabaseClient>[];

  Future<
    ({
      SupabaseTechnicianJobsRepository repository,
      SupabaseClient client,
      String token,
    })
  >
  open(
    Future<http.Response> Function(http.Request) handler, {
    bool withSession = true,
    bool expired = false,
  }) async {
    final token = _jwt(expired: expired);
    final client = SupabaseClient(
      'https://dormfix.test',
      _apiKey,
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
      await client.auth.setInitialSession(_sessionJson(token));
    }
    return (
      repository: SupabaseTechnicianJobsRepository(client),
      client: client,
      token: token,
    );
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  group('technician payloads', () {
    test('keeps Vietnamese and converts timestamp offsets to UTC', () {
      final detail = TechnicianJobDetail.fromJson(_detailJson());

      expect(detail.job.title, 'Đèn phòng không sáng');
      expect(detail.job.description, 'Đèn nhấp nháy, cần kiểm tra dây điện.');
      expect(detail.job.roomCode, 'A101');
      expect(detail.job.building, 'Tòa A');
      expect(detail.job.categoryName, 'Điện');
      expect(detail.job.status, RepairStatus.awaitingRework);
      expect(detail.job.version, 4);
      expect(detail.job.createdAt, DateTime.utc(2026, 10, 15, 2, 30));
      expect(detail.job.createdAt.isUtc, isTrue);
      expect(detail.job.updatedAt.isUtc, isTrue);
      expect(detail.studentName, 'Nguyễn Thị Ánh');
      expect(detail.studentPhone, '0900000001');
      expect(detail.results.single.technicianName, 'Trần Văn Bình');
      expect(detail.results.single.submittedAt.isUtc, isTrue);
      expect(detail.feedback.single.reason, 'Đèn vẫn nhấp nháy');
      expect(detail.feedback.single.authorName, 'Nguyễn Thị Ánh');
      expect(detail.history.single.action, 'rework_requested');
      expect(detail.history.single.actorName, 'Nguyễn Thị Ánh');
      expect(detail.history.single.oldStatus, 'awaiting_confirmation');
      expect(detail.history.single.note, isNull);
      expect(detail.assignments.single.assignedByName, 'Quản lý ký túc xá');
      expect(detail.assignments.single.endedAt, isNull);
      expect(detail.assignments.single.transferReason, isNull);
      expect(detail.attachments.single.resultId, isNull);
      expect(detail.attachments.single.feedbackId, isNull);
    });

    test('rejects unknown statuses and incomplete or mistyped job fields', () {
      for (final json in [
        _jobJson(status: 'future_status'),
        _jobJson()..remove('description'),
        _jobJson()..['version'] = '4',
        _jobJson()..['created_at'] = '2026-10-15T09:30:00',
      ]) {
        expect(() => TechnicianJob.fromJson(json), throwsFormatException);
      }
    });

    test('requires the detail sections and required student contact', () {
      for (final json in [
        _detailJson()..remove('history'),
        _detailJson()..['results'] = <String, dynamic>{},
        _detailJson()..['student'] = {'full_name': 'Sinh viên', 'phone': null},
        _detailJson()..['attachments'] = [null],
      ]) {
        expect(() => TechnicianJobDetail.fromJson(json), throwsFormatException);
      }
    });

    test('rejects invalid attachment metadata instead of defaulting it', () {
      for (final json in [
        _attachmentJson()..['size_bytes'] = 0,
        _attachmentJson()..['size_bytes'] = 5242881,
        _attachmentJson()..['mime_type'] = 'text/html',
        _attachmentJson()..['feedback_id'] = 7,
        _attachmentJson()
          ..['result_id'] = 'result-1'
          ..['feedback_id'] = 'feedback-1',
      ]) {
        expect(() => JobAttachment.fromJson(json), throwsFormatException);
      }
    });
  });

  group('real Supabase read contract', () {
    test('calls the list RPC with the JWT and parses every status', () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        return _jsonResponse([
          for (final status in RepairStatus.values)
            _jobJson(status: status.databaseValue),
        ]);
      });

      final jobs = await opened.repository.fetchJobs();

      expect(jobs.map((job) => job.status), RepairStatus.values);
      expect(
        jobs.any((job) => job.status == RepairStatus.awaitingRework),
        isTrue,
      );
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/technician_list_jobs');
      expect(jsonDecode(request.body), isNull);
      _expectAuthenticated(request, opened.token);
    });

    test('returns an empty real list without inserting mock jobs', () async {
      final opened = await open((_) async => _jsonResponse([]));

      expect(await opened.repository.fetchJobs(), isEmpty);
    });

    test('passes only p_request_id and parses all detail sections', () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        return _jsonResponse(_detailJson());
      });

      final detail = await opened.repository.fetchJobDetail(_requestId);

      expect(detail.job.id, _requestId);
      expect(detail.studentName, 'Nguyễn Thị Ánh');
      expect(detail.attachments, hasLength(1));
      expect(detail.results, hasLength(1));
      expect(detail.feedback, hasLength(1));
      expect(detail.history, hasLength(1));
      expect(detail.assignments, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/technician_get_job');
      expect(jsonDecode(request.body), {'p_request_id': _requestId});
      _expectAuthenticated(request, opened.token);
    });

    test(
      'fails closed if the returned detail belongs to another job',
      () async {
        final opened = await open(
          (_) async => _jsonResponse(
            _detailJson()
              ..['request'] = (_jobJson()..['id'] = 'another-request'),
          ),
        );

        await expectLater(
          opened.repository.fetchJobDetail(_requestId),
          throwsA(_deniedFailure),
        );
      },
    );

    for (final useDetail in [false, true]) {
      for (final signOut in [false, true]) {
        test(
          'discards an in-flight ${useDetail ? 'detail' : 'list'} after ${signOut ? 'logout' : 'account switch'}',
          () async {
            final started = Completer<void>();
            final response = Completer<http.Response>();
            final opened = await open((request) async {
              if (request.url.path == '/auth/v1/logout') {
                return http.Response('', 204);
              }
              started.complete();
              return response.future;
            });
            final pending = useDetail
                ? opened.repository.fetchJobDetail(_requestId)
                : opened.repository.fetchJobs();
            final expectation = expectLater(pending, throwsA(_deniedFailure));
            await started.future;

            if (signOut) {
              await opened.client.auth.signOut(scope: SignOutScope.local);
            } else {
              const otherId = '44444444-4444-4444-8444-444444444444';
              await opened.client.auth.setInitialSession(
                _sessionJson(
                  _jwt(expired: false, userId: otherId),
                  userId: otherId,
                ),
              );
            }
            response.complete(
              _jsonResponse(useDetail ? _detailJson() : [_jobJson()]),
            );

            await expectation;
          },
        );
      }
    }

    test(
      'keeps an in-flight response when the same user refreshes a token',
      () async {
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final opened = await open((_) async {
          started.complete();
          return response.future;
        });
        final pending = opened.repository.fetchJobs();
        await started.future;
        await opened.client.auth.setInitialSession(
          _sessionJson('${_jwt(expired: false)}-refreshed'),
        );
        response.complete(_jsonResponse([_jobJson()]));

        expect(await pending, hasLength(1));
      },
    );

    for (final withSession in [false, true]) {
      test(
        'sends no request for a ${withSession ? 'expired' : 'missing'} session',
        () async {
          var networkCalls = 0;
          final opened = await open(
            (_) async {
              networkCalls++;
              return _jsonResponse([]);
            },
            withSession: withSession,
            expired: withSession,
          );

          await expectLater(
            opened.repository.fetchJobs(),
            throwsA(_deniedFailure),
          );
          await expectLater(
            opened.repository.fetchJobDetail(_requestId),
            throwsA(_deniedFailure),
          );
          await expectLater(
            opened.repository.fetchAttachment(
              _requestId,
              JobAttachment.fromJson(_attachmentJson()),
            ),
            throwsA(_deniedFailure),
          );
          expect(networkCalls, 0);
        },
      );
    }

    for (final code in [
      '28000',
      '42501',
      'P0002',
      'PGRST301',
      'PGRST303',
      '401',
      '403',
    ]) {
      test(
        'maps $code to access denial without private server details',
        () async {
          final opened = await open(
            (_) async => _jsonResponse({
              'code': code,
              'message': 'private student phone 0900000001, $_storagePath',
              'details': 'private SQL assignment detail',
              'hint': 'private hint',
            }, status: code == '401' ? 401 : 403),
          );

          await expectLater(
            opened.repository.fetchJobs(),
            throwsA(_deniedFailure),
          );
        },
      );
    }

    test(
      'recognizes JWT expiration even with an unexpected service code',
      () async {
        final opened = await open(
          (_) async => _jsonResponse({
            'code': 'OTHER_CODE',
            'message': 'JWT expired: private token information',
          }, status: 401),
        );

        await expectLater(
          opened.repository.fetchJobs(),
          throwsA(_deniedFailure),
        );
      },
    );

    test('sanitizes transport errors and allows a later retry', () async {
      var calls = 0;
      final opened = await open((_) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException(
            'private token and student phone 0900000001',
          );
        }
        return _jsonResponse([_jobJson()]);
      });

      await expectLater(
        opened.repository.fetchJobs(),
        throwsA(_retryableFailure),
      );
      expect(await opened.repository.fetchJobs(), hasLength(1));
      expect(calls, 2);
    });

    test(
      'sanitizes malformed JSON contracts and ordinary service failures',
      () async {
        final replies = [
          _jsonResponse([_jobJson(status: 'private-payload')]),
          _jsonResponse({'private': 'student phone 0900000001'}),
          _jsonResponse({
            'code': 'XX000',
            'message': 'private SQL and token',
          }, status: 500),
        ];
        final opened = await open((_) async => replies.removeAt(0));

        for (var i = 0; i < 3; i++) {
          await expectLater(
            opened.repository.fetchJobs(),
            throwsA(_retryableFailure),
          );
        }
      },
    );
  });

  group('private attachment reads', () {
    test(
      'rechecks assignment and DB metadata then downloads with JWT each time',
      () async {
        final requests = <http.Request>[];
        final opened = await open((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/technician_get_job')) {
            return _jsonResponse(_detailJson());
          }
          if (request.url.path == '/rest/v1/request_attachments') {
            expect(request.method, 'GET');
            expect(request.url.queryParameters['id'], 'eq.$_attachmentId');
            expect(request.url.queryParameters['request_id'], 'eq.$_requestId');
            expect(
              request.url.queryParameters['storage_path'],
              'eq.$_storagePath',
            );
            expect(
              request.url.queryParameters['select'],
              contains('storage_path'),
            );
            return _jsonResponse([
              {..._attachmentJson(), 'request_id': _requestId},
            ]);
          }
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/storage/v1/object/repair-images/$_storagePath',
          );
          expect(request.url.path, isNot(contains('/public/')));
          expect(request.url.path, isNot(contains('/sign/')));
          expect(request.url.queryParameters, isNot(contains('token')));
          return http.Response.bytes([137, 80, 78, 71], 200);
        });
        final attachment = JobAttachment.fromJson(_attachmentJson());

        for (var i = 0; i < 2; i++) {
          expect(
            await opened.repository.fetchAttachment(_requestId, attachment),
            Uint8List.fromList([137, 80, 78, 71]),
          );
        }

        expect(requests, hasLength(6));
        for (final request in requests) {
          _expectAuthenticated(request, opened.token);
        }
      },
    );

    test('rejects a caller-supplied path that is absent from the authorized detail', () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        return _jsonResponse(_detailJson());
      });
      final forged = JobAttachment.fromJson(
        _attachmentJson()..['storage_path'] = 'private-other-job/image.png',
      );

      await expectLater(
        opened.repository.fetchAttachment(_requestId, forged),
        throwsA(_deniedFailure),
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, endsWith('/technician_get_job'));
    });

    test(
      'rejects wrong roles or revoked assignments before any object request',
      () async {
        final requests = <http.Request>[];
        final opened = await open((request) async {
          requests.add(request);
          return _jsonResponse({
            'code': '42501',
            'message': 'private assignment transferred to another technician',
          }, status: 403);
        });

        await expectLater(
          opened.repository.fetchAttachment(
            _requestId,
            JobAttachment.fromJson(_attachmentJson()),
          ),
          throwsA(_deniedFailure),
        );
        expect(requests, hasLength(1));
      },
    );

    for (final metadata in [
      <Map<String, dynamic>>[],
      [
        {..._attachmentJson(), 'request_id': 'another-request'},
      ],
      [
        {
          ..._attachmentJson(),
          'request_id': _requestId,
          'storage_path': 'private-other-job/image.png',
        },
      ],
    ]) {
      test(
        'does not download when actual DB metadata is absent or mismatched',
        () async {
          var requests = 0;
          final opened = await open((request) async {
            requests++;
            if (request.url.path.endsWith('/technician_get_job')) {
              return _jsonResponse(_detailJson());
            }
            expect(request.url.path, '/rest/v1/request_attachments');
            return _jsonResponse(metadata);
          });

          await expectLater(
            opened.repository.fetchAttachment(
              _requestId,
              JobAttachment.fromJson(_attachmentJson()),
            ),
            throwsA(_deniedFailure),
          );
          expect(requests, 2);
        },
      );
    }

    test(
      'honors Storage permission denial and hides private object paths',
      () async {
        final opened = await open((request) async {
          if (request.url.path.endsWith('/technician_get_job')) {
            return _jsonResponse(_detailJson());
          }
          if (request.url.path == '/rest/v1/request_attachments') {
            return _jsonResponse([
              {..._attachmentJson(), 'request_id': _requestId},
            ]);
          }
          return _jsonResponse({
            'statusCode': '403',
            'error': 'Unauthorized',
            'message': 'private object $_storagePath was revoked',
          }, status: 403);
        });

        await expectLater(
          opened.repository.fetchAttachment(
            _requestId,
            JobAttachment.fromJson(_attachmentJson()),
          ),
          throwsA(_deniedFailure),
        );
      },
    );
  });
}

final _deniedFailure = isA<TechnicianJobsFailure>()
    .having((failure) => failure.accessDenied, 'accessDenied', isTrue)
    .having((failure) => failure.message, 'message', isNot(contains('private')))
    .having(
      (failure) => failure.message,
      'message',
      isNot(contains('0900000001')),
    )
    .having(
      (failure) => failure.message,
      'message',
      isNot(contains(_storagePath)),
    );

final _retryableFailure = isA<TechnicianJobsFailure>()
    .having((failure) => failure.accessDenied, 'accessDenied', isFalse)
    .having((failure) => failure.message, 'message', contains('thử lại'))
    .having((failure) => failure.message, 'message', isNot(contains('private')))
    .having(
      (failure) => failure.message,
      'message',
      isNot(contains('0900000001')),
    );

void _expectAuthenticated(http.Request request, String token) {
  expect(request.headers['authorization'], 'Bearer $token');
  expect(request.headers['apikey'], _apiKey);
}

http.Response _jsonResponse(Object? value, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _jwt({required bool expired, String userId = _technicianId}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiresAt =
      DateTime.now()
          .add(expired ? const Duration(hours: -1) : const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': userId, 'role': 'authenticated', 'exp': expiresAt})}.'
      'local-test-signature';
}

String _sessionJson(String token, {String userId = _technicianId}) =>
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'refresh_token': 'local-test-refresh-token',
      'user': {
        'id': userId,
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-10-15T00:00:00Z',
      },
    });

Map<String, dynamic> _jobJson({String status = 'awaiting_rework'}) => {
  'id': _requestId,
  'request_code': 'DF000001',
  'title': 'Đèn phòng không sáng',
  'description': 'Đèn nhấp nháy, cần kiểm tra dây điện.',
  'room_code': 'A101',
  'building': 'Tòa A',
  'category_name': 'Điện',
  'status': status,
  'created_at': '2026-10-15T09:30:00+07:00',
  'updated_at': '2026-10-15T03:00:00Z',
  'version': 4,
};

Map<String, dynamic> _attachmentJson() => {
  'id': _attachmentId,
  'storage_path': _storagePath,
  'mime_type': 'image/png',
  'size_bytes': 4,
  'result_id': null,
  'feedback_id': null,
};

Map<String, dynamic> _detailJson() => {
  'request': _jobJson(),
  'student': {'full_name': 'Nguyễn Thị Ánh', 'phone': '0900000001'},
  'attachments': [_attachmentJson()],
  'results': [
    {
      'id': 'result-1',
      'content': 'Đã thay bóng đèn.',
      'submitted_at': '2026-10-15T02:40:00Z',
      'technician_name': 'Trần Văn Bình',
    },
  ],
  'feedback': [
    {
      'id': 'feedback-1',
      'kind': 'rework',
      'reason': 'Đèn vẫn nhấp nháy',
      'created_at': '2026-10-15T02:50:00Z',
      'author_name': 'Nguyễn Thị Ánh',
    },
  ],
  'history': [
    {
      'id': 'history-1',
      'action': 'rework_requested',
      'actor_name': 'Nguyễn Thị Ánh',
      'old_status': 'awaiting_confirmation',
      'new_status': 'awaiting_rework',
      'note': null,
      'occurred_at': '2026-10-15T02:50:00Z',
    },
  ],
  'assignments': [
    {
      'id': 'assignment-1',
      'technician_name': 'Trần Văn Bình',
      'assigned_by_name': 'Quản lý ký túc xá',
      'assigned_at': '2026-10-15T02:35:00Z',
      'ended_at': null,
      'transfer_reason': null,
      'end_reason': null,
    },
  ],
};
