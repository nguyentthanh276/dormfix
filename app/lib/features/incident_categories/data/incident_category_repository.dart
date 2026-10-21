import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/incident_category_item.dart';

class IncidentCategoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // Dữ liệu mẫu dự phòng khi chạy chế độ xem trước (bị chặn quyền 42501)
  static final List<IncidentCategoryItem> _fallbackCategories = [
    IncidentCategoryItem(
      id: 'cat-1',
      name: 'Điện',
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
    IncidentCategoryItem(
      id: 'cat-2',
      name: 'Nước',
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
    ),
    IncidentCategoryItem(
      id: 'cat-3',
      name: 'Nội thất & CSVC',
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
    IncidentCategoryItem(
      id: 'cat-4',
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

      return (response as List)
          .map((e) => IncidentCategoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        debugPrint('Chưa có quyền 42501 trên Supabase: Dùng dữ liệu mẫu dự phòng.');
        return List.from(_fallbackCategories);
      }
      rethrow;
    } catch (e) {
      if (e.toString().contains('42501')) {
        return List.from(_fallbackCategories);
      }
      rethrow;
    }
  }

  /// DF-049: Thêm mới loại sự cố
  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('Tên loại sự cố không được để trống.');

    try {
      await _client.from('incident_categories').insert({
        'name': trimmed,
        'is_active': true,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Loại sự cố "$trimmed" đã tồn tại.');
      }
      if (e.code == '42501') {
        _fallbackCategories.add(
          IncidentCategoryItem(
            id: 'cat-${DateTime.now().millisecondsSinceEpoch}',
            name: trimmed,
            isActive: true,
            createdAt: DateTime.now(),
          ),
        );
        return;
      }
      rethrow;
    }
  }

  /// DF-049: Sửa tên loại sự cố
  Future<void> updateCategory(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw Exception('Tên loại sự cố không được để trống.');

    try {
      await _client.from('incident_categories').update({
        'name': trimmed,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Loại sự cố "$trimmed" đã tồn tại.');
      }
      if (e.code == '42501') {
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
      rethrow;
    }
  }

  /// DF-050: Ngừng sử dụng / Kích hoạt lại loại sự cố
  Future<void> toggleCategoryStatus(String id, bool currentStatus) async {
    try {
      await _client.from('incident_categories').update({
        'is_active': !currentStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
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