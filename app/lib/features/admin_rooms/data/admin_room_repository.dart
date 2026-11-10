import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/admin_catalog_failure.dart';
import '../../../core/data/admin_catalog_rpc.dart';
import '../models/admin_room.dart';

abstract interface class AdminRoomRepository {
  Future<List<AdminRoom>> fetchRooms();
  Future<void> addRoom({required String code, required String building});
  Future<void> updateRoom({
    required String roomId,
    required String code,
    required String building,
  });
  Future<void> deactivateRoom(AdminRoom room);
}

class SupabaseAdminRoomRepository implements AdminRoomRepository {
  SupabaseAdminRoomRepository(SupabaseClient client)
    : _rpc = AdminCatalogRpc(client);

  final AdminCatalogRpc _rpc;

  @override
  Future<List<AdminRoom>> fetchRooms() => _rpc.call(
    'admin_list_rooms',
    (data) => List<AdminRoom>.unmodifiable((data as List).map(_room)),
    readError: 'Không thể tải danh sách phòng. Vui lòng thử lại.',
  );

  @override
  Future<void> addRoom({required String code, required String building}) async {
    final input = _roomInput(code, building);
    await _write(
      'admin_create_room',
      {'p_code': input.code, 'p_building': input.building},
      (room) =>
          room.isActive &&
          room.code == input.code &&
          room.building == input.building,
      requireChange: true,
    );
  }

  @override
  Future<void> updateRoom({
    required String roomId,
    required String code,
    required String building,
  }) async {
    final input = _roomInput(code, building);
    await _write(
      'admin_update_room',
      {'p_room_id': roomId, 'p_code': input.code, 'p_building': input.building},
      (room) =>
          room.id == roomId &&
          room.code == input.code &&
          room.building == input.building,
    );
  }

  @override
  Future<void> deactivateRoom(AdminRoom room) => _write(
    'admin_deactivate_room',
    {'p_room_id': room.id},
    (saved) => saved.id == room.id && !saved.isActive,
  );

  Future<void> _write(
    String function,
    Map<String, dynamic> params,
    bool Function(AdminRoom) matches, {
    bool requireChange = false,
  }) => _rpc.call(
    function,
    (data) {
      final row = Map<String, dynamic>.from(data as Map);
      final changed = row['changed'];
      if (changed is! bool ||
          (requireChange && !changed) ||
          !matches(_room(row))) {
        throw const FormatException('Invalid room receipt.');
      }
    },
    params: params,
    readError: 'Không thể lưu thông tin phòng.',
    write: true,
  );

  static AdminRoom _room(Object? row) =>
      AdminRoom.fromJson(Map<String, dynamic>.from(row as Map));
}

class UnavailableAdminRoomRepository implements AdminRoomRepository {
  const UnavailableAdminRoomRepository();

  @override
  Future<List<AdminRoom>> fetchRooms() async =>
      throw AdminCatalogFailure.unavailable;

  @override
  Future<void> addRoom({
    required String code,
    required String building,
  }) async => throw AdminCatalogFailure.unavailable;

  @override
  Future<void> updateRoom({
    required String roomId,
    required String code,
    required String building,
  }) async => throw AdminCatalogFailure.unavailable;

  @override
  Future<void> deactivateRoom(AdminRoom room) async =>
      throw AdminCatalogFailure.unavailable;
}

class MockAdminRoomRepository implements AdminRoomRepository {
  MockAdminRoomRepository({Iterable<AdminRoom>? rooms})
    : _rooms = List.of(rooms ?? const []);

  final List<AdminRoom> _rooms;
  int _nextId = 0;

  @override
  Future<List<AdminRoom>> fetchRooms() async => List.unmodifiable(_rooms);

  @override
  Future<void> addRoom({required String code, required String building}) async {
    final input = _roomInput(code, building);
    _checkUnique(input.code);
    String id;
    do {
      id = 'mock-room-${_nextId++}';
    } while (_rooms.any((room) => room.id == id));
    _rooms.add(
      AdminRoom(
        id: id,
        code: input.code,
        building: input.building,
        isActive: true,
      ),
    );
  }

  @override
  Future<void> updateRoom({
    required String roomId,
    required String code,
    required String building,
  }) async {
    final input = _roomInput(code, building);
    final index = _index(roomId);
    _checkUnique(input.code, except: roomId);
    final old = _rooms[index];
    _rooms[index] = AdminRoom(
      id: roomId,
      code: input.code,
      building: input.building,
      isActive: old.isActive,
      studentNames: old.studentNames,
    );
  }

  @override
  Future<void> deactivateRoom(AdminRoom room) async {
    final index = _index(room.id);
    final current = _rooms[index];
    if (!current.isActive) return;
    if (current.studentNames.isNotEmpty) {
      throw const AdminCatalogFailure(
        'Phòng vẫn còn sinh viên.',
        conflict: true,
      );
    }
    _rooms[index] = AdminRoom(
      id: current.id,
      code: current.code,
      building: current.building,
      isActive: false,
    );
  }

  int _index(String id) {
    final index = _rooms.indexWhere((room) => room.id == id);
    if (index < 0) {
      throw const AdminCatalogFailure('Không tìm thấy phòng.', conflict: true);
    }
    return index;
  }

  void _checkUnique(String code, {String? except}) {
    if (_rooms.any(
      (room) =>
          room.id != except &&
          room.code.trim().toLowerCase() == code.toLowerCase(),
    )) {
      throw const AdminCatalogFailure('Mã phòng đã tồn tại.');
    }
  }
}

({String code, String building}) _roomInput(String code, String building) {
  final input = (code: code.trim(), building: building.trim());
  if (input.code.isEmpty || input.building.isEmpty) {
    throw const AdminCatalogFailure('Mã phòng và tòa nhà không được để trống.');
  }
  return input;
}
