import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/student_requests/data/request_repository.dart';
import 'package:dormfix/features/student_requests/data/supabase_request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_detail.dart';
import 'package:dormfix/features/student_requests/models/student_request_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _student = '33333333-3333-4333-8333-333333333333';
const _other = '44444444-4444-4444-8444-444444444444';
const _request = '11111111-1111-4111-8111-111111111111';
const _category = '22222222-2222-4222-8222-222222222222';
const _photo = '55555555-5555-4555-8555-555555555555';
const _result = '66666666-6666-4666-8666-666666666666';
const _feedback = '77777777-7777-4777-8777-777777777777';
const _key = 'sb_publishable_student_request_tests';
const _png = [137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3];

void main() {
  final clients = <SupabaseClient>[];
  Future<({SupabaseClient client, SupabaseRequestRepository repo})> open(
    Future<http.Response> Function(http.Request) handler, {
    bool withSession = true,
    bool expired = false,
  }) async {
    final client = SupabaseClient(
      'https://dormfix.test',
      _key,
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
    if (withSession) {
      await client.auth.setInitialSession(_session(expired: expired));
    }
    return (client: client, repo: SupabaseRequestRepository(client));
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  test('secure request IDs are distinct canonical UUIDv4 values', () {
    final ids = List.generate(100, (_) => createStudentRequestId());
    expect(ids.toSet(), hasLength(100));
    expect(ids.every(isStudentRequestId), isTrue);
    expect(ids.every((id) => id[14] == '4' && '89ab'.contains(id[19])), isTrue);
  });

  test(
    'list/category RPCs use JWT without client owner or room parameters',
    () async {
      final calls = <http.Request>[];
      final app = await open((request) async {
        calls.add(request);
        return _json(
          request.url.path.endsWith('student_list_categories')
              ? [
                  {'id': _category, 'name': 'Điện'},
                ]
              : [_summary()],
        );
      });
      expect((await app.repo.fetchCategories()).single.name, 'Điện');
      final item = (await app.repo.fetchMyRequests()).single;
      expect(item.studentId, _student);
      expect(item.version, 1);
      expect(item.createdAt, DateTime.utc(2026, 11, 9, 10));
      for (final request in calls) {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), isNull);
        expect(request.headers['apikey'], _key);
        expect(request.headers['authorization'], startsWith('Bearer '));
      }
      expect(app.repo.supportsEditing, isTrue);
      expect(app.repo.supportsCancellation, isTrue);
      expect(app.repo.supportsConfirmationActions, isTrue);
      expect(app.repo.supportsVersionedMutations, isTrue);
      expect(app.repo.supportsReopening, isTrue);
      expect(app.repo.allowsDemoFallback, isFalse);
    },
  );

  test('detail retains snapshot, current contact, all result/feedback photos and audit actor', () async {
    final app = await open((request) async {
      expect(jsonDecode(request.body), {'p_request_id': _request});
      return _json(_detail());
    });
    final detail = await app.repo.fetchRequestDetail(_request);
    expect(detail.request.roomCode, 'DEMO-A101');
    expect(detail.categoryId, _category);
    expect(detail.canEdit || detail.canCancel || detail.canReopen, isFalse);
    expect(detail.technicianName, 'Kỹ thuật viên Demo');
    expect(detail.technicianPhone, '0901111111');
    expect(detail.studentPhotos, [_path]);
    expect(detail.attachments, hasLength(3));
    expect(detail.results.single.photos, [_resultPath]);
    expect(detail.feedback.single.reason, 'Nước vẫn rò');
    expect(detail.feedback.single.photos, [_feedbackPath]);
    expect(detail.history.single.actorId, _student);
    expect(detail.history.single.note, 'Đã tạo yêu cầu');
    expect(() => detail.attachments.clear(), throwsUnsupportedError);
  });

  test(
    'versioned actions need explicit true server flags and valid states',
    () async {
      final samples = [
        _detail()
          ..addAll({'can_edit': true, 'can_cancel': true, 'can_reopen': true}),
        _detail()..addAll({
          'can_edit': 'true',
          'can_cancel': null,
          'can_reopen': false,
        }),
        _detail()
          ..addAll({'can_edit': true, 'can_cancel': true, 'can_reopen': true})
          ..['request']['status'] = 'completed',
      ];
      final app = await open((_) async => _json(samples.removeAt(0)));
      final pending = await app.repo.fetchRequestDetail(_request);
      expect(
        (pending.canEdit, pending.canCancel, pending.canReopen),
        (true, true, false),
      );
      final malformed = await app.repo.fetchRequestDetail(_request);
      expect(
        (malformed.canEdit, malformed.canCancel, malformed.canReopen),
        (false, false, false),
      );
      final completed = await app.repo.fetchRequestDetail(_request);
      expect(
        (completed.canEdit, completed.canCancel, completed.canReopen),
        (false, false, true),
      );
    },
  );

  test('foreign and malformed summaries are rejected safely', () async {
    final values = [
      _summary()..['student_id'] = _other,
      _summary()..['status'] = 'unknown',
      _summary()..['version'] = 0,
      _summary()..['created_at'] = '2026-11-09T10:00:00',
    ];
    final app = await open((_) async => _json([values.removeAt(0)]));
    await expectLater(app.repo.fetchMyRequests(), throwsA(_denied));
    for (var i = 0; i < 3; i++) {
      await expectLater(app.repo.fetchMyRequests(), throwsA(_safe));
    }
  });

  for (final expired in [false, true]) {
    test(
      'missing/expired session prevents every network read/create ($expired)',
      () async {
        var calls = 0;
        final app = await open(
          (_) async {
            calls++;
            return _json([]);
          },
          withSession: expired,
          expired: expired,
        );
        await expectLater(app.repo.fetchCategories(), throwsA(_denied));
        await expectLater(app.repo.fetchMyRequests(), throwsA(_denied));
        await expectLater(
          app.repo.fetchRequestDetail(_request),
          throwsA(_denied),
        );
        await expectLater(app.repo.createRequest(_draft()), throwsA(_denied));
        expect(calls, 0);
      },
    );
  }

  test('create only sends validated input and one idempotency UUID', () async {
    final calls = <http.Request>[];
    final app = await open((request) async {
      calls.add(request);
      return _json(_summary());
    });
    final created = await app.repo.createRequest(_draft());
    expect(created.id, _request);
    expect(created.status, RepairStatus.pending);
    expect(calls, hasLength(1));
    expect(calls.single.url.path, '/rest/v1/rpc/student_create_request');
    expect(jsonDecode(calls.single.body), {
      'p_request_id': _request,
      'p_title': 'Đèn bị hỏng',
      'p_category_id': _category,
      'p_description': 'Đèn không sáng',
      'p_photos': [],
    });
  });

  test(
    'canonical private upload uses actual bytes/MIME and no upsert',
    () async {
      final calls = <http.Request>[];
      Map<String, dynamic>? manifest;
      final app = await open((request) async {
        calls.add(request);
        if (request.url.path.contains('/object/info/')) {
          return _storageMissing();
        }
        if (request.url.path.contains('/rpc/')) {
          manifest =
              (jsonDecode(request.body)['p_photos'] as List).single
                  as Map<String, dynamic>;
          return _json(_summary());
        }
        return _json({
          'Key':
              'repair-images/${request.url.path.split('/repair-images/').last}',
        });
      });
      await app.repo.createRequest(_draft(photos: true));
      final photo = manifest!;
      expect(
        photo['storage_path'],
        'student-requests/$_student/$_request/${photo['id']}.png',
      );
      expect(photo['mime_type'], 'image/png');
      expect(photo['size_bytes'], _png.length);
      final upload = calls.singleWhere(
        (r) => r.url.path.contains('/object/repair-images/'),
      );
      expect(upload.headers['x-upsert'], 'false');
      expect(latin1.decode(upload.bodyBytes), contains(latin1.decode(_png)));
      expect(latin1.decode(upload.bodyBytes), contains('image/png'));
      expect(calls.map((r) => r.method), ['GET', 'POST', 'POST']);
    },
  );

  test(
    'matching staged photo is reused, mismatching object never finalized',
    () async {
      for (final mismatch in [false, true]) {
        var uploads = 0, rpcs = 0;
        final app = await open((request) async {
          if (request.url.path.contains('/object/info/')) {
            final path = request.url.path.split('/repair-images/').last;
            return _json(_info(path)..['size'] = mismatch ? 999 : _png.length);
          }
          if (request.url.path.contains('/rpc/')) {
            rpcs++;
            return _json(_summary());
          }
          if (request.method == 'POST') uploads++;
          return _json([]);
        });
        final pending = app.repo.createRequest(_draft(photos: true));
        if (mismatch) {
          await expectLater(pending, throwsA(_safe));
        } else {
          await pending;
        }
        expect(uploads, 0);
        expect(rpcs, mismatch ? 0 : 1);
      }
    },
  );

  test(
    'invalid empty, oversized, fake and excess images stop before network',
    () async {
      var calls = 0;
      final app = await open((_) async {
        calls++;
        return _json({});
      });
      for (final photos in [
        [AttachmentDraft(name: 'x.png', bytes: Uint8List(0))],
        [AttachmentDraft(name: 'x.png', bytes: Uint8List(5 * 1024 * 1024 + 1))],
        [
          AttachmentDraft(name: 'x.png', bytes: Uint8List.fromList([1, 2, 3])),
        ],
        List.generate(
          6,
          (_) =>
              AttachmentDraft(name: 'x.png', bytes: Uint8List.fromList(_png)),
        ),
      ]) {
        await expectLater(
          app.repo.createRequest(_draft(attachments: photos)),
          throwsA(_safe),
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'unknown commit replays before Storage and accepts current assigned status',
    () async {
      var rpcs = 0, uploads = 0, deletes = 0, infoCalls = 0;
      final bodies = <String>[];
      final app = await open((request) async {
        if (request.url.path.contains('/object/info/')) {
          infoCalls++;
          return _storageMissing();
        }
        if (request.url.path.contains('/rpc/')) {
          bodies.add(request.body);
          rpcs++;
          if (rpcs == 1) throw http.ClientException('private-token SQL detail');
          return _json(
            _summary()
              ..['status'] = 'assigned'
              ..['version'] = 2,
          );
        }
        if (request.method == 'DELETE') {
          deletes++;
        } else {
          uploads++;
        }
        return _json({'Key': 'uploaded'});
      });
      final draft = _draft(photos: true);
      await expectLater(app.repo.createRequest(draft), throwsA(_uncertain));
      expect(deletes, 0);
      final receipt = await app.repo.createRequest(draft);
      expect(receipt.status, RepairStatus.assigned);
      expect(bodies[0], bodies[1]);
      expect(uploads, 1);
      expect(infoCalls, 1);
      expect(deletes, 0);
    },
  );

  test(
    'uncertain request can restore missing staging without changing IDs',
    () async {
      var rpcs = 0, uploads = 0;
      final bodies = <String>[];
      final app = await open((request) async {
        if (request.url.path.contains('/object/info/')) {
          return _storageMissing();
        }
        if (request.url.path.contains('/rpc/')) {
          rpcs++;
          bodies.add(request.body);
          if (rpcs == 1) return _error('XX000', 500);
          if (rpcs == 2) {
            return _error('22023', 400, message: 'INVALID_REQUEST_PHOTOS');
          }
          return _json(_summary());
        }
        expect(request.method, 'POST');
        uploads++;
        return _json({'Key': 'uploaded'});
      });
      final draft = _draft(photos: true);
      await expectLater(app.repo.createRequest(draft), throwsA(_uncertain));
      await app.repo.createRequest(draft);
      expect(uploads, 2);
      expect(rpcs, 3);
      expect(bodies.toSet(), hasLength(1));
    },
  );

  test(
    'duplicate taps share one RPC and request ID reuse rejects changed payload',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final app = await open((_) async {
        calls++;
        return response.future;
      });
      final draft = _draft();
      final a = app.repo.createRequest(draft),
          b = app.repo.createRequest(draft);
      response.complete(_json(_summary()));
      expect((await a).id, _request);
      expect((await b).id, _request);
      expect(calls, 1);
      await expectLater(
        app.repo.createRequest(_draft(title: 'Changed')),
        throwsA(_safe),
      );
      expect(calls, 1);
    },
  );

  test('changed original bytes cannot alter an uncertain retry', () async {
    final bytes = Uint8List.fromList(_png);
    final app = await open((request) async {
      if (request.url.path.contains('/object/info/')) return _storageMissing();
      if (request.url.path.contains('/rpc/')) {
        throw http.ClientException('lost response');
      }
      return _json({'Key': 'uploaded'});
    });
    final draft = _draft(
      attachments: [AttachmentDraft(name: 'x.png', bytes: bytes)],
    );
    await expectLater(app.repo.createRequest(draft), throwsA(_uncertain));
    bytes[11] = 99;
    await expectLater(app.repo.createRequest(draft), throwsA(_uncertain));
  });

  test(
    'malformed create receipt is uncertain; definite input error is not',
    () async {
      for (final malformed in [true, false]) {
        final app = await open(
          (_) async => malformed ? _json({}) : _error('22023', 400),
        );
        await expectLater(
          app.repo.createRequest(_draft()),
          throwsA(
            isA<RequestFailure>().having(
              (e) => e.uncertain,
              'uncertain',
              malformed,
            ),
          ),
        );
      }
    },
  );

  for (final operation in ['list', 'detail', 'upload', 'create']) {
    for (final switchBack in [false, true]) {
      test(
        'in-flight $operation rejects identity switch including switch-back=$switchBack',
        () async {
          final started = Completer<void>(),
              response = Completer<http.Response>();
          final app = await open((request) async {
            if (operation == 'upload' &&
                request.url.path.contains('/object/info/')) {
              return _storageMissing();
            }
            started.complete();
            return response.future;
          });
          final Future<Object> pending = switch (operation) {
            'list' => app.repo.fetchMyRequests(),
            'detail' => app.repo.fetchRequestDetail(_request),
            _ => app.repo.createRequest(_draft(photos: operation == 'upload')),
          };
          final expectation = expectLater(pending, throwsA(_denied));
          await started.future;
          await app.client.auth.setInitialSession(_session(userId: _other));
          if (switchBack) await app.client.auth.setInitialSession(_session());
          response.complete(
            _json(switch (operation) {
              'list' => [_summary()],
              'detail' => _detail(),
              _ => _summary(),
            }),
          );
          await expectation;
        },
      );
    }
  }

  test(
    'same-user token refresh keeps a valid read and emits no access change',
    () async {
      final started = Completer<void>(), response = Completer<http.Response>();
      final app = await open((_) async {
        started.complete();
        return response.future;
      });
      var invalidations = 0;
      final subscription = app.repo.accessChanges.listen(
        (_) => invalidations++,
      );
      final pending = app.repo.fetchMyRequests();
      await started.future;
      await app.client.auth.setInitialSession(_session(signature: 'renewed'));
      response.complete(_json([_summary()]));
      expect(await pending, hasLength(1));
      expect(invalidations, 0);
      await app.client.auth.setInitialSession(_session(userId: _other));
      await Future<void>.delayed(Duration.zero);
      expect(invalidations, 1);
      await subscription.cancel();
    },
  );

  test('private image rechecks detail then downloads bytes with JWT', () async {
    final calls = <http.Request>[];
    final app = await open((request) async {
      calls.add(request);
      return request.url.path.contains('/rpc/')
          ? _json(_detail())
          : http.Response.bytes(
              _png,
              200,
              headers: {'content-type': 'image/png'},
            );
    });
    final bytes = await app.repo.fetchAttachment(_request, _attachment());
    expect(bytes, _png);
    expect(calls, hasLength(2));
    expect(calls.last.url.path, '/storage/v1/object/repair-images/$_path');
    expect(calls.last.headers['authorization'], startsWith('Bearer '));
    expect(() => bytes[0] = 0, throwsUnsupportedError);
  });

  test('forged attachment cannot trigger a Storage download', () async {
    var calls = 0;
    final app = await open((request) async {
      calls++;
      expect(request.url.path, contains('/rpc/'));
      return _json(_detail());
    });
    await expectLater(
      app.repo.fetchAttachment(
        _request,
        RequestAttachment(
          id: _photo,
          storagePath: 'foreign.png',
          mimeType: 'image/png',
          sizeBytes: _png.length,
        ),
      ),
      throwsA(_denied),
    );
    expect(calls, 1);
  });

  test(
    'private image bytes are discarded after logout while download is pending',
    () async {
      final started = Completer<void>(), response = Completer<http.Response>();
      final app = await open((request) async {
        if (request.url.path == '/auth/v1/logout') {
          return http.Response('', 204);
        }
        if (request.url.path.contains('/rpc/')) return _json(_detail());
        started.complete();
        return response.future;
      });
      final pending = app.repo.fetchAttachment(_request, _attachment());
      final expectation = expectLater(pending, throwsA(_denied));
      await started.future;
      await app.client.auth.signOut(scope: SignOutScope.local);
      response.complete(http.Response.bytes(_png, 200));
      await expectation;
    },
  );

  test(
    'server and transport errors never expose SQL, token or private details',
    () async {
      final errors = <Object>[
        _error('42501', 403),
        _error('P0002', 404),
        _error('XX000', 500),
        http.ClientException('secret-token SQL private phone'),
      ];
      final app = await open((_) async {
        final error = errors.removeAt(0);
        if (error is http.Response) return error;
        throw error;
      });
      for (var i = 0; i < 4; i++) {
        await expectLater(
          app.repo.fetchMyRequests(),
          throwsA(
            isA<RequestFailure>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('secret-token')),
            ),
          ),
        );
      }
    },
  );

  test(
    'inactive room/category errors explain the available next action',
    () async {
      final messages = [
        'ACTIVE_STUDENT_ROOM_REQUIRED',
        'ACTIVE_CATEGORY_REQUIRED',
      ];
      final app = await open(
        (_) async => _error('22023', 400, message: messages.removeAt(0)),
      );
      await expectLater(
        app.repo.createRequest(_draft()),
        throwsA(
          isA<RequestFailure>()
              .having(
                (e) => e.message,
                'room advice',
                contains('liên hệ Admin'),
              )
              .having((e) => e.uncertain, 'definite rejection', isFalse),
        ),
      );
      await expectLater(
        app.repo.createRequest(_draft()),
        throwsA(
          isA<RequestFailure>().having(
            (e) => e.message,
            'category advice',
            contains('chọn loại khác'),
          ),
        ),
      );
    },
  );

  test(
    'later writes are disabled without any fallback or direct table call',
    () async {
      var calls = 0;
      final app = await open((_) async {
        calls++;
        return _json({});
      });
      await expectLater(
        app.repo.updateRequest(
          const EditRepairRequest(
            requestId: _request,
            title: 'x',
            categoryId: _category,
            description: 'y',
          ),
        ),
        throwsA(_safe),
      );
      await expectLater(
        app.repo.cancelRequest(requestId: _request, reason: 'x'),
        throwsA(_safe),
      );
      expect(calls, 0);
    },
  );
}

final _safe = isA<RequestFailure>();
final _denied = isA<RequestFailure>().having(
  (e) => e.accessDenied,
  'accessDenied',
  isTrue,
);
final _uncertain = isA<RequestFailure>().having(
  (e) => e.uncertain,
  'uncertain',
  isTrue,
);
const _path = 'student-requests/$_student/$_request/$_photo.png';
const _resultPath = 'technician-results/result.png';
const _feedbackPath = 'student-feedback/feedback.png';
NewRepairRequest _draft({
  bool photos = false,
  List<AttachmentDraft>? attachments,
  String title = ' Đèn bị hỏng ',
}) => NewRepairRequest(
  requestId: _request,
  title: title,
  categoryId: _category,
  description: ' Đèn không sáng ',
  attachments:
      attachments ??
      (photos
          ? [
              AttachmentDraft(
                name: 'untrusted-name.jpg',
                bytes: Uint8List.fromList(_png),
              ),
            ]
          : []),
);
Map<String, dynamic> _summary() => {
  'id': _request,
  'student_id': _student,
  'request_code': 'DF000001',
  'title': 'Đèn bị hỏng',
  'category_name': 'Điện',
  'room_code': 'DEMO-A101',
  'status': 'pending',
  'created_at': '2026-11-09T17:00:00+07:00',
  'version': 1,
};
RequestAttachment _attachment() => RequestAttachment(
  id: _photo,
  storagePath: _path,
  mimeType: 'image/png',
  sizeBytes: _png.length,
);
Map<String, dynamic> _detail() => {
  'request': _summary()
    ..['description'] = 'Đèn không sáng'
    ..['category_id'] = _category,
  'technician': {'full_name': 'Kỹ thuật viên Demo', 'phone': '0901111111'},
  'attachments': [
    {
      'id': _photo,
      'storage_path': _path,
      'mime_type': 'image/png',
      'size_bytes': _png.length,
      'result_id': null,
      'feedback_id': null,
    },
    {
      'id': '88888888-8888-4888-8888-888888888888',
      'storage_path': _resultPath,
      'mime_type': 'image/png',
      'size_bytes': _png.length,
      'result_id': _result,
      'feedback_id': null,
    },
    {
      'id': '99999999-9999-4999-8999-999999999999',
      'storage_path': _feedbackPath,
      'mime_type': 'image/png',
      'size_bytes': _png.length,
      'result_id': null,
      'feedback_id': _feedback,
    },
  ],
  'results': [
    {
      'id': _result,
      'content': 'Đã sửa đèn',
      'submitted_at': '2026-11-09T11:00:00Z',
      'technician_name': 'Kỹ thuật viên Demo',
    },
  ],
  'feedback': [
    {
      'id': _feedback,
      'kind': 'rework',
      'reason': 'Nước vẫn rò',
      'created_at': '2026-11-09T12:00:00Z',
      'author_name': 'Sinh viên Demo',
    },
  ],
  'history': [
    {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'action': 'created',
      'actor_id': _student,
      'actor_name': 'Sinh viên Demo',
      'old_status': null,
      'new_status': 'pending',
      'note': null,
      'occurred_at': '2026-11-09T10:00:00Z',
    },
  ],
};
Map<String, dynamic> _info(String path) => {
  'id': _photo,
  'version': '1',
  'name': path,
  'bucket_id': 'repair-images',
  'size': _png.length,
  'content_type': 'image/png',
  'created_at': '2026-11-09T10:00:00Z',
  'cache_control': '0',
  'etag': 'test-etag',
};
http.Response _storageMissing() => _json({
  'statusCode': '404',
  'error': 'not_found',
  'message': 'Object not found',
}, status: 404);
http.Response _error(
  String code,
  int status, {
  String message = 'secret-token SQL private phone',
}) => _json({'code': code, 'message': message}, status: status);
http.Response _json(Object? body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
String _session({
  bool expired = false,
  String userId = _student,
  String signature = 'student-request-test',
}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry =
      DateTime.now()
          .add(expired ? const Duration(hours: -1) : const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  return jsonEncode({
    'access_token':
        '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': userId, 'role': 'authenticated', 'exp': expiry})}.$signature',
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
}
