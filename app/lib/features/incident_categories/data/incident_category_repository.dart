import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/admin_catalog_failure.dart';
import '../../../core/data/admin_catalog_rpc.dart';
import '../models/incident_category_item.dart';

abstract interface class IncidentCategoryRepository {
  Future<List<IncidentCategoryItem>> fetchAllCategories();
  Future<void> addCategory(String name);
  Future<void> updateCategory(String id, String newName);
  Future<void> toggleCategoryStatus(String id, bool currentStatus);
}

class SupabaseIncidentCategoryRepository implements IncidentCategoryRepository {
  SupabaseIncidentCategoryRepository(SupabaseClient client)
    : _rpc = AdminCatalogRpc(client);

  final AdminCatalogRpc _rpc;

  @override
  Future<List<IncidentCategoryItem>> fetchAllCategories() => _rpc.call(
    'admin_list_incident_categories',
    (data) =>
        List<IncidentCategoryItem>.unmodifiable((data as List).map(_category)),
    readError: 'Không thể tải loại sự cố. Vui lòng thử lại.',
  );

  @override
  Future<void> addCategory(String name) async {
    final trimmed = _categoryName(name);
    await _write(
      'admin_create_incident_category',
      {'p_name': trimmed},
      (category) => category.name == trimmed && category.isActive,
      requireChange: true,
    );
  }

  @override
  Future<void> updateCategory(String id, String newName) async {
    final trimmed = _categoryName(newName);
    await _write('admin_rename_incident_category', {
      'p_category_id': id,
      'p_name': trimmed,
    }, (category) => category.id == id && category.name == trimmed);
  }

  @override
  Future<void> toggleCategoryStatus(String id, bool currentStatus) => _write(
    'admin_set_incident_category_active',
    {'p_category_id': id, 'p_is_active': !currentStatus},
    (category) => category.id == id && category.isActive == !currentStatus,
  );

  Future<void> _write(
    String function,
    Map<String, dynamic> params,
    bool Function(IncidentCategoryItem) matches, {
    bool requireChange = false,
  }) => _rpc.call(
    function,
    (data) {
      final row = Map<String, dynamic>.from(data as Map);
      final changed = row['changed'];
      if (changed is! bool ||
          (requireChange && !changed) ||
          !matches(_category(row))) {
        throw const FormatException('Invalid category receipt.');
      }
    },
    params: params,
    readError: 'Không thể lưu thông tin loại sự cố.',
    write: true,
  );

  static IncidentCategoryItem _category(Object? row) =>
      IncidentCategoryItem.fromJson(Map<String, dynamic>.from(row as Map));
}

class UnavailableIncidentCategoryRepository
    implements IncidentCategoryRepository {
  const UnavailableIncidentCategoryRepository();

  @override
  Future<List<IncidentCategoryItem>> fetchAllCategories() async =>
      throw AdminCatalogFailure.unavailable;

  @override
  Future<void> addCategory(String name) async =>
      throw AdminCatalogFailure.unavailable;

  @override
  Future<void> updateCategory(String id, String newName) async =>
      throw AdminCatalogFailure.unavailable;

  @override
  Future<void> toggleCategoryStatus(String id, bool currentStatus) async =>
      throw AdminCatalogFailure.unavailable;
}

class MockIncidentCategoryRepository implements IncidentCategoryRepository {
  MockIncidentCategoryRepository({Iterable<IncidentCategoryItem>? categories})
    : _categories = List.of(categories ?? const []);

  final List<IncidentCategoryItem> _categories;
  int _nextId = 0;

  @override
  Future<List<IncidentCategoryItem>> fetchAllCategories() async =>
      List.unmodifiable(_categories);

  @override
  Future<void> addCategory(String name) async {
    final trimmed = _categoryName(name);
    _checkUnique(trimmed);
    String id;
    do {
      id = 'mock-category-${_nextId++}';
    } while (_categories.any((category) => category.id == id));
    _categories.add(
      IncidentCategoryItem(
        id: id,
        name: trimmed,
        isActive: true,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateCategory(String id, String newName) async {
    final trimmed = _categoryName(newName);
    final index = _index(id);
    _checkUnique(trimmed, except: id);
    final old = _categories[index];
    _categories[index] = IncidentCategoryItem(
      id: id,
      name: trimmed,
      isActive: old.isActive,
      createdAt: old.createdAt,
    );
  }

  @override
  Future<void> toggleCategoryStatus(String id, bool currentStatus) async {
    final index = _index(id);
    final old = _categories[index];
    _categories[index] = IncidentCategoryItem(
      id: id,
      name: old.name,
      isActive: !currentStatus,
      createdAt: old.createdAt,
    );
  }

  int _index(String id) {
    final index = _categories.indexWhere((category) => category.id == id);
    if (index < 0) {
      throw const AdminCatalogFailure(
        'Không tìm thấy loại sự cố.',
        conflict: true,
      );
    }
    return index;
  }

  void _checkUnique(String name, {String? except}) {
    if (_categories.any(
      (category) =>
          category.id != except &&
          category.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      throw const AdminCatalogFailure('Tên loại sự cố đã tồn tại.');
    }
  }
}

String _categoryName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw const AdminCatalogFailure('Tên loại sự cố không được để trống.');
  }
  return trimmed;
}
