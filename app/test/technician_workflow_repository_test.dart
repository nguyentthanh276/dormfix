import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/technician_jobs/data/technician_workflow_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_job.dart';
import 'package:dormfix/features/technician_jobs/models/technician_workflow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _requestId = '11111111-1111-4111-8111-111111111111';
const _technicianId = '33333333-3333-4333-8333-333333333333';
const _otherId = '44444444-4444-4444-8444-444444444444';
const _apiKey = 'sb_publishable_local_workflow_test';
const _png = [137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3];

void main() {
  final clients = <SupabaseClient>[];

  Future<
    ({
      SupabaseClient client,
      SupabaseTechnicianWorkflowRepository repo,
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
    if (withSession) await client.auth.setInitialSession(_session(token));
    return (
      client: client,
      repo: SupabaseTechnicianWorkflowRepository(client),
      token: token,
    );
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  group('immutable workflow payloads', () {
    test('old details disable writes and server capabilities are parsed', () {
      final old = TechnicianJobDetail.fromJson(_detail());
      expect(old.workflow.canStart, isFalse);
      expect(old.workflow.canSubmitResult, isFalse);
      final current = TechnicianJobDetail.fromJson(
        _detail()
          ..['workflow'] = {
            'can_start': false,
            'can_submit_result': true,
            'blocked_reason': null,
          },
      );
      expect(current.workflow.canSubmitResult, isTrue);
      for (final reason in [
        'READ_ONLY',
        'ASSIGNMENT_NOT_READY',
        'START_REQUIRED',
        'CONTINUE_REQUIRED',
        'TRANSFER_CONFIRMATION_REQUIRED',
      ]) {
        final value = TechnicianWorkflowCapabilities.fromJson({
          'can_start': false,
          'can_submit_result': false,
          'blocked_reason': reason,
        });
        expect(value.blockedReason, reason);
      }
    });

    test(
      'malformed capabilities fail closed rather than guessing from status',
      () {
        for (final value in [
          {
            'can_start': true,
            'can_submit_result': true,
            'blocked_reason': null,
          },
          {
            'can_start': 'true',
            'can_submit_result': false,
            'blocked_reason': null,
          },
          {'can_start': true, 'can_submit_result': false},
          {
            'can_start': false,
            'can_submit_result': false,
            'blocked_reason': 'new',
          },
        ]) {
          expect(
            () => TechnicianJobDetail.fromJson(_detail()..['workflow'] = value),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'photo MIME comes from bytes and bytes cannot mutate after selection',
      () {
        final source = Uint8List.fromList(_png);
        final photo = TechnicianResultPhoto.fromBytes(
          name: '../../fake.exe',
          bytes: source,
        );
        source[0] = 0;
        expect(photo.bytes.first, 137);
        expect(photo.mimeType, 'image/png');
        expect(photo.extension, 'png');
        expect(() => photo.bytes[0] = 0, throwsUnsupportedError);
        expect(isTechnicianWorkflowId(photo.id), isTrue);
        final jpeg = TechnicianResultPhoto.fromBytes(
          name: 'fake.png',
          bytes: Uint8List.fromList([255, 216, 255, 0]),
        );
        expect(jpeg.mimeType, 'image/jpeg');
        final webp = TechnicianResultPhoto.fromBytes(
          name: 'fake.jpg',
          bytes: Uint8List.fromList([
            82,
            73,
            70,
            70,
            0,
            0,
            0,
            0,
            87,
            69,
            66,
            80,
          ]),
        );
        expect(webp.mimeType, 'image/webp');
      },
    );

    test('photo and submission constraints reject invalid local payloads', () {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
        Uint8List(5242881),
      ]) {
        expect(
          () => TechnicianResultPhoto.fromBytes(name: 'x.png', bytes: bytes),
          throwsA(isA<TechnicianWorkflowFailure>()),
        );
      }
      final photo = _photo();
      for (final photos in [
        [photo, photo],
        List.generate(6, (_) => _photo()),
      ]) {
        expect(
          () => _submission(photos: photos),
          throwsA(isA<TechnicianWorkflowFailure>()),
        );
      }
      expect(
        () => _submission(content: ' \n '),
        throwsA(isA<TechnicianWorkflowFailure>()),
      );
      expect(
        () => TechnicianResultSubmission.create(
          job: _job(id: 'invalid'),
          content: 'x',
          photos: [],
        ),
        throwsA(isA<TechnicianWorkflowFailure>()),
      );
    });

    test('submission owns list and retains exact identity, content and canonical path', () {
      final source = [_photo()];
      final submission = _submission(
        photos: source,
        content: '  Đã thay bóng đèn. \n',
      );
      source.clear();
      expect(submission.content, 'Đã thay bóng đèn.');
      expect(submission.photos, hasLength(1));
      expect(() => submission.photos.clear(), throwsUnsupportedError);
      expect(
        submission.storagePath(_technicianId, submission.photos.single),
        'technician-results/$_technicianId/$_requestId/4/${submission.resultId}/${submission.photos.single.id}.png',
      );
      expect(submission.resultId, isNot(_submission().resultId));
    });
  });

  group('real Supabase write contract', () {
    test('start sends exact version/JWT and validates receipt', () async {
      final requests = <http.Request>[];
      final opened = await open((request) async {
        requests.add(request);
        return _json(_startReceipt());
      });
      final receipt = await opened.repo.startJob(
        requestId: _requestId,
        expectedVersion: 4,
      );
      expect(receipt.status, RepairStatus.inProgress);
      expect(receipt.version, 5);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/technician_start_job');
      expect(jsonDecode(request.body), {
        'p_request_id': _requestId,
        'p_expected_version': 4,
      });
      _authenticated(request, opened.token);
    });

    for (final expired in [false, true]) {
      test(
        '${expired ? 'expired' : 'missing'} session prevents all network writes',
        () async {
          var calls = 0;
          final opened = await open(
            (_) async {
              calls++;
              return _json({});
            },
            withSession: expired,
            expired: expired,
          );
          await expectLater(
            opened.repo.startJob(requestId: _requestId, expectedVersion: 4),
            throwsA(_denied),
          );
          await expectLater(
            opened.repo.submitResult(_submission()),
            throwsA(_denied),
          );
          expect(calls, 0);
        },
      );
    }

    test('invalid start inputs are rejected locally', () async {
      var calls = 0;
      final opened = await open((_) async {
        calls++;
        return _json({});
      });
      for (final input in [
        (id: 'bad', version: 4),
        (id: _requestId, version: 0),
      ]) {
        await expectLater(
          opened.repo.startJob(
            requestId: input.id,
            expectedVersion: input.version,
          ),
          throwsA(isA<TechnicianWorkflowFailure>()),
        );
      }
      expect(calls, 0);
    });

    for (final code in [
      '28000',
      '42501',
      'P0002',
      'P0001',
      '22023',
      'PGRST202',
    ]) {
      test(
        'maps $code without exposing backend error details or retrying',
        () async {
          var calls = 0;
          final opened = await open((_) async {
            calls++;
            return _error(code, 'private-token-storage-path');
          });
          try {
            await opened.repo.startJob(
              requestId: _requestId,
              expectedVersion: 4,
            );
            fail('Expected failure');
          } on TechnicianWorkflowFailure catch (error) {
            expect(
              error.accessDenied,
              ['28000', '42501', 'P0002'].contains(code),
            );
            expect(error.conflict, code == 'P0001');
            expect(error.uncertain, isFalse);
            expect(error.message, isNot(contains('private-token')));
          }
          expect(calls, 1);
        },
      );
    }

    test(
      'photo-less submit has stable result UUID and exact trimmed RPC payload',
      () async {
        final submission = _submission(content: ' Đã sửa ổ điện. ');
        final requests = <http.Request>[];
        final opened = await open((request) async {
          requests.add(request);
          return _json(_resultReceipt(submission));
        });
        final receipt = await opened.repo.submitResult(submission);
        expect(receipt.status, RepairStatus.awaitingConfirmation);
        expect(receipt.resultId, submission.resultId);
        expect(
          requests.single.url.path,
          '/rest/v1/rpc/technician_submit_result',
        );
        expect(jsonDecode(requests.single.body), _payload(submission));
        _authenticated(requests.single, opened.token);
      },
    );

    test(
      'private upload has canonical path, real bytes, MIME and no upsert',
      () async {
        final submission = _submission(photos: [_photo()]);
        final path = submission.storagePath(
          _technicianId,
          submission.photos.single,
        );
        final requests = <http.Request>[];
        final opened = await open((request) async {
          requests.add(request);
          if (request.method == 'GET') return _missing();
          if (request.url.path.startsWith('/storage/')) {
            return _json({'Key': 'repair-images/$path'});
          }
          return _json(_resultReceipt(submission));
        });
        await opened.repo.submitResult(submission);
        expect(requests.map((r) => r.method), ['GET', 'POST', 'POST']);
        expect(
          requests[0].url.path,
          '/storage/v1/object/info/repair-images/$path',
        );
        final upload = requests[1];
        expect(upload.url.path, '/storage/v1/object/repair-images/$path');
        expect(upload.headers['x-upsert'], 'false');
        expect(
          latin1.decode(upload.bodyBytes),
          contains('content-type: image/png'),
        );
        expect(latin1.decode(upload.bodyBytes), contains(latin1.decode(_png)));
        expect(jsonDecode(requests.last.body), _payload(submission));
        for (final request in requests) {
          _authenticated(request, opened.token);
        }
        expect(
          requests.any(
            (r) =>
                r.url.path.contains('/public/') ||
                r.url.path.contains('/sign/'),
          ),
          isFalse,
        );
      },
    );

    test(
      'owned staged object with matching metadata is reused without upload',
      () async {
        final submission = _submission(photos: [_photo()]);
        final requests = <http.Request>[];
        final opened = await open((request) async {
          requests.add(request);
          if (request.method == 'GET') return _json(_info(submission));
          return _json(_resultReceipt(submission, replayed: true));
        });
        final receipt = await opened.repo.submitResult(submission);
        expect(receipt.replayed, isTrue);
        expect(requests, hasLength(2));
        expect(requests.last.url.path, '/rest/v1/rpc/technician_submit_result');
      },
    );

    for (final field in ['size', 'content_type', 'name', 'bucket_id']) {
      test(
        'mismatching staged $field is never finalized and cleans only own paths',
        () async {
          final submission = _submission(photos: [_photo()]);
          final requests = <http.Request>[];
          final opened = await open((request) async {
            requests.add(request);
            if (request.method == 'DELETE') return _json([]);
            final info = _info(submission);
            info[field] = field == 'size' ? 999 : 'wrong';
            return _json(info);
          });
          await expectLater(
            opened.repo.submitResult(submission),
            throwsA(isA<TechnicianWorkflowFailure>()),
          );
          expect(requests.map((r) => r.method), ['GET', 'DELETE']);
          expect(jsonDecode(requests.last.body), {
            'prefixes': [
              submission.storagePath(_technicianId, submission.photos.single),
            ],
          });
        },
      );
    }

    test(
      'partial upload failure performs no final RPC or automatic upload retry',
      () async {
        final submission = _submission(photos: [_photo(), _photo()]);
        final requests = <http.Request>[];
        var uploads = 0;
        final opened = await open((request) async {
          requests.add(request);
          if (request.method == 'GET') return _missing();
          if (request.method == 'DELETE') return _json([]);
          uploads++;
          return uploads == 1
              ? _json({'Key': 'first'})
              : _json({
                  'statusCode': 503,
                  'message': 'private failure',
                }, status: 503);
        });
        await expectLater(
          opened.repo.submitResult(submission),
          throwsA(
            isA<TechnicianWorkflowFailure>().having(
              (e) => e.uncertain,
              'uncertain',
              false,
            ),
          ),
        );
        expect(uploads, 2);
        expect(requests.map((r) => r.method), [
          'GET',
          'POST',
          'GET',
          'POST',
          'DELETE',
        ]);
        expect(jsonDecode(requests.last.body), {
          'prefixes': [
            for (final photo in submission.photos)
              submission.storagePath(_technicianId, photo),
          ],
        });
      },
    );

    test(
      'concurrent duplicate upload is reused only after matching info',
      () async {
        final submission = _submission(photos: [_photo()]);
        var gets = 0;
        final requests = <http.Request>[];
        final opened = await open((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return ++gets == 1 ? _missing() : _json(_info(submission));
          }
          if (request.url.path.startsWith('/storage/')) {
            return _json({
              'statusCode': 409,
              'error': 'Duplicate',
              'message': 'exists',
            }, status: 409);
          }
          return _json(_resultReceipt(submission));
        });
        await opened.repo.submitResult(submission);
        expect(requests.map((r) => r.method), ['GET', 'POST', 'GET', 'POST']);
      },
    );

    test(
      'definitive server conflict cleans staging and is not uncertain',
      () async {
        final submission = _submission(photos: [_photo()]);
        final requests = <http.Request>[];
        final opened = await open((request) async {
          requests.add(request);
          if (request.method == 'GET') return _json(_info(submission));
          if (request.method == 'DELETE') return _json([]);
          return _error('P0001', 'JOB_STATE_CONFLICT');
        });
        await expectLater(
          opened.repo.submitResult(submission),
          throwsA(
            isA<TechnicianWorkflowFailure>()
                .having((e) => e.conflict, 'conflict', true)
                .having((e) => e.uncertain, 'uncertain', false),
          ),
        );
        expect(requests.map((r) => r.method), ['GET', 'POST', 'DELETE']);
      },
    );

    test('lost commit response replays original manifest before any Storage operation', () async {
      final submission = _submission(photos: [_photo()]);
      final requests = <http.Request>[];
      var commits = 0;
      final opened = await open((request) async {
        requests.add(request);
        if (request.method == 'GET') return _json(_info(submission));
        if (request.method == 'DELETE') {
          return _json({
            'message': 'committed objects protected',
            'statusCode': 403,
          }, status: 403);
        }
        if (++commits == 1) {
          throw http.ClientException('private transport detail');
        }
        return _json(_resultReceipt(submission, replayed: true));
      });
      await expectLater(
        opened.repo.submitResult(submission),
        throwsA(
          isA<TechnicianWorkflowFailure>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      final beforeRetry = requests.length;
      final receipt = await opened.repo.submitResult(submission);
      expect(receipt.replayed, isTrue);
      expect(requests.length, beforeRetry + 1);
      expect(requests.last.url.path, '/rest/v1/rpc/technician_submit_result');
      expect(jsonDecode(requests[1].body), jsonDecode(requests.last.body));
    });

    test('uncertain noncommit can restage after direct replay reports missing photos', () async {
      final submission = _submission(photos: [_photo()]);
      final requests = <http.Request>[];
      var commits = 0;
      final opened = await open((request) async {
        requests.add(request);
        if (request.method == 'GET') return _missing();
        if (request.method == 'DELETE') return _json([]);
        if (request.url.path.startsWith('/storage/')) {
          return _json({'Key': 'stored'});
        }
        commits++;
        if (commits == 1) throw http.ClientException('connection lost');
        if (commits == 2) return _error('22023', 'INVALID_RESULT_PHOTOS');
        return _json(_resultReceipt(submission));
      });
      await expectLater(
        opened.repo.submitResult(submission),
        throwsA(
          isA<TechnicianWorkflowFailure>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      final retryStart = requests.length;
      await opened.repo.submitResult(submission);
      expect(requests.sublist(retryStart).map((r) => r.method), [
        'POST',
        'GET',
        'POST',
        'POST',
      ]);
      expect(
        jsonDecode(requests[retryStart].body),
        jsonDecode(requests.last.body),
      );
    });

    for (final field in ['request_id', 'result_id', 'version', 'status']) {
      test(
        'unexpected result receipt $field produces sanitized uncertain failure',
        () async {
          final submission = _submission();
          final opened = await open((_) async {
            final receipt = _resultReceipt(submission);
            receipt[field] = field == 'version'
                ? 99
                : (field == 'status' ? 'completed' : _otherId);
            return _json(receipt);
          });
          await expectLater(
            opened.repo.submitResult(submission),
            throwsA(
              isA<TechnicianWorkflowFailure>().having(
                (e) => e.uncertain,
                'uncertain',
                true,
              ),
            ),
          );
        },
      );
    }

    test(
      'account switch during start discards the in-flight receipt',
      () async {
        final started = Completer<void>();
        final result = Completer<http.Response>();
        final opened = await open((_) async {
          started.complete();
          return result.future;
        });
        final action = opened.repo.startJob(
          requestId: _requestId,
          expectedVersion: 4,
        );
        final checked = expectLater(action, throwsA(_denied));
        await started.future;
        await opened.client.auth.setInitialSession(
          _session(_jwt(uid: _otherId), uid: _otherId),
        );
        result.complete(_json(_startReceipt()));
        await checked;
      },
    );

    for (final duringUpload in [false, true]) {
      test(
        'account switch during ${duringUpload ? 'upload' : 'info'} stops finalization and cleanup under new JWT',
        () async {
          final submission = _submission(photos: [_photo()]);
          final started = Completer<void>();
          final result = Completer<http.Response>();
          final requests = <http.Request>[];
          final opened = await open((request) async {
            requests.add(request);
            if (duringUpload && request.method == 'GET') return _missing();
            started.complete();
            return result.future;
          });
          final checked = expectLater(
            opened.repo.submitResult(submission),
            throwsA(_denied),
          );
          await started.future;
          await opened.client.auth.setInitialSession(
            _session(_jwt(uid: _otherId), uid: _otherId),
          );
          result.complete(duringUpload ? _json({'Key': 'stored'}) : _missing());
          await checked;
          expect(requests.length, duringUpload ? 2 : 1);
          await expectLater(
            opened.repo.submitResult(submission),
            throwsA(_denied),
          );
          expect(requests.length, duringUpload ? 2 : 1);
        },
      );
    }
  });
}

final _denied = isA<TechnicianWorkflowFailure>().having(
  (e) => e.accessDenied,
  'accessDenied',
  true,
);
TechnicianResultPhoto _photo() => TechnicianResultPhoto.fromBytes(
  name: 'đèn.png',
  bytes: Uint8List.fromList(_png),
);
TechnicianResultSubmission _submission({
  List<TechnicianResultPhoto> photos = const [],
  String content = 'Đã sửa.',
}) => TechnicianResultSubmission.create(
  job: _job(),
  content: content,
  photos: photos,
);
TechnicianJob _job({String id = _requestId}) => TechnicianJob(
  id: id,
  requestCode: 'DF-001',
  title: 'Đèn hỏng',
  description: 'Đèn không sáng',
  roomCode: 'A101',
  building: 'A',
  categoryName: 'Điện',
  status: RepairStatus.inProgress,
  createdAt: DateTime.utc(2026, 10, 20),
  updatedAt: DateTime.utc(2026, 10, 20),
  version: 4,
);
Map<String, dynamic> _detail() => {
  'request': {
    'id': _requestId,
    'request_code': 'DF-001',
    'title': 'Đèn hỏng',
    'description': 'Đèn không sáng',
    'room_code': 'A101',
    'building': 'A',
    'category_name': 'Điện',
    'status': 'assigned',
    'created_at': '2026-10-20T00:00:00Z',
    'updated_at': '2026-10-20T00:00:00Z',
    'version': 4,
  },
  'student': {'full_name': 'Sinh viên', 'phone': '0900000000'},
  'attachments': [],
  'results': [],
  'feedback': [],
  'history': [],
  'assignments': [],
};
Map<String, dynamic> _startReceipt() => {
  'request_id': _requestId,
  'status': 'in_progress',
  'version': 5,
};
Map<String, dynamic> _resultReceipt(
  TechnicianResultSubmission submission, {
  bool replayed = false,
}) => {
  'request_id': _requestId,
  'result_id': submission.resultId,
  'status': 'awaiting_confirmation',
  'version': 5,
  'replayed': replayed,
};
Map<String, dynamic> _payload(TechnicianResultSubmission submission) => {
  'p_request_id': _requestId,
  'p_expected_version': 4,
  'p_result_id': submission.resultId,
  'p_content': submission.content,
  'p_photos': [
    for (final p in submission.photos)
      {
        'id': p.id,
        'storage_path': submission.storagePath(_technicianId, p),
        'mime_type': p.mimeType,
        'size_bytes': p.sizeBytes,
      },
  ],
};
Map<String, dynamic> _info(TechnicianResultSubmission submission) => {
  'id': submission.photos.first.id,
  'version': '1',
  'name': submission.storagePath(_technicianId, submission.photos.first),
  'bucket_id': 'repair-images',
  'created_at': '2026-10-21T00:00:00Z',
  'size': submission.photos.first.sizeBytes,
  'content_type': submission.photos.first.mimeType,
};
http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response _error(String code, String message) => _json({
  'code': code,
  'message': message,
  'details': null,
  'hint': null,
}, status: 400);
http.Response _missing() => _json({
  'statusCode': 404,
  'message': 'Object not found',
  'error': 'not_found',
}, status: 404);
void _authenticated(http.Request request, String token) {
  expect(request.headers['authorization'], 'Bearer $token');
  expect(request.headers['apikey'], _apiKey);
}

String _jwt({String uid = _technicianId, bool expired = false}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp =
      DateTime.now()
          .add(Duration(hours: expired ? -1 : 1))
          .millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': uid, 'role': 'authenticated', 'exp': exp})}.local-test-signature';
}

String _session(String token, {String uid = _technicianId}) => jsonEncode({
  'access_token': token,
  'token_type': 'bearer',
  'refresh_token': 'local-test-refresh',
  'user': {
    'id': uid,
    'app_metadata': {},
    'user_metadata': {},
    'aud': 'authenticated',
    'created_at': '2026-10-15T00:00:00Z',
  },
});
