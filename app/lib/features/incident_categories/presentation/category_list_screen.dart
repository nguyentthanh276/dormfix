import 'package:flutter/material.dart';

import '../../../core/data/admin_catalog_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/admin_catalog_dialog.dart';
import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/error_view.dart';

import '../data/incident_category_repository.dart';
import '../models/incident_category_item.dart';

class CategoryListScreen extends StatefulWidget {
  const CategoryListScreen({
    super.key,
    required this.repository,
    this.embedded = false,
  });

  final IncidentCategoryRepository repository;
  final bool embedded;

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  final _searchCtrl = TextEditingController();
  List<IncidentCategoryItem> _items = [];
  String _searchQuery = '';
  bool _loading = true;
  bool _changingStatus = false;
  int _loadGeneration = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CategoryListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _items = [];
      _changingStatus = false;
      _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await widget.repository.fetchAllCategories();
      if (mounted && generation == _loadGeneration) {
        setState(() => _items = list);
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _items = [];
          _loadError = error is AdminCatalogFailure
              ? error.message
              : 'Không thể tải danh mục. Vui lòng thử lại.';
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  // Tự động gán Icon và Màu sắc sinh động theo tên loại sự cố
  Map<String, dynamic> _getCategoryVisual(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('điện')) {
      return {'icon': Icons.bolt_rounded, 'color': const Color(0xFFF59E0B)};
    }
    if (lower.contains('nước')) {
      return {
        'icon': Icons.water_drop_rounded,
        'color': const Color(0xFF0284C7),
      };
    }
    if (lower.contains('nội thất') ||
        lower.contains('csvc') ||
        lower.contains('bàn') ||
        lower.contains('ghế')) {
      return {'icon': Icons.chair_rounded, 'color': const Color(0xFF8B5CF6)};
    }
    if (lower.contains('mạng') ||
        lower.contains('internet') ||
        lower.contains('wifi')) {
      return {'icon': Icons.wifi_rounded, 'color': const Color(0xFF10B981)};
    }
    if (lower.contains('khóa') || lower.contains('cửa')) {
      return {
        'icon': Icons.door_front_door_rounded,
        'color': const Color(0xFF64748B),
      };
    }
    return {'icon': Icons.category_rounded, 'color': AppColors.primaryDark};
  }

  List<IncidentCategoryItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((c) => c.name.toLowerCase().contains(query)).toList();
  }

  Future<void> _showAddEditDialog([IncidentCategoryItem? item]) async {
    final repository = widget.repository;
    var name = item?.name ?? '';
    final result = await showDialog<AdminCatalogDialogResult>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => AdminCatalogDialog(
        title: item == null ? 'Thêm loại sự cố mới' : 'Sửa loại sự cố',
        submitLabel: item == null ? 'Thêm mới' : 'Cập nhật',
        fields: (enabled) => TextFormField(
          initialValue: item?.name,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Tên loại sự cố *'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Vui lòng nhập tên loại sự cố.'
              : null,
          onSaved: (value) => name = value!.trim(),
        ),
        onSave: () => item == null
            ? repository.addCategory(name)
            : repository.updateCategory(item.id, name),
      ),
    );
    if (!mounted || repository != widget.repository || result == null) return;
    await _load();
  }

  Future<void> _setCategoryStatus(IncidentCategoryItem item) async {
    if (_changingStatus) return;
    final repository = widget.repository;
    setState(() => _changingStatus = true);
    try {
      await repository.toggleCategoryStatus(item.id, item.isActive);
      if (mounted && repository == widget.repository) await _load();
    } catch (error) {
      if (!mounted || repository != widget.repository) return;
      final failure = error is AdminCatalogFailure ? error : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure?.message ??
                'Chưa xác nhận được kết quả. Đang tải lại danh mục.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (failure == null ||
          failure.accessDenied ||
          failure.conflict ||
          failure.uncertain) {
        await _load();
      }
    } finally {
      if (mounted && repository == widget.repository) {
        setState(() => _changingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredItems;
    const primaryColor = AppColors.primaryDark;

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Expanded(child: Text("Danh mục sự cố")),
              FilledButton.icon(
                onPressed: _loading || _loadError != null || _changingStatus
                    ? null
                    : () => _showAddEditDialog(),
                icon: const Icon(Icons.add),
                label: const Text("Thêm loại"),
              ),
            ],
          ),
        ),
        // KHUNG TÌM KIẾM BO TRÒN HIỆN ĐẠI
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Tìm kiếm tên loại sự cố...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.search_rounded, color: primaryColor),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 16,
              ),
              filled: true,
              fillColor: const Color(0xFFF1F3F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),

        // DANH SÁCH LOẠI SỰ CỐ
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(primaryColor),
                  ),
                )
              : _loadError != null
              ? ErrorView(message: _loadError!, onRetry: _load)
              : list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 56,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Chưa có loại sự cố nào.'
                            : 'Không tìm thấy loại sự cố phù hợp.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    key: const PageStorageKey("admin-categories-list"),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final cat = list[index];
                      final visual = _getCategoryVisual(cat.name);
                      final catIcon = visual['icon'] as IconData;
                      final catColor = visual['color'] as Color;

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cat.isActive
                                ? const Color(0xFFE9ECEF)
                                : Colors.red.shade100,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            // Icon đại diện theo màu sắc danh mục
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: cat.isActive
                                    ? catColor.withValues(alpha: 0.12)
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                catIcon,
                                color: cat.isActive
                                    ? catColor
                                    : Colors.grey.shade500,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Tên sự cố & Badge trạng thái
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat.name,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: cat.isActive
                                          ? const Color(0xFF2B2D42)
                                          : Colors.grey.shade500,
                                      decoration: cat.isActive
                                          ? null
                                          : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: cat.isActive
                                              ? const Color(0xFF2E7D32)
                                              : const Color(0xFFC62828),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          cat.isActive
                                              ? 'Đang hoạt động'
                                              : 'Ngừng sử dụng',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: cat.isActive
                                                ? const Color(0xFF2E7D32)
                                                : const Color(0xFFC62828),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Nút Chỉnh sửa
                            IconButton(
                              tooltip: 'Chỉnh sửa tên',
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: Colors.blueGrey,
                              ),
                              onPressed: _changingStatus
                                  ? null
                                  : () => _showAddEditDialog(cat),
                            ),

                            // Công tắc Bật / Tắt trạng thái
                            Switch.adaptive(
                              activeTrackColor: primaryColor,
                              value: cat.isActive,
                              onChanged: _changingStatus
                                  ? null
                                  : (_) => _setCategoryStatus(cat),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: const DormFixAppBar(title: "Loại sự cố", roleLabel: "Admin"),
      body: body,
    );
  }
}
