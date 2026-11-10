import 'dart:async';
import 'dart:convert';

import 'package:dormfix/core/data/admin_catalog_failure.dart';
import 'package:dormfix/features/admin_rooms/data/admin_room_repository.dart';
import 'package:dormfix/features/admin_rooms/models/admin_room.dart';
import 'package:dormfix/features/incident_categories/data/incident_category_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _admin = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';
const _roomId = '33333333-3333-4333-8333-333333333333';
const _categoryId = '44444444-4444-4444-8444-444444444444';

void main() {
  Future<SupabaseClient> client(
    FutureOr<http.Response> Function(http.Request) handler, {
    bool signedIn = true,
  }) async {
    final client = SupabaseClient(
      'https://dormfix.test',
      'sb_publishable_catalog_test',
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

  test(
    'rooms use only guarded RPCs and validate names and persisted changes',
    () async {
      final calls = <List<Object?>>[];
      final supabase = await client((request) {
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer ${_token(_admin)}');
        final name = request.url.pathSegments.last;
        expect(request.url.path, '/rest/v1/rpc/$name');
        calls.add([name, jsonDecode(request.body)]);
        return _json(switch (name) {
          'admin_list_rooms' => [
            _room(names: ['Sinh viên A']),
            _room(code: 'B102', active: false),
          ],
          'admin_create_room' => {..._room(code: 'B101'), 'changed': true},
          'admin_update_room' => {..._room(code: 'B103'), 'changed': true},
          'admin_deactivate_room' => {
            ..._room(code: 'B103', active: false),
            'changed': false,
          },
          _ => throw StateError('Unexpected RPC.'),
        });
      });
      final repository = SupabaseAdminRoomRepository(supabase);
      final rooms = await repository.fetchRooms();
      expect(rooms.first.studentNames, ['Sinh viên A']);
      expect(rooms.last.isActive, isFalse);
      expect(() => rooms.first.studentNames.clear(), throwsUnsupportedError);
      await repository.addRoom(code: ' B101 ', building: ' B ');
      await repository.updateRoom(
        roomId: _roomId,
        code: ' B103 ',
        building: ' B ',
      );
      // The server decides occupancy even if the screen has an older room snapshot.
      await repository.deactivateRoom(rooms.first);
      expect(calls, [
        ['admin_list_rooms', null],
        [
          'admin_create_room',
          {'p_code': 'B101', 'p_building': 'B'},
        ],
        [
          'admin_update_room',
          {'p_room_id': _roomId, 'p_code': 'B103', 'p_building': 'B'},
        ],
        [
          'admin_deactivate_room',
          {'p_room_id': _roomId},
        ],
      ]);
    },
  );

  test(
    'categories preserve inactive rows and send desired state explicitly',
    () async {
      final calls = <List<Object?>>[];
      final supabase = await client((request) {
        expect(request.method, 'POST');
        final name = request.url.pathSegments.last;
        expect(request.url.path, '/rest/v1/rpc/$name');
        final params = jsonDecode(request.body);
        calls.add([name, params]);
        return _json(switch (name) {
          'admin_list_incident_categories' => [_category(active: false)],
          'admin_create_incident_category' => {..._category(), 'changed': true},
          'admin_rename_incident_category' => {
            ..._category(name: 'Điện lạnh'),
            'changed': true,
          },
          'admin_set_incident_category_active' => {
            ..._category(
              name: 'Điện lạnh',
              active: params['p_is_active'] as bool,
            ),
            'changed': false,
          },
          _ => throw StateError('Unexpected RPC.'),
        });
      });
      final repository = SupabaseIncidentCategoryRepository(supabase);
      final inactive = (await repository.fetchAllCategories()).single;
      expect(inactive.isActive, isFalse);
      expect(inactive.createdAt, DateTime.utc(2026, 11, 9, 10));
      await repository.addCategory(' Điện ');
      await repository.updateCategory(_categoryId, ' Điện lạnh ');
      await repository.toggleCategoryStatus(_categoryId, true);
      await repository.toggleCategoryStatus(_categoryId, false);
      expect(calls, [
        ['admin_list_incident_categories', null],
        [
          'admin_create_incident_category',
          {'p_name': 'Điện'},
        ],
        [
          'admin_rename_incident_category',
          {'p_category_id': _categoryId, 'p_name': 'Điện lạnh'},
        ],
        [
          'admin_set_incident_category_active',
          {'p_category_id': _categoryId, 'p_is_active': false},
        ],
        [
          'admin_set_incident_category_active',
          {'p_category_id': _categoryId, 'p_is_active': true},
        ],
      ]);
    },
  );

  test('missing session does not issue reads or writes', () async {
    var calls = 0;
    final supabase = await client((_) {
      calls++;
      return _json([]);
    }, signedIn: false);
    final rooms = SupabaseAdminRoomRepository(supabase);
    final categories = SupabaseIncidentCategoryRepository(supabase);
    await expectLater(rooms.fetchRooms(), throwsA(_denied));
    await expectLater(categories.fetchAllCategories(), throwsA(_denied));
    await expectLater(
      rooms.addRoom(code: 'B1', building: 'B'),
      throwsA(_denied),
    );
    await expectLater(categories.addCategory('Điện'), throwsA(_denied));
    expect(calls, 0);
  });

  test(
    'permission, occupancy, duplicate and missing RPC failures never fall back',
    () async {
      final replies = [
        _error('42501', 'secret-token'),
        _error('PGRST202', 'internal RPC name'),
        _error('P0001', 'ROOM_HAS_STUDENTS'),
        _error('23505', 'ROOM_CODE_ALREADY_EXISTS'),
        _error('23505', 'CATEGORY_NAME_ALREADY_EXISTS'),
        _error('P0002', 'CATEGORY_NOT_FOUND'),
      ];
      final supabase = await client((_) => replies.removeAt(0));
      final rooms = SupabaseAdminRoomRepository(supabase);
      final categories = SupabaseIncidentCategoryRepository(supabase);
      await expectLater(rooms.fetchRooms(), throwsA(_denied));
      await expectLater(
        categories.fetchAllCategories(),
        throwsA(AdminCatalogFailure.unavailable),
      );
      await expectLater(
        rooms.deactivateRoom(_emptyRoom),
        throwsA(_failure.having((e) => e.conflict, 'conflict', true)),
      );
      await expectLater(
        rooms.addRoom(code: 'B101', building: 'B'),
        throwsA(_message('đã tồn tại')),
      );
      await expectLater(
        categories.addCategory('Điện'),
        throwsA(_message('đã tồn tại')),
      );
      await expectLater(
        categories.updateCategory(_categoryId, 'Điện'),
        throwsA(_failure.having((e) => e.conflict, 'conflict', true)),
      );
      expect(replies, isEmpty);
    },
  );

  test('malformed reads and unknown write outcomes fail safely', () async {
    var call = 0;
    final supabase = await client((_) {
      call++;
      return switch (call) {
        1 => _json([_room()..['student_count'] = 1]),
        2 => _json({..._category(), 'changed': 'true'}),
        3 => _json({..._room(), 'id': _other, 'changed': true}),
        _ => throw http.ClientException('secret-token private host'),
      };
    });
    final rooms = SupabaseAdminRoomRepository(supabase);
    final categories = SupabaseIncidentCategoryRepository(supabase);
    final uncertain = _failure.having((e) => e.uncertain, 'uncertain', true);
    await expectLater(
      rooms.fetchRooms(),
      throwsA(_failure.having((e) => e.uncertain, 'uncertain', false)),
    );
    await expectLater(categories.addCategory('Điện'), throwsA(uncertain));
    await expectLater(
      rooms.updateRoom(roomId: _roomId, code: 'B101', building: 'B'),
      throwsA(uncertain),
    );
    await expectLater(
      categories.toggleCategoryStatus(_categoryId, false),
      throwsA(uncertain),
    );
    expect(call, 4);
  });

  for (final switchBack in [false, true]) {
    test(
      'pending Admin write discards receipt after identity change, switchBack=$switchBack',
      () async {
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final supabase = await client((request) {
          expect(request.headers['authorization'], 'Bearer ${_token(_admin)}');
          started.complete();
          return response.future;
        });
        final pending = SupabaseAdminRoomRepository(supabase)
            .addRoom(code: 'B101', building: 'B');
        final denied = expectLater(pending, throwsA(_denied));
        await started.future;
        await supabase.auth.setInitialSession(_session(userId: _other));
        if (switchBack) await supabase.auth.setInitialSession(_session());
        response.complete(_json({..._room(), 'changed': true}));
        await denied;
      },
    );
  }

  test('mocks are explicit and never share mutable fallback state', () async {
    final first = MockAdminRoomRepository(rooms: [_emptyRoom]);
    final second = MockAdminRoomRepository(rooms: [_emptyRoom]);
    await first.deactivateRoom(_emptyRoom);
    expect((await first.fetchRooms()).single.isActive, isFalse);
    expect((await second.fetchRooms()).single.isActive, isTrue);
    final firstCatalog = MockIncidentCategoryRepository();
    await firstCatalog.addCategory('Điện');
    expect(
      await MockIncidentCategoryRepository().fetchAllCategories(),
      isEmpty,
    );
    await expectLater(
      const UnavailableAdminRoomRepository().fetchRooms(),
      throwsA(AdminCatalogFailure.unavailable),
    );
    await expectLater(
      const UnavailableIncidentCategoryRepository().addCategory('Điện'),
      throwsA(AdminCatalogFailure.unavailable),
    );
  });
}

final _failure = isA<AdminCatalogFailure>().having(
  (failure) => failure.message,
  'safe message',
  isNot(contains('secret-token')),
);
final _denied = _failure.having(
  (failure) => failure.accessDenied,
  'accessDenied',
  true,
);
Matcher _message(String expected) =>
    _failure.having((e) => e.message, 'message', contains(expected));

final _emptyRoom = AdminRoom(
  id: _roomId,
  code: 'B101',
  building: 'B',
  isActive: true,
);

Map<String, dynamic> _room({
  String code = 'B101',
  bool active = true,
  List<String> names = const [],
}) => {
  'id': _roomId,
  'code': code,
  'building': 'B',
  'is_active': active,
  'student_count': names.length,
  'profiles': names.map((name) => {'full_name': name}).toList(),
};

Map<String, dynamic> _category({String name = 'Điện', bool active = true}) => {
  'id': _categoryId,
  'name': name,
  'is_active': active,
  'created_at': '2026-11-09T17:00:00+07:00',
};

http.Response _error(String code, String message) =>
    _json({'code': code, 'message': message}, status: 400);
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
  return "${part({'alg': 'HS256'})}.${part({'sub': userId, 'exp': 2147483647})}.catalog-test";
}
