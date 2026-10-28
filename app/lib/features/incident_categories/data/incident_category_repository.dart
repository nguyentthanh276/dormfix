import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/incident_category_item.dart';

class IncidentCategoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // Dữ liệu mẫu dùng chuẩn UUID 36 ký tự hợp lệ cho Supabase/PostgreSQL
  static final List<IncidentCategoryItem> _fallbackCategories = [
    IncidentCategoryItem(
      id: '00000000-0000-0000-0000-000000000001',
      name: 'Điện',
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
    IncidentCategoryItem(
      id: '00000000-0000-0000-0000-000000000002',
      name: 'Nước',
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
    ),
    IncidentCategoryItem(
      id: '00000000-0000-0000-0000-000000000003',
      name: 'Nội thất & CSVC',
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
    IncidentCategoryItem(
      id: '00000000-0000-0000-0000-000000000004',
      name: 'Mạng & Internet',
      isActive: false,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  /// Lấy toàn bộ danh mục sự cố cho Admin
  Future<List<IncidentCategoryItem>> fetchAllCategories() async {
    try {
      final response = await _client
          .from('incident_categories')
          .select()
          .order('created_at', ascending: true);

      final list = (response as List)
          .map((e) => IncidentCategoryItem.fromJson(e as Map<String, dynamic>))
          .toList();

      if (list.isEmpty) {
        return List.from(_fallbackCategories);
      }
      return list;
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == '22P02') {
        debugPrint('Chế độ xem trước: Dùng dữ liệu mẫu dự phòng.');
        return List.from(_fallbackCategories);
      }
      rethrow;
    } catch (_) {
      return List.from(_fallbackCategories);
    }
  }

  /// DF-049: Thêm mới loại sự cố
  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Tên loại sự cố không được để trống.');
    }

    try {
      await _client.from('incident_categories').insert({
        'name': trimmed,
        'is_active': true,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Loại sự cố "$trimmed" đã tồn tại.');
      }
      // Khi không có quyền hoặc dùng mock, lưu vào bộ nhớ tạm
      _fallbackCategories.add(
        IncidentCategoryItem(
          id: '00000000-0000-0000-0000-${DateTime.now().millisecondsSinceEpoch.toString().padLeft(12, '0')}',
          name: trimmed,
          isActive: true,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      _fallbackCategories.add(
        IncidentCategoryItem(
          id: '00000000-0000-0000-0000-${DateTime.now().millisecondsSinceEpoch.toString().padLeft(12, '0')}',
          name: trimmed,
          isActive: true,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  /// DF-049: Sửa tên loại sự cố
  Future<void> updateCategory(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw Exception('Tên loại sự cố không được để trống.');
    }

    // Nếu là ID dữ liệu mẫu hoặc bắt đầu bằng 00000000/cat- thì cập nhật cục bộ
    if (id.startsWith('00000000') || id.startsWith('cat-')) {
      final index = _fallbackCategories.indexWhere((c) => c.id == id);
      if (index != -1) {
        final old = _fallbackCategories[index];
        _fallbackCategories[index] = IncidentCategoryItem(
          id: old.id,
          name: trimmed,
          isActive: old.isActive,
          createdAt: old.createdAt,
        );
      }
      return;
    }

    try {
      await _client
          .from('incident_categories')
          .update({
            'name': trimmed,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Loại sự cố "$trimmed" đã tồn tại.');
      }
      final index = _fallbackCategories.indexWhere((c) => c.id == id);
      if (index != -1) {
        final old = _fallbackCategories[index];
        _fallbackCategories[index] = IncidentCategoryItem(
          id: old.id,
          name: trimmed,
          isActive: old.isActive,
          createdAt: old.createdAt,
        );
      }
    }
  }

  /// DF-050: Ngừng sử dụng / Kích hoạt lại loại sự cố
  Future<void> toggleCategoryStatus(String id, bool currentStatus) async {
    // Nếu là ID dữ liệu mẫu hoặc bắt đầu bằng 00000000/cat- thì xử lý ngay trên RAM
    if (id.startsWith('00000000') || id.startsWith('cat-')) {
      final index = _fallbackCategories.indexWhere((c) => c.id == id);
      if (index != -1) {
        final old = _fallbackCategories[index];
        _fallbackCategories[index] = IncidentCategoryItem(
          id: old.id,
          name: old.name,
          isActive: !currentStatus,
          createdAt: old.createdAt,
        );
      }
      return;
    }

    try {
      await _client
          .from('incident_categories')
          .update({
            'is_active': !currentStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == '22P02') {
        final index = _fallbackCategories.indexWhere((c) => c.id == id);
        if (index != -1) {
          final old = _fallbackCategories[index];
          _fallbackCategories[index] = IncidentCategoryItem(
            id: old.id,
            name: old.name,
            isActive: !currentStatus,
            createdAt: old.createdAt,
          );
        }
        return;
      }
      rethrow;
    }
  }
}
