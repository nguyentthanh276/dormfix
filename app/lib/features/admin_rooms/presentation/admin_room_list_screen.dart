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
  final _searchCtrl = TextEditingController();
  List<AdminRoom> _rooms = [];
  String _searchQuery = '';
  String _selectedBuilding = 'Tất cả';
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
      final list = await _repo.fetchRooms();
      if (mounted) setState(() => _rooms = list);
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

  // Danh sách tòa nhà
  List<String> get _availableBuildings {
    final buildings = _rooms.map((r) => r.building.trim()).toSet().toList();
    buildings.sort();
    return ['Tất cả', ...buildings];
  }

  // Hàm bỏ dấu tiếng Việt
  String _normalize(String text) {
    var str = text.toLowerCase().trim();
    const withDiacritics =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const withoutDiacritics =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    for (int i = 0; i < withDiacritics.length; i++) {
      str = str.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return str;
  }

  // Lấy ký tự định danh của tòa (ví dụ "Tòa A" -> "a")
  String _extractBuildingLetter(String building) {
    return _normalize(building).replaceAll(RegExp(r'^(toa|khu)\s*'), '').trim();
  }

  List<AdminRoom> get _filteredRooms {
    return _rooms.where((room) {
      // 1. Lọc theo Chip Tòa nhà được chọn
      if (_selectedBuilding != 'Tất cả') {
        if (_normalize(room.building) != _normalize(_selectedBuilding)) {
          return false;
        }
      }

      // 2. Lọc theo ô tìm kiếm
      final q = _normalize(_searchQuery);
      if (q.isEmpty) return true;

      final roomLetter = _extractBuildingLetter(room.building);
      final roomCode = _normalize(room.code);
      final roomBuilding = _normalize(room.building);

      // NẾU NGƯỜI DÙNG CHỈ GÕ 1 KÝ TỰ (VD: "a", "b", "c")
      if (q.length == 1) {
        // Chỉ chấp nhận: Tòa A hoặc Mã phòng bắt đầu bằng chữ cái đó (như A101, A2-305)
        return roomLetter == q || roomCode.startsWith(q);
      }

      // NẾU GÕ "toa a", "tòa a", "khu a"
      if (q.startsWith('toa ') ||
          q.startsWith('tòa ') ||
          q.startsWith('khu ')) {
        final targetLetter = q.replaceFirst(RegExp(r'^(toa|tòa|khu)\s*'), '');
        return roomLetter == targetLetter || roomBuilding.contains(q);
      }

      // TÌM THEO MÃ PHÒNG HOẶC TÊN SINH VIÊN
      final studentsNorm = room.studentNames.map(_normalize).join(' ');
      return roomCode.contains(q) ||
          roomBuilding.contains(q) ||
          studentsNorm.contains(q);
    }).toList();
  }

  void _showRoomDialog([AdminRoom? room]) {
    final isEdit = room != null;
    final codeCtrl = TextEditingController(text: room?.code ?? '');
    final buildingCtrl = TextEditingController(text: room?.building ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isEdit ? Icons.edit_note_rounded : Icons.add_home_work_rounded,
              color: const Color(0xFFD35400),
            ),
            const SizedBox(width: 8),
            Text(
              isEdit ? 'Cập nhật phòng' : 'Thêm phòng mới',
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
                controller: codeCtrl,
                decoration: InputDecoration(
                  labelText: 'Mã phòng *',
                  hintText: 'VD: A101, B2-205',
                  prefixIcon: const Icon(Icons.meeting_room_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Nhập mã phòng' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: buildingCtrl,
                decoration: InputDecoration(
                  labelText: 'Tòa nhà *',
                  hintText: 'VD: Tòa A, Tòa B',
                  prefixIcon: const Icon(Icons.apartment_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Nhập tòa nhà' : null,
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
                  await _repo.addRoom(
                    code: codeCtrl.text.trim(),
                    building: buildingCtrl.text.trim(),
                  );
                } else {
                  await _repo.updateRoom(
                    roomId: room.id,
                    code: codeCtrl.text.trim(),
                    building: buildingCtrl.text.trim(),
                  );
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
            label: Text(isEdit ? 'Lưu thay đổi' : 'Thêm mới'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredRooms;
    const primaryColor = Color(0xFFD35400);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Quản lý phòng KTX',
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
        onPressed: () => _showRoomDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Thêm phòng',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // KHU VỰC TÌM KIẾM & CHỌN TÒA
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo mã phòng, tòa nhà, sinh viên...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
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
                const SizedBox(height: 10),

                // THANH FILTER CHIPS CHỌN TÒA
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _availableBuildings.map((building) {
                      final isSelected = _selectedBuilding == building;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(building),
                          selected: isSelected,
                          selectedColor: const Color(0xFFFFE0B2),
                          backgroundColor: const Color(0xFFF1F3F5),
                          labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? primaryColor : Colors.black87,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? primaryColor
                                : Colors.transparent,
                            width: 1,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedBuilding = building);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // DANH SÁCH PHÒNG
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
                          Icons.search_off_rounded,
                          size: 56,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Không tìm thấy phòng nào phù hợp.',
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
                    itemBuilder: (context, i) {
                      final room = list[i];
                      final hasStudents = room.studentNames.isNotEmpty;
                      final buildingBadge = room.building
                          .replaceAll(
                            RegExp(r'^(Tòa|Khu)\s*', caseSensitive: false),
                            '',
                          )
                          .trim();

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: room.isActive
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
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Badge Tòa nhà bo tròn
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: room.isActive
                                    ? const Color(0xFFFFF3E0)
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  buildingBadge.isEmpty ? 'P' : buildingBadge,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: room.isActive
                                        ? primaryColor
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Thông tin chi tiết phòng
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        room.code,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2B2D42),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '(${room.building})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const Spacer(),
                                      // Badge Trạng thái
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: room.isActive
                                              ? const Color(0xFFE8F5E9)
                                              : const Color(0xFFFFEBEE),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          room.isActive
                                              ? 'Hoạt động'
                                              : 'Ngừng dùng',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: room.isActive
                                                ? const Color(0xFF2E7D32)
                                                : const Color(0xFFC62828),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Thông tin sinh viên
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        hasStudents
                                            ? Icons.person_rounded
                                            : Icons.person_off_outlined,
                                        size: 15,
                                        color: hasStudents
                                            ? Colors.blueGrey
                                            : Colors.grey.shade400,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          hasStudents
                                              ? room.studentNames.join(', ')
                                              : 'Phòng trống (chưa có SV)',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: hasStudents
                                                ? Colors.black87
                                                : Colors.grey.shade500,
                                            fontStyle: hasStudents
                                                ? FontStyle.normal
                                                : FontStyle.italic,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Menu thao tác 3 chấm
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: Colors.grey,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  _showRoomDialog(room);
                                } else if (action == 'deactivate') {
                                  try {
                                    await _repo.deactivateRoom(room);
                                    _load();
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            e.toString().replaceAll(
                                              'Exception: ',
                                              '',
                                            ),
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Chỉnh sửa'),
                                    ],
                                  ),
                                ),
                                if (room.isActive)
                                  PopupMenuItem(
                                    value: 'deactivate',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.block_rounded,
                                          size: 18,
                                          color: Colors.red.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Ngừng sử dụng',
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
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
