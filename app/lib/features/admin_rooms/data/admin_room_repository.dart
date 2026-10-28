import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_room.dart';

class AdminRoomRepository {
  // Tránh gọi Supabase.instance.client trực tiếp tại biến khởi tạo
  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  // Dữ liệu mẫu dự phòng khi chạy preview chưa đăng nhập hoặc chưa kết nối Supabase
  static final List<AdminRoom> _fallbackRooms = [
    AdminRoom(
      id: 'room-1',
      code: 'DEMO-A101',
      building: 'Tòa A',
      isActive: true,
      studentNames: ['Nguyễn Văn An'], // Phòng có SV -> Test chặn xóa DF-042
    ),
    AdminRoom(
      id: 'room-2',
      code: 'A2-305',
      building: 'Tòa A',
      isActive: true,
      studentNames: ['Lê Văn Cường', 'Trần Bảo Ngọc'],
    ),
    AdminRoom(
      id: 'room-3',
      code: 'B1-112',
      building: 'Tòa B',
      isActive: true,
      studentNames: [], // Phòng trống -> Cho phép ngừng dùng thành công DF-042
    ),
    AdminRoom(
      id: 'room-4',
      code: 'C3-210',
      building: 'Tòa C',
      isActive: false,
      studentNames: [],
    ),
  ];

  /// DF-039: Lấy danh sách phòng kèm thông tin sinh viên
  Future<List<AdminRoom>> fetchRooms() async {
    final client = _client;
    if (client == null) {
      return List.from(_fallbackRooms);
    }

    try {
      final response = await client
          .from('rooms')
          .select('id, code, building, is_active, profiles(full_name)')
          .order('code', ascending: true);

      return (response as List)
          .map((e) => AdminRoom.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        debugPrint(
          'Chưa có quyền 42501 trên Supabase: Dùng dữ liệu phòng mẫu dự phòng.',
        );
        return List.from(_fallbackRooms);
      }
      rethrow;
    } catch (e) {
      debugPrint('Lỗi tải danh sách phòng, dùng dữ liệu mẫu: $e');
      return List.from(_fallbackRooms);
    }
  }

  /// DF-040: Thêm phòng mới
  Future<void> addRoom({required String code, required String building}) async {
    final trimmedCode = code.trim();
    final trimmedBuilding = building.trim();
    if (trimmedCode.isEmpty || trimmedBuilding.isEmpty) {
      throw Exception('Mã phòng và tòa nhà không được để trống.');
    }

    final client = _client;
    if (client == null) {
      final isExist = _fallbackRooms.any(
        (r) => r.code.toUpperCase() == trimmedCode.toUpperCase(),
      );
      if (isExist) {
        throw Exception('Mã phòng "$trimmedCode" đã tồn tại.');
      }

      _fallbackRooms.add(
        AdminRoom(
          id: 'room-${DateTime.now().millisecondsSinceEpoch}',
          code: trimmedCode,
          building: trimmedBuilding,
          isActive: true,
          studentNames: [],
        ),
      );
      return;
    }

    try {
      await client.from('rooms').insert({
        'code': trimmedCode,
        'building': trimmedBuilding,
        'is_active': true,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Mã phòng "$trimmedCode" đã tồn tại.');
      }
      if (e.code == '42501') {
        final isExist = _fallbackRooms.any(
          (r) => r.code.toUpperCase() == trimmedCode.toUpperCase(),
        );
        if (isExist) {
          throw Exception('Mã phòng "$trimmedCode" đã tồn tại.');
        }

        _fallbackRooms.add(
          AdminRoom(
            id: 'room-${DateTime.now().millisecondsSinceEpoch}',
            code: trimmedCode,
            building: trimmedBuilding,
            isActive: true,
            studentNames: [],
          ),
        );
        return;
      }
      rethrow;
    }
  }

  /// DF-041: Cập nhật thông tin phòng
  Future<void> updateRoom({
    required String roomId,
    required String code,
    required String building,
  }) async {
    final trimmedCode = code.trim();
    final trimmedBuilding = building.trim();
    if (trimmedCode.isEmpty || trimmedBuilding.isEmpty) {
      throw Exception('Mã phòng và tòa nhà không được để trống.');
    }

    final client = _client;
    if (client == null) {
      final index = _fallbackRooms.indexWhere((r) => r.id == roomId);
      if (index != -1) {
        final old = _fallbackRooms[index];
        _fallbackRooms[index] = AdminRoom(
          id: old.id,
          code: trimmedCode,
          building: trimmedBuilding,
          isActive: old.isActive,
          studentNames: old.studentNames,
        );
      }
      return;
    }

    try {
      await client
          .from('rooms')
          .update({
            'code': trimmedCode,
            'building': trimmedBuilding,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', roomId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Mã phòng "$trimmedCode" đã tồn tại.');
      }
      if (e.code == '42501') {
        final index = _fallbackRooms.indexWhere((r) => r.id == roomId);
        if (index != -1) {
          final old = _fallbackRooms[index];
          _fallbackRooms[index] = AdminRoom(
            id: old.id,
            code: trimmedCode,
            building: trimmedBuilding,
            isActive: old.isActive,
            studentNames: old.studentNames,
          );
        }
        return;
      }
      rethrow;
    }
  }

  /// DF-042: Ngừng sử dụng phòng (Kiểm tra chặn nếu còn sinh viên)
  Future<void> deactivateRoom(AdminRoom room) async {
    if (room.studentNames.isNotEmpty) {
      throw Exception(
        'Không thể ngừng sử dụng phòng ${room.code} vì vẫn còn ${room.studentNames.length} sinh viên đang ở. Vui lòng chuyển sinh viên sang phòng khác trước.',
      );
    }

    final client = _client;
    if (client == null) {
      final index = _fallbackRooms.indexWhere((r) => r.id == room.id);
      if (index != -1) {
        final old = _fallbackRooms[index];
        _fallbackRooms[index] = AdminRoom(
          id: old.id,
          code: old.code,
          building: old.building,
          isActive: false,
          studentNames: old.studentNames,
        );
      }
      return;
    }

    try {
      await client
          .from('rooms')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', room.id);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        final index = _fallbackRooms.indexWhere((r) => r.id == room.id);
        if (index != -1) {
          final old = _fallbackRooms[index];
          _fallbackRooms[index] = AdminRoom(
            id: old.id,
            code: old.code,
            building: old.building,
            isActive: false,
            studentNames: old.studentNames,
          );
        }
        return;
      }
      rethrow;
    }
  }
}