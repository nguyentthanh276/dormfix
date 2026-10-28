import 'package:flutter/material.dart';

import '../data/incident_category_repository.dart';
import '../models/incident_category_item.dart';

class CategoryListScreen extends StatefulWidget {
  const CategoryListScreen({super.key});

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  final _repo = IncidentCategoryRepository();
  final _searchCtrl = TextEditingController();
  List<IncidentCategoryItem> _items = [];
  String _searchQuery = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _repo.fetchAllCategories();
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
    return {'icon': Icons.category_rounded, 'color': const Color(0xFFD35400)};
  }

  List<IncidentCategoryItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((c) => c.name.toLowerCase().contains(query)).toList();
  }

  void _showAddEditDialog([IncidentCategoryItem? item]) {
    final isEdit = item != null;
    final controller = TextEditingController(text: item?.name ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isEdit
                  ? Icons.edit_note_rounded
                  : Icons.add_circle_outline_rounded,
              color: const Color(0xFFD35400),
            ),
            const SizedBox(width: 8),
            Text(
              isEdit ? 'Sửa loại sự cố' : 'Thêm loại sự cố mới',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Tên loại sự cố *',
                  hintText: 'VD: Sự cố Điện, Hỏng điều hòa...',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Vui lòng nhập tên loại sự cố'
                    : null,
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD35400),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                if (!isEdit) {
                  await _repo.addCategory(controller.text.trim());
                } else {
                  await _repo.updateCategory(item.id, controller.text.trim());
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(isEdit ? 'Cập nhật' : 'Thêm mới'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredItems;
    const primaryColor = Color(0xFFD35400);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Quản lý loại sự cố',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _showAddEditDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Thêm sự cố',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // KHUNG TÌM KIẾM BO TRÒN HIỆN ĐẠI
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm tên loại sự cố...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: primaryColor,
                ),
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
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 85),
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
                                      Text(
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
                              onPressed: () => _showAddEditDialog(cat),
                            ),

                            // Công tắc Bật / Tắt trạng thái
                            Switch.adaptive(
                              activeThumbColor: primaryColor,
                              value: cat.isActive,
                              onChanged: (val) async {
                                try {
                                  await _repo.toggleCategoryStatus(
                                    cat.id,
                                    cat.isActive,
                                  );
                                  _load();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Lỗi: ${e.toString()}'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
