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
  List<IncidentCategoryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _repo.fetchAllCategories();
      setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddEditDialog([IncidentCategoryItem? item]) {
    final controller = TextEditingController(text: item?.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item == null ? 'Thêm loại sự cố' : 'Sửa loại sự cố'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Tên loại sự cố'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                if (item == null) {
                  await _repo.addCategory(controller.text);
                } else {
                  await _repo.updateCategory(item.id, controller.text);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                  );
                }
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý loại sự cố')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final cat = _items[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cat.isActive ? Colors.green.shade50 : Colors.grey.shade200,
                    child: Icon(
                      Icons.category_outlined,
                      color: cat.isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                  title: Text(
                    cat.name,
                    style: TextStyle(
                      decoration: cat.isActive ? null : TextDecoration.lineThrough,
                      color: cat.isActive ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  subtitle: Text(cat.isActive ? 'Đang hoạt động' : 'Ngừng sử dụng'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showAddEditDialog(cat),
                      ),
                      Switch(
                        value: cat.isActive,
                        onChanged: (_) async {
                          await _repo.toggleCategoryStatus(cat.id, cat.isActive);
                          _load();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}