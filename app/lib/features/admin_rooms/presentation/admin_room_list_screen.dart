import 'package:flutter/material.dart';

import '../../../core/data/admin_catalog_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/admin_catalog_dialog.dart';
import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/error_view.dart';

import '../data/admin_room_repository.dart';
import '../models/admin_room.dart';

class AdminRoomListScreen extends StatefulWidget {
  const AdminRoomListScreen({
    super.key,
    required this.repository,
    this.embedded = false,
  });

  final AdminRoomRepository repository;
  final bool embedded;

  @override
  State<AdminRoomListScreen> createState() => _AdminRoomListScreenState();
}

class _AdminRoomListScreenState extends State<AdminRoomListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<AdminRoom> _allRooms = [];
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;
  String _selectedBuilding = 'Tất cả';

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  @override
  void didUpdateWidget(covariant AdminRoomListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _allRooms = [];
      _fetchRooms();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRooms() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await widget.repository.fetchRooms();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _allRooms = data;
        if (!_buildingList.contains(_selectedBuilding)) {
          _selectedBuilding = 'Tất cả';
        }
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _allRooms = [];
        _loadError = error is AdminCatalogFailure
            ? error.message
            : 'Không thể tải danh sách phòng. Vui lòng thử lại.';
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<AdminRoom> get _filteredRooms {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _allRooms.where((room) {
      final matchCode = room.code.toLowerCase().contains(query);
      final matchBuilding =
          _selectedBuilding == 'Tất cả' ||
          room.building.toLowerCase() == _selectedBuilding.toLowerCase();
      return matchCode && matchBuilding;
    }).toList();
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF16A34A),
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
    final filteredRooms = _filteredRooms;
    final buildings = _buildingList;
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Expanded(child: Text("Danh sách phòng")),
              FilledButton.icon(
                onPressed: _isLoading || _loadError != null
                    ? null
                    : () => _openRoomEditor(),
                icon: const Icon(Icons.add),
                label: const Text("Thêm phòng"),
              ),
            ],
          ),
        ),
        // Khu vực tìm kiếm & Bộ lọc tòa
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          color: Colors.white,
          child: Column(
            children: [
              // Thanh tìm kiếm
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
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
                            setState(() {});
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
                  key: const PageStorageKey("admin-rooms-list"),
                  scrollDirection: Axis.horizontal,
                  itemCount: buildings.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final b = buildings[idx];
                    final isSelected = b == _selectedBuilding;
                    return ChoiceChip(
                      label: Text(b),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedBuilding = b;
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
                            ? AppColors.primaryDark
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
                  child: CircularProgressIndicator(
                    color: AppColors.primaryDark,
                  ),
                )
              : _loadError != null
              ? ErrorView(message: _loadError!, onRetry: _fetchRooms)
              : filteredRooms.isEmpty
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
              : RefreshIndicator(
                  onRefresh: _fetchRooms,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    itemCount: filteredRooms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _buildRoomCard(filteredRooms[i]),
                  ),
                ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: const DormFixAppBar(title: "Quản lý phòng", roleLabel: "Admin"),
      body: body,
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phòng ${room.code}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                              Flexible(
                                child: Text(
                                  room.isActive
                                      ? 'Đang hoạt động'
                                      : 'Ngừng sử dụng',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
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
                    _openRoomEditor(room);
                  } else if (val == 'deactivate') {
                    _confirmDeactivate(room);
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
                  if (room.isActive)
                    const PopupMenuItem(
                      value: 'deactivate',
                      child: Row(
                        children: [
                          Icon(
                            Icons.block_rounded,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Ngừng sử dụng',
                            style: TextStyle(color: Colors.red),
                          ),
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

  Future<void> _openRoomEditor([AdminRoom? room]) async {
    final repository = widget.repository;
    var code = room?.code ?? '';
    var building = room?.building ?? '';
    final result = await showDialog<AdminCatalogDialogResult>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => AdminCatalogDialog(
        title: room == null ? 'Thêm phòng mới' : 'Cập nhật phòng',
        submitLabel: room == null ? 'Lưu' : 'Cập nhật',
        fields: (enabled) => Column(
          children: [
            TextFormField(
              initialValue: room?.code,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Mã phòng *'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Vui lòng nhập mã phòng.'
                  : null,
              onSaved: (value) => code = value!.trim(),
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: room?.building,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Tòa nhà *'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Vui lòng nhập tòa nhà.'
                  : null,
              onSaved: (value) => building = value!.trim(),
            ),
          ],
        ),
        onSave: () => room == null
            ? repository.addRoom(code: code, building: building)
            : repository.updateRoom(
                roomId: room.id,
                code: code,
                building: building,
              ),
      ),
    );
    if (!mounted || widget.repository != repository || result == null) return;
    if (result == AdminCatalogDialogResult.saved) {
      _showToast(room == null ? 'Đã thêm phòng $code' : 'Đã cập nhật phòng');
    }
    await _fetchRooms();
  }

  Future<void> _confirmDeactivate(AdminRoom room) async {
    if (room.studentNames.isNotEmpty) {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Không thể ngừng sử dụng'),
          content: Text(
            'Phòng ${room.code} còn ${room.studentNames.length} sinh viên. '
            'Hãy chuyển sinh viên sang phòng khác trước.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      return;
    }

    final repository = widget.repository;
    final result = await showDialog<AdminCatalogDialogResult>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => AdminCatalogDialog(
        title: 'Ngừng sử dụng phòng?',
        submitLabel: 'Ngừng sử dụng',
        destructive: true,
        fields: (_) => Text('Phòng ${room.code} sẽ ngừng sử dụng.'),
        onSave: () => repository.deactivateRoom(room),
      ),
    );
    if (!mounted || widget.repository != repository || result == null) return;
    if (result == AdminCatalogDialogResult.saved) {
      _showToast('Đã ngừng sử dụng phòng ${room.code}');
    }
    await _fetchRooms();
  }
}
