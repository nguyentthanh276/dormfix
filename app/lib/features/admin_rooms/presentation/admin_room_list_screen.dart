import 'package:flutter/material.dart';
import '../data/admin_room_repository.dart';
import '../models/admin_room.dart';

class AdminRoomListScreen extends StatefulWidget {
  const AdminRoomListScreen({super.key});

  @override
  State<AdminRoomListScreen> createState() => _AdminRoomListScreenState();
}

class _AdminRoomListScreenState extends State<AdminRoomListScreen> {
  final _repo = AdminRoomRepository();
  List<AdminRoom> _rooms = [];
  String _searchQuery = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _repo.fetchRooms();
      setState(() => _rooms = list);
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

  List<AdminRoom> get _filteredRooms {
    if (_searchQuery.trim().isEmpty) return _rooms;
    return _rooms
        .where((r) => r.code.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  void _showRoomDialog([AdminRoom? room]) {
    final codeCtrl = TextEditingController(text: room?.code ?? '');
    final buildingCtrl = TextEditingController(text: room?.building ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(room == null ? 'Thêm phòng mới' : 'Cập nhật phòng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Mã phòng (VD: A101)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: buildingCtrl,
              decoration: const InputDecoration(labelText: 'Tòa nhà (VD: Tòa A)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              try {
                if (room == null) {
                  await _repo.addRoom(code: codeCtrl.text, building: buildingCtrl.text);
                } else {
                  await _repo.updateRoom(roomId: room.id, code: codeCtrl.text, building: buildingCtrl.text);
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
    final list = _filteredRooms;
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý phòng KTX')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRoomDialog(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm kiếm theo mã phòng...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(child: Text('Không tìm thấy phòng nào.'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final room = list[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: room.isActive ? Colors.blue.shade50 : Colors.grey.shade300,
                                child: Text(room.building, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              title: Text('Phòng: ${room.code}'),
                              subtitle: Text(
                                'Sinh viên: ${room.studentNames.isEmpty ? "Trống" : room.studentNames.join(", ")}\n'
                                'Trạng thái: ${room.isActive ? "Đang hoạt động" : "Ngừng sử dụng"}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    _showRoomDialog(room);
                                  } else if (action == 'deactivate') {
                                    try {
                                      await _repo.deactivateRoom(room);
                                      _load();
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                                        );
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                                  if (room.isActive)
                                    const PopupMenuItem(value: 'deactivate', child: Text('Ngừng sử dụng')),
                                ],
                              ),
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