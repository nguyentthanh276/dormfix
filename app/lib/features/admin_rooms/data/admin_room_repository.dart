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
      studentNames: ['Nguyễn Văn An'],
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
      studentNames: [],
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
}
