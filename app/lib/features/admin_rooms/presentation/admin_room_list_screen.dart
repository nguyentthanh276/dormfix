import 'package:flutter/material.dart';

import '../data/admin_room_repository.dart';
import '../models/admin_room.dart';

class AdminRoomListScreen extends StatefulWidget {
  const AdminRoomListScreen({super.key});

  @override
  State<AdminRoomListScreen> createState() => _AdminRoomListScreenState();
}

class _AdminRoomListScreenState extends State<AdminRoomListScreen> {
  final AdminRoomRepository _repo = AdminRoomRepository();
  final TextEditingController _searchCtrl = TextEditingController();

  List<AdminRoom> _allRooms = [];
  List<AdminRoom> _filteredRooms = [];
  bool _isLoading = true;
  String _selectedBuilding = 'Tất cả';

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRooms() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repo.fetchRooms();
      if (!mounted) return;
      setState(() {
        _allRooms = data;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showToast('Lỗi tải dữ liệu: $e', isError: true);
    }
  }

  // Logic lọc chuẩn xác: Chỉ tìm theo mã phòng và lọc theo tòa được chọn
  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filteredRooms = _allRooms.where((room) {
        // 1. Khớp mã phòng (Bỏ quét chữ 'Tòa' hoặc tên SV để tránh bị trùng chữ 'A')
        final matchCode =
            query.isEmpty || room.code.toLowerCase().contains(query);

        // 2. Khớp tòa nhà được chọn ở Chip
        final matchBuilding =
            _selectedBuilding == 'Tất cả' ||
            room.building.toLowerCase() == _selectedBuilding.toLowerCase();

        return matchCode && matchBuilding;
      }).toList();
    });
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? const Color(0xFFDC2626)
            : const Color(0xFF16A34A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<String> get _buildingList {
    final buildings = _allRooms.map((r) => r.building).toSet().toList()..sort();
    return ['Tất cả', ...buildings];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFEA580C),
        foregroundColor: Colors.white,
        title: const Text(
          'Quản lý phòng KTX',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchRooms,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFEA580C),
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Thêm phòng',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        onPressed: _openAddRoomDialog,
      ),
      body: Column(
        children: [
          // Khu vực tìm kiếm & Bộ lọc tòa
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            color: Colors.white,
            child: Column(
              children: [
                // Thanh tìm kiếm
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm theo mã phòng...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade400,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Lọc theo Tòa nhà dạng Chips
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _buildingList.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final b = _buildingList[idx];
                      final isSelected = b == _selectedBuilding;
                      return ChoiceChip(
                        label: Text(b),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            _selectedBuilding = b;
                            _applyFilters();
                          });
                        },
                        selectedColor: const Color(0xFFFFEDD5),
                        backgroundColor: const Color(0xFFF8FAFC),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFFEA580C)
                              : const Color(0xFF64748B),
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFFF97316)
                              : const Color(0xFFE2E8F0),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Danh sách phòng
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFEA580C)),
                  )
                : _filteredRooms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.meeting_room_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Không tìm thấy phòng nào',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
                    itemCount: _filteredRooms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _buildRoomCard(_filteredRooms[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(AdminRoom room) {
    final hasStudents = room.studentNames.isNotEmpty;
    final statusColor = room.isActive
        ? const Color(0xFF16A34A)
        : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: room.isActive
              ? const Color(0xFFE2E8F0)
              : const Color(0xFFCBD5E1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge Tòa nhà
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: room.isActive
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: room.isActive
                        ? const Color(0xFFBFDBFE)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.apartment_rounded,
                      size: 20,
                      color: room.isActive
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      room.building,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: room.isActive
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Thông tin phòng
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Phòng ${room.code}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 3,
                                backgroundColor: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                room.isActive
                                    ? 'Đang hoạt động'
                                    : 'Ngừng sử dụng',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          hasStudents
                              ? Icons.people_alt_rounded
                              : Icons.person_off_rounded,
                          size: 15,
                          color: hasStudents
                              ? const Color(0xFF0284C7)
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hasStudents
                                ? 'Sinh viên: ${room.studentNames.join(', ')}'
                                : 'Phòng trống (chưa có sinh viên)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: hasStudents
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: hasStudents
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Menu thao tác
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFF64748B),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (val) {
                  if (val == 'edit') {
                    _openEditRoomDialog(room);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                        SizedBox(width: 10),
                        Text('Sửa thông tin'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddRoomDialog() {
    final codeCtrl = TextEditingController();
    final bldCtrl = TextEditingController(text: 'Tòa A');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Thêm phòng mới',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(
                labelText: 'Mã phòng *',
                hintText: 'VD: A1-101',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: bldCtrl,
              decoration: InputDecoration(
                labelText: 'Tòa nhà *',
                hintText: 'VD: Tòa A',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
            ),
            onPressed: () async {
              final code = codeCtrl.text.trim();
              final bld = bldCtrl.text.trim();
              if (code.isEmpty || bld.isEmpty) {
                _showToast('Vui lòng điền đủ thông tin', isError: true);
                return;
              }
              Navigator.pop(ctx);
              try {
                await _repo.addRoom(code: code, building: bld);
                _showToast('Thêm phòng $code thành công!');
                _fetchRooms();
              } catch (e) {
                _showToast('$e', isError: true);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _openEditRoomDialog(AdminRoom room) {
    final codeCtrl = TextEditingController(text: room.code);
    final bldCtrl = TextEditingController(text: room.building);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cập nhật phòng',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(
                labelText: 'Mã phòng *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: bldCtrl,
              decoration: InputDecoration(
                labelText: 'Tòa nhà *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
            ),
            onPressed: () async {
              final code = codeCtrl.text.trim();
              final bld = bldCtrl.text.trim();
              if (code.isEmpty || bld.isEmpty) {
                _showToast('Vui lòng điền đủ thông tin', isError: true);
                return;
              }
              Navigator.pop(ctx);
              try {
                await _repo.updateRoom(
                  roomId: room.id,
                  code: code,
                  building: bld,
                );
                _showToast('Cập nhật phòng thành công!');
                _fetchRooms();
              } catch (e) {
                _showToast('$e', isError: true);
              }
            },
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
  }
}
