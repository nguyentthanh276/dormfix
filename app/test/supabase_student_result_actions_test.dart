import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/student_confirmation/models/student_confirmation_submission.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/data/request_repository.dart';
import 'package:dormfix/features/student_requests/data/supabase_request_repository.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_rules.dart';
import 'package:dormfix/features/student_requests/models/student_request_id.dart';
import 'package:dormfix/features/student_requests/models/student_request_mutation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _student = '33333333-3333-4333-8333-333333333333';
const _other = '44444444-4444-4444-8444-444444444444';
const _request = '11111111-1111-4111-8111-111111111111';
const _action = '77777777-7777-4777-8777-777777777777';
const _category = '22222222-2222-4222-8222-222222222222';
const _oldPhoto = '55555555-5555-4555-8555-555555555555';
const _key = 'sb_publishable_student_result_tests';
const _version = 8;
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

  test(
    'submission trims note and freezes attachment list and original bytes',
    () {
      final bytes = Uint8List.fromList(_png);
      final photos = [AttachmentDraft(name: 'photo.png', bytes: bytes)];
      final submission = _draft(attachments: photos, note: '  Vẫn rò nước  ');
      bytes[11] = 99;
      photos.clear();
      expect(submission.note, 'Vẫn rò nước');
      expect(submission.attachments.single.bytes, _png);
      expect(() => submission.attachments.clear(), throwsUnsupportedError);
      expect(
        () => submission.attachments.single.bytes[0] = 0,
        throwsUnsupportedError,
      );
      expect(_draft(note: '  ').note, isNull);
    },
  );

  test(
    'legacy repository hides unsupported confirmation and never fakes success',
    () async {
      final repo = MockRequestRepository();
      expect(repo.supportsConfirmationActions, isFalse);
      await expectLater(repo.submitConfirmation(_draft()), throwsA(_safe));
    },
  );

  for (final note in [null, ' Đã sửa tốt ']) {
    test(
      'confirm calls only RPC with current JWT and optional note ($note)',
      () async {
        final calls = <http.Request>[];
        final app = await open((request) async {
          calls.add(request);
          return _json(_receipt(rework: false));
        });
        final receipt = await app.repo.submitConfirmation(
          _draft(action: StudentResultAction.confirmFixed, note: note),
        );
        expect(app.repo.supportsConfirmationActions, isTrue);
        expect(receipt.requestId, _request);
        expect(receipt.actionId, _action);
        expect(receipt.status, RepairStatus.completed);
        expect(receipt.version, _version + 1);
        expect(receipt.feedbackId, isNull);
        expect(receipt.replayed, isFalse);
        expect(calls, hasLength(1));
        final request = calls.single;
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/student_confirm_result');
        expect(request.headers['authorization'], startsWith('Bearer '));
        expect(request.headers['apikey'], _key);
        expect(jsonDecode(request.body), {
          'p_request_id': _request,
          'p_expected_version': _version,
          'p_action_id': _action,
          'p_note': note?.trim(),
        });
      },
    );
  }

  test('rework reason is required but photos are optional', () async {
    final app = await open((request) async {
      expect(request.url.path, '/rest/v1/rpc/student_request_rework');
      expect(jsonDecode(request.body), {
        'p_request_id': _request,
        'p_expected_version': _version,
        'p_action_id': _action,
        'p_reason': 'Vẫn rò nước',
        'p_photos': [],
      });
      return _json(_receipt());
    });
    final receipt = await app.repo.submitConfirmation(_draft());
    expect(receipt.status, RepairStatus.awaitingRework);
    expect(receipt.feedbackId, _action);
  });

  test('rework stages private signed-in bytes under version and action UUIDs', () async {
    final calls = <http.Request>[];
    Map<String, dynamic>? manifest;
    final app = await open((request) async {
      calls.add(request);
      if (_isInfo(request)) return _missing();
      if (_isRpc(request)) {
        manifest = Map<String, dynamic>.from(
          (jsonDecode(request.body)['p_photos'] as List).single as Map,
        );
        return _json(_receipt());
      }
      return _json({'Key': 'uploaded'});
    });
    await app.repo.submitConfirmation(_draft(photos: true));
    final photo = manifest!;
    expect(isStudentRequestId(photo['id'] as String), isTrue);
    expect(
      photo['storage_path'],
      'student-feedback/$_student/$_request/$_version/$_action/${photo['id']}.png',
    );
    expect(photo['mime_type'], 'image/png');
    expect(photo['size_bytes'], _png.length);
    final upload = calls[1];
    expect(upload.method, 'POST');
    expect(
      upload.url.path,
      '/storage/v1/object/repair-images/${photo['storage_path']}',
    );
    expect(upload.headers['x-upsert'], 'false');
    expect(upload.headers['authorization'], startsWith('Bearer '));
    expect(latin1.decode(upload.bodyBytes), contains(latin1.decode(_png)));
    expect(latin1.decode(upload.bodyBytes), contains('image/png'));
    expect(calls.map((r) => r.method), ['GET', 'POST', 'POST']);
  });

  test('invalid identities, versions, reason and photo payloads stop before network', () async {
    var calls = 0;
    final app = await open((_) async {
      calls++;
      return _json({});
    });
    final invalid = [
      _draft(actionId: 'bad'),
      _draft(requestId: 'bad'),
      _draft(version: 0),
      _draft(version: 2147483647),
      _draft(note: '  '),
      _draft(action: StudentResultAction.confirmFixed, photos: true),
      _draft(attachments: List.generate(6, (_) => _photo())),
      _draft(
        attachments: [AttachmentDraft(name: 'x.png', bytes: Uint8List(0))],
      ),
      _draft(
        attachments: [
          AttachmentDraft(name: 'x.png', bytes: Uint8List.fromList([1, 2, 3])),
        ],
      ),
      _draft(
        attachments: [
          AttachmentDraft(
            name: 'x.png',
            bytes: Uint8List(RequestRules.maxImageBytes + 1),
          ),
        ],
      ),
    ];
    for (final draft in invalid) {
      await expectLater(app.repo.submitConfirmation(draft), throwsA(_safe));
    }
    expect(calls, 0);
  });

  for (final expired in [false, true]) {
    test('missing or expired auth prevents result writes ($expired)', () async {
      var calls = 0;
      final app = await open(
        (_) async {
          calls++;
          return _json(_receipt());
        },
        withSession: expired,
        expired: expired,
      );
      await expectLater(
        app.repo.submitConfirmation(_draft(photos: true)),
        throwsA(_denied),
      );
      expect(calls, 0);
    });
  }

  for (final rework in [false, true]) {
    test(
      'unknown commit replays same RPC before Storage and never deletes ($rework)',
      () async {
        var rpcCalls = 0;
        final calls = <http.Request>[];
        final bodies = <String>[];
        final app = await open((request) async {
          calls.add(request);
          if (_isInfo(request)) return _missing();
          if (_isRpc(request)) {
            bodies.add(request.body);
            if (++rpcCalls == 1) throw http.ClientException('secret SQL token');
            return _json(_receipt(rework: rework, replayed: true));
          }
          return _json({'Key': 'uploaded'});
        });
        final draft = _draft(
          action: rework
              ? StudentResultAction.requestRework
              : StudentResultAction.confirmFixed,
          photos: rework,
        );
        await expectLater(
          app.repo.submitConfirmation(draft),
          throwsA(_uncertain),
        );
        final firstCallCount = calls.length;
        final receipt = await app.repo.submitConfirmation(draft);
        expect(receipt.replayed, isTrue);
        expect(receipt.version, _version + 1);
        expect(calls.length, firstCallCount + 1);
        expect(_isRpc(calls.last), isTrue);
        expect(bodies.toSet(), hasLength(1));
        expect(calls.where((r) => r.method == 'DELETE'), isEmpty);
      },
    );
  }

  test(
    'uncertain rework restores missing staging with exactly the same manifest',
    () async {
      var rpcs = 0, uploads = 0;
      final bodies = <String>[];
      final paths = <String>[];
      final app = await open((request) async {
        if (_isInfo(request)) return _missing();
        if (_isRpc(request)) {
          bodies.add(request.body);
          if (++rpcs == 1) return _error('XX000');
          if (rpcs == 2) {
            return _error('22023', message: 'INVALID_FEEDBACK_PHOTOS');
          }
          return _json(_receipt());
        }
        expect(request.method, 'POST');
        uploads++;
        paths.add(request.url.path);
        return _json({'Key': 'uploaded'});
      });
      final draft = _draft(photos: true);
      await expectLater(
        app.repo.submitConfirmation(draft),
        throwsA(_uncertain),
      );
      await app.repo.submitConfirmation(draft);
      expect(uploads, 2);
      expect(rpcs, 3);
      expect(bodies.toSet(), hasLength(1));
      expect(paths.toSet(), hasLength(1));
    },
  );

  test(
    'double tap coalesces and reused action UUID cannot change payload',
    () async {
      var calls = 0;
      final started = Completer<void>(), response = Completer<http.Response>();
      final app = await open((_) async {
        calls++;
        started.complete();
        return response.future;
      });
      final draft = _draft();
      final a = app.repo.submitConfirmation(draft);
      final b = app.repo.submitConfirmation(_draft());
      await started.future;
      response.complete(_json(_receipt()));
      expect((await a).actionId, _action);
      expect((await b).actionId, _action);
      expect(calls, 1);
      for (final changed in [
        _draft(note: 'Nội dung khác'),
        _draft(version: _version + 1),
        _draft(action: StudentResultAction.confirmFixed),
        _draft(requestId: _other),
      ]) {
        await expectLater(
          app.repo.submitConfirmation(changed),
          throwsA(_conflict),
        );
      }
      expect(calls, 1);
    },
  );

  test('original mutable bytes cannot change uncertain frozen retry', () async {
    final bytes = Uint8List.fromList(_png);
    final bodies = <String>[];
    final app = await open((request) async {
      if (_isInfo(request)) return _missing();
      if (_isRpc(request)) {
        bodies.add(request.body);
        if (bodies.length == 1) throw http.ClientException('lost');
        return _json(_receipt(replayed: true));
      }
      expect(latin1.decode(request.bodyBytes), contains(latin1.decode(_png)));
      return _json({'Key': 'uploaded'});
    });
    final draft = _draft(
      attachments: [AttachmentDraft(name: 'x.png', bytes: bytes)],
    );
    await expectLater(app.repo.submitConfirmation(draft), throwsA(_uncertain));
    bytes[11] = 99;
    await app.repo.submitConfirmation(draft);
    expect(bodies[0], bodies[1]);
  });

  test(
    'changed uncertain action remains uncertain and conflict is explicit',
    () async {
      var calls = 0;
      final app = await open((_) async {
        calls++;
        throw http.ClientException('lost response');
      });
      await expectLater(
        app.repo.submitConfirmation(_draft()),
        throwsA(_uncertain),
      );
      await expectLater(
        app.repo.submitConfirmation(_draft(note: 'Changed')),
        throwsA(_conflict.having((e) => e.uncertain, 'uncertain', isTrue)),
      );
      expect(calls, 1);
    },
  );

  test('malformed or wrong action receipts stay uncertain and retain staged photos', () async {
    final malformed = [
      <String, dynamic>{},
      _receipt()..['request_id'] = _other,
      _receipt()..['action_id'] = _other,
      _receipt()..['status'] = 'completed',
      _receipt()..['version'] = _version + 2,
      _receipt()..['feedback_id'] = null,
      _receipt()..['replayed'] = 'true',
      _receipt()..remove('feedback_id'),
    ];
    for (final invalid in malformed) {
      var deletes = 0;
      final app = await open((request) async {
        if (_isInfo(request)) return _missing();
        if (_isRpc(request)) return _json(invalid);
        if (request.method == 'DELETE') deletes++;
        return _json({'Key': 'uploaded'});
      });
      await expectLater(
        app.repo.submitConfirmation(_draft(photos: true)),
        throwsA(_uncertain),
      );
      expect(deletes, 0);
    }
  });

  test('confirm receipt cannot claim a feedback record', () async {
    final app = await open(
      (_) async => _json(_receipt(rework: false)..['feedback_id'] = _action),
    );
    await expectLater(
      app.repo.submitConfirmation(
        _draft(action: StudentResultAction.confirmFixed),
      ),
      throwsA(_uncertain),
    );
  });

  for (final message in [
    'REQUEST_STATE_CONFLICT',
    'CONFIRMATION_NOT_READY',
    'ACTION_REPLAY_MISMATCH',
  ]) {
    test('server conflict is explicit and definitive: $message', () async {
      final app = await open((_) async => _error('P0001', message: message));
      await expectLater(
        app.repo.submitConfirmation(_draft()),
        throwsA(_conflict.having((e) => e.uncertain, 'uncertain', isFalse)),
      );
    });
  }

  test(
    'definitive state conflict cleans only own uncommitted staged manifest',
    () async {
      final paths = <String>[];
      List<dynamic>? cleanup;
      final app = await open((request) async {
        if (_isInfo(request)) return _missing();
        if (_isRpc(request)) {
          paths.add(
            (jsonDecode(request.body)['p_photos'] as List)
                    .single['storage_path']
                as String,
          );
          return _error('P0001', message: 'REQUEST_STATE_CONFLICT');
        }
        if (request.method == 'DELETE') {
          cleanup = jsonDecode(request.body)['prefixes'] as List;
          return _json([]);
        }
        return _json({'Key': 'uploaded'});
      });
      await expectLater(
        app.repo.submitConfirmation(_draft(photos: true)),
        throwsA(_conflict),
      );
      expect(cleanup, paths);
      expect(
        cleanup!.single,
        startsWith('student-feedback/$_student/$_request/$_version/$_action/'),
      );
    },
  );

  test('previous unknown commit stays uncertain after conflict and does not clean up', () async {
    var rpcs = 0, deletes = 0;
    final app = await open((request) async {
      if (_isInfo(request)) return _missing();
      if (_isRpc(request)) {
        if (++rpcs == 1) throw http.ClientException('lost');
        return _error('P0001', message: 'REQUEST_STATE_CONFLICT');
      }
      if (request.method == 'DELETE') deletes++;
      return _json({'Key': 'uploaded'});
    });
    final draft = _draft(photos: true);
    await expectLater(app.repo.submitConfirmation(draft), throwsA(_uncertain));
    await expectLater(app.repo.submitConfirmation(draft), throwsA(_uncertain));
    expect(deletes, 0);
  });

  test(
    'matching staged object is reused; mismatching metadata never finalizes',
    () async {
      for (final mismatch in [false, true]) {
        var rpcs = 0, uploads = 0;
        final app = await open((request) async {
          if (_isInfo(request)) {
            final path = request.url.path.split('/repair-images/').last;
            return _json(_info(path)..['size'] = mismatch ? 999 : _png.length);
          }
          if (_isRpc(request)) {
            rpcs++;
            return _json(_receipt());
          }
          if (request.method == 'POST') uploads++;
          return _json([]);
        });
        final pending = app.repo.submitConfirmation(_draft(photos: true));
        if (mismatch) {
          await expectLater(pending, throwsA(_safe));
        } else {
          await pending;
        }
        expect(rpcs, mismatch ? 0 : 1);
        expect(uploads, 0);
      }
    },
  );

  for (final operation in ['confirm', 'rework-upload', 'rework-rpc']) {
    for (final switchBack in [false, true]) {
      test(
        'in-flight $operation rejects identity switch including switch-back=$switchBack',
        () async {
          final started = Completer<void>(),
              response = Completer<http.Response>();
          var deletes = 0;
          final app = await open((request) async {
            if (_isInfo(request)) return _missing();
            if (request.method == 'DELETE') {
              deletes++;
              return _json([]);
            }
            started.complete();
            return response.future;
          });
          final draft = _draft(
            action: operation == 'confirm'
                ? StudentResultAction.confirmFixed
                : StudentResultAction.requestRework,
            photos: operation == 'rework-upload',
          );
          final pending = app.repo.submitConfirmation(draft);
          final expectation = expectLater(pending, throwsA(_denied));
          await started.future;
          await app.client.auth.setInitialSession(_session(userId: _other));
          if (switchBack) await app.client.auth.setInitialSession(_session());
          response.complete(
            _json(
              operation == 'rework-upload'
                  ? {'Key': 'uploaded'}
                  : _receipt(rework: operation != 'confirm'),
            ),
          );
          await expectation;
          expect(deletes, 0);
        },
      );
    }
  }

  test('logout in flight rejects receipt without cleanup', () async {
    final started = Completer<void>(), response = Completer<http.Response>();
    final app = await open((request) async {
      if (request.url.path == '/auth/v1/logout') return http.Response('', 204);
      started.complete();
      return response.future;
    });
    final pending = app.repo.submitConfirmation(_draft());
    final expectation = expectLater(pending, throwsA(_denied));
    await started.future;
    await app.client.auth.signOut();
    response.complete(_json(_receipt()));
    await expectation;
  });

  test('same-user token refresh permits pending action and receipt', () async {
    final started = Completer<void>(), response = Completer<http.Response>();
    final app = await open((_) async {
      started.complete();
      return response.future;
    });
    final pending = app.repo.submitConfirmation(_draft());
    await started.future;
    await app.client.auth.setInitialSession(_session(signature: 'renewed'));
    response.complete(_json(_receipt()));
    expect((await pending).status, RepairStatus.awaitingRework);
  });

  test('role or ownership rejection never cleans staging or exposes server details', () async {
    for (final code in ['42501', 'P0002', '28000']) {
      var deletes = 0;
      final app = await open((request) async {
        if (_isInfo(request)) return _missing();
        if (_isRpc(request)) return _error(code);
        if (request.method == 'DELETE') deletes++;
        return _json({'Key': 'uploaded'});
      });
      await expectLater(
        app.repo.submitConfirmation(_draft(photos: true)),
        throwsA(_denied),
      );
      expect(deletes, 0);
    }
  });

  test('SQL transport and missing RPC errors remain redacted with correct uncertainty', () async {
    for (final error in [
      _error('PGRST202'),
      _error('22023', message: 'REWORK_REASON_REQUIRED'),
      _error('XX000'),
      http.ClientException('secret-token SQL private-user'),
    ]) {
      final app = await open((_) async {
        if (error is http.Response) return error;
        throw error;
      });
      await expectLater(
        app.repo.submitConfirmation(_draft()),
        throwsA(
          isA<RequestFailure>()
              .having(
                (e) => e.message,
                'redacted message',
                allOf(
                  isNot(contains('secret-token')),
                  isNot(contains('SQL')),
                  isNot(contains('private-user')),
                ),
              )
              .having(
                (e) => e.uncertain,
                'uncertain',
                error is! http.Response || error.statusCode == 500,
              ),
        ),
      );
    }
  });

  test('edit retains attachment IDs, stages only new bytes, and replays without Storage', () async {
    final calls = <http.Request>[];
    final retained = [_oldPhoto];
    final photo = _photo();
    final edit = _edit(keep: retained, attachments: [photo]);
    retained.clear();
    photo.bytes[11] = 99;
    var rpcs = 0;
    final app = await open((request) async {
      calls.add(request);
      if (_isInfo(request)) return _missing();
      if (_isRpc(request)) {
        return _json(_mutationReceipt(status: 'pending', replayed: ++rpcs > 1));
      }
      return _json({'Key': 'uploaded'});
    });
    final receipt = await app.repo.submitMutation(edit);
    expect(receipt.status, RepairStatus.pending);
    expect(receipt.feedbackId, isNull);
    expect(calls.map((r) => r.method), ['GET', 'POST', 'POST']);
    final rpc = calls.last;
    expect(rpc.url.path, '/rest/v1/rpc/student_edit_request');
    final body = jsonDecode(rpc.body) as Map<String, dynamic>;
    final photoId = body['p_photos'].single['id'] as String;
    final path =
        'student-request-edits/$_student/$_request/$_version/$_action/$photoId.png';
    expect(body, {
      'p_request_id': _request,
      'p_action_id': _action,
      'p_expected_version': _version,
      'p_title': 'Ổ điện không hoạt động',
      'p_category_id': _category,
      'p_description': 'Không có điện',
      'p_keep_attachment_ids': [_oldPhoto],
      'p_photos': [
        {
          'id': photoId,
          'storage_path': path,
          'mime_type': 'image/png',
          'size_bytes': _png.length,
        },
      ],
    });
    expect(calls[1].url.path, '/storage/v1/object/repair-images/$path');
    expect(latin1.decode(calls[1].bodyBytes), contains(latin1.decode(_png)));
    final replay = await app.repo.submitMutation(edit);
    expect(replay.replayed, isTrue);
    expect(calls, hasLength(4));
    expect(calls.last.body, rpc.body);
  });

  test(
    'cancel sends reason and version only, without touching Storage',
    () async {
      final app = await open((request) async {
        expect(request.url.path, '/rest/v1/rpc/student_cancel_request');
        expect(request.headers['authorization'], startsWith('Bearer '));
        expect(jsonDecode(request.body), {
          'p_request_id': _request,
          'p_expected_version': _version,
          'p_action_id': _action,
          'p_reason': 'Đã báo nhầm',
        });
        return _json(_mutationReceipt(status: 'cancelled'));
      });
      final receipt = await app.repo.submitMutation(_cancel());
      expect(receipt.status, RepairStatus.cancelled);
      expect(receipt.version, _version + 1);
    },
  );

  test('reopen preserves frozen feedback IDs and retries finalize before Storage', () async {
    final calls = <http.Request>[];
    var rpcCount = 0;
    final app = await open((request) async {
      calls.add(request);
      if (_isInfo(request)) return _missing();
      if (_isRpc(request)) {
        expect(request.url.path, '/rest/v1/rpc/student_reopen_request');
        if (++rpcCount == 1) throw http.ClientException('lost response');
        return _json(
          _mutationReceipt(
            status: 'pending',
            feedbackId: _action,
            replayed: true,
          ),
        );
      }
      return _json({'Key': 'uploaded'});
    });
    final draft = _reopen(photos: true);
    await expectLater(app.repo.submitMutation(draft), throwsA(_uncertain));
    final receipt = await app.repo.submitMutation(draft);
    expect(receipt.status, RepairStatus.pending);
    expect(receipt.feedbackId, _action);
    expect(receipt.replayed, isTrue);
    expect(calls.map((r) => r.method), ['GET', 'POST', 'POST', 'POST']);
    expect(calls[2].body, calls[3].body);
    final body = jsonDecode(calls.last.body);
    expect(body['p_reason'], 'Sự cố xuất hiện lại');
    final image = body['p_photos'].single;
    expect(
      image['storage_path'],
      'student-feedback/$_student/$_request/$_version/$_action/${image['id']}.png',
    );
  });

  test('edit restages missing photos only after definitive RPC response, with same manifest', () async {
    final bodies = <String>[];
    final uploaded = <String>[];
    final app = await open((request) async {
      if (_isInfo(request)) return _missing();
      if (_isRpc(request)) {
        bodies.add(request.body);
        if (bodies.length == 1) return _error('XX000');
        if (bodies.length == 2) {
          expect(uploaded, hasLength(1));
          return _error('22023', message: 'INVALID_REQUEST_PHOTOS');
        }
        return _json(_mutationReceipt(status: 'pending'));
      }
      expect(request.method, 'POST');
      uploaded.add(request.url.path);
      return _json({'Key': 'uploaded'});
    });
    final draft = _edit(keep: [_oldPhoto], attachments: [_photo()]);
    await expectLater(app.repo.submitMutation(draft), throwsA(_uncertain));
    await app.repo.submitMutation(draft);
    expect(bodies, hasLength(3));
    expect(bodies.toSet(), hasLength(1));
    expect(uploaded, hasLength(2));
    expect(uploaded.toSet(), hasLength(1));
  });

  test('invalid retained IDs, combined photo limit and empty reasons stop before network', () async {
    var calls = 0;
    final app = await open((_) async {
      calls++;
      return _json({});
    });
    for (final draft in [
      _edit(keep: ['https://not-a-photo-id.example']),
      _edit(keep: [_oldPhoto, _oldPhoto]),
      _edit(keep: [_oldPhoto], attachments: List.generate(5, (_) => _photo())),
      _cancel(reason: ' '),
      _reopen(reason: ' '),
    ]) {
      await expectLater(app.repo.submitMutation(draft), throwsA(_safe));
    }
    expect(calls, 0);
  });

  test(
    'reopen wrong-room and cancel assignment conflicts prompt refresh',
    () async {
      final app = await open((request) async {
        if (request.url.path.endsWith('student_reopen_request')) {
          return _error('P0001', message: 'REOPEN_ROOM_MISMATCH');
        }
        return _error('P0001', message: 'REQUEST_ASSIGNMENT_CONFLICT');
      });
      await expectLater(
        app.repo.submitMutation(_reopen()),
        throwsA(
          _conflict.having(
            (e) => e.message,
            'room guidance',
            contains('phòng hiện tại'),
          ),
        ),
      );
      await expectLater(
        app.repo.submitMutation(_cancel(actionId: _other)),
        throwsA(_conflict.having((e) => e.uncertain, 'uncertain', isFalse)),
      );
    },
  );

  test(
    'mutation and confirmation cannot reuse an action UUID in flight',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final app = await open((request) async {
        expect(request.url.path, '/rest/v1/rpc/student_cancel_request');
        started.complete();
        return response.future;
      });
      final pending = app.repo.submitMutation(_cancel());
      await started.future;
      await expectLater(
        app.repo.submitConfirmation(_draft()),
        throwsA(_conflict),
      );
      response.complete(_json(_mutationReceipt(status: 'cancelled')));
      expect((await pending).status, RepairStatus.cancelled);
    },
  );
}

final _safe = isA<RequestFailure>();
final _denied = _safe.having((e) => e.accessDenied, 'accessDenied', isTrue);
final _uncertain = _safe.having((e) => e.uncertain, 'uncertain', isTrue);
final _conflict = _safe.having((e) => e.conflict, 'conflict', isTrue);

StudentRequestMutation _edit({
  List<String> keep = const [],
  List<AttachmentDraft> attachments = const [],
}) => StudentRequestMutation.edit(
  actionId: _action,
  requestId: _request,
  expectedVersion: _version,
  title: ' Ổ điện không hoạt động ',
  categoryId: _category,
  description: ' Không có điện ',
  keepAttachmentIds: keep,
  attachments: attachments,
);

StudentRequestMutation _cancel({
  String actionId = _action,
  String reason = ' Đã báo nhầm ',
}) => StudentRequestMutation.cancel(
  actionId: actionId,
  requestId: _request,
  expectedVersion: _version,
  reason: reason,
);

StudentRequestMutation _reopen({
  String reason = ' Sự cố xuất hiện lại ',
  bool photos = false,
}) => StudentRequestMutation.reopen(
  actionId: _action,
  requestId: _request,
  expectedVersion: _version,
  reason: reason,
  attachments: photos ? [_photo()] : [],
);

Map<String, dynamic> _mutationReceipt({
  required String status,
  String? feedbackId,
  bool replayed = false,
}) => {
  'request_id': _request,
  'action_id': _action,
  'status': status,
  'version': _version + 1,
  'feedback_id': feedbackId,
  'replayed': replayed,
};

StudentConfirmationSubmission _draft({
  String actionId = _action,
  String requestId = _request,
  int version = _version,
  StudentResultAction action = StudentResultAction.requestRework,
  String? note = '  Vẫn rò nước  ',
  bool photos = false,
  List<AttachmentDraft>? attachments,
}) => StudentConfirmationSubmission(
  actionId: actionId,
  requestId: requestId,
  expectedVersion: version,
  action: action,
  note: note,
  attachments: attachments ?? (photos ? [_photo()] : []),
);

AttachmentDraft _photo() =>
    AttachmentDraft(name: 'photo.png', bytes: Uint8List.fromList(_png));
bool _isRpc(http.Request request) => request.url.path.contains('/rest/v1/rpc/');
bool _isInfo(http.Request request) =>
    request.url.path.contains('/object/info/');
Map<String, dynamic> _receipt({bool rework = true, bool replayed = false}) => {
  'request_id': _request,
  'action_id': _action,
  'status': rework ? 'awaiting_rework' : 'completed',
  'version': _version + 1,
  'feedback_id': rework ? _action : null,
  'replayed': replayed,
};
Map<String, dynamic> _info(String path) => {
  'id': _action,
  'version': '1',
  'name': path,
  'bucket_id': 'repair-images',
  'size': _png.length,
  'content_type': 'image/png',
  'created_at': '2026-11-10T10:00:00Z',
};
http.Response _missing() => _json({
  'statusCode': '404',
  'error': 'not_found',
  'message': 'Object not found',
}, status: 404);
http.Response _error(
  String code, {
  String message = 'secret-token SQL private-user',
}) => _json({
  'code': code,
  'message': message,
}, status: code == 'XX000' ? 500 : 400);
http.Response _json(Object? body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
String _session({
  bool expired = false,
  String userId = _student,
  String signature = 'student-result-test',
}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry =
      DateTime.now()
          .add(Duration(hours: expired ? -1 : 1))
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
      'created_at': '2026-11-10T00:00:00Z',
    },
  });
}
