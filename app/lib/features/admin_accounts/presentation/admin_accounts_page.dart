import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../data/admin_accounts_repository.dart';
import '../models/managed_account.dart';

/// DF-028/029/030: danh sách, tìm kiếm và lọc tài khoản dành riêng cho Admin.
class AdminAccountsPage extends StatefulWidget {
  const AdminAccountsPage({super.key, required this.repository, required this.isAdmin, this.onBack});
  final AdminAccountsRepository repository;
  final bool isAdmin;
  final VoidCallback? onBack;

  @override
  State<AdminAccountsPage> createState() => _AdminAccountsPageState();
}

class _AdminAccountsPageState extends State<AdminAccountsPage> {
  static const _pageSize = 20;
  final _search = TextEditingController();
  Timer? _debounce;
  List<ManagedAccount> _accounts = const [];
  AppRole? _role;
  AccountStatus? _status;
  int _offset = 0;
  bool _loading = true;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() { super.initState(); if (widget.isAdmin) _load(); }
  @override
  void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }

  Future<void> _load({bool append = false}) async {
    if (!widget.isAdmin) return;
    setState(() { _loading = true; _error = null; if (!append) _offset = 0; });
    try {
      final items = await widget.repository.list(query: _search.text, role: _role, status: _status, offset: append ? _offset : 0, limit: _pageSize + 1);
      if (!mounted) return;
      final hasMore = items.length > _pageSize;
      setState(() { _accounts = append ? [..._accounts, ...items.take(_pageSize)] : items.take(_pageSize).toList(); _hasMore = hasMore; _offset = append ? _offset + _pageSize : _pageSize; _loading = false; });
    } catch (_) { if (mounted) setState(() { _loading = false; _error = 'Không thể tải danh sách tài khoản. Vui lòng thử lại.'; }); }
  }

  void _searchChanged(String _) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), () => _load()); }
  void _clearFilters() { _search.clear(); setState(() { _role = null; _status = null; }); _load(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) return const Scaffold(body: Center(child: Text('Bạn không có quyền truy cập màn hình này.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý tài khoản'), leading: widget.onBack == null ? null : BackButton(onPressed: widget.onBack)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          TextField(controller: _search, onChanged: _searchChanged, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm theo họ tên hoặc mã định danh', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            DropdownButton<AppRole?>(value: _role, hint: const Text('Vai trò: Tất cả'), items: [const DropdownMenuItem(value: null, child: Text('Tất cả vai trò')), ...[AppRole.student, AppRole.technician].map((r) => DropdownMenuItem(value: r, child: Text(r.label)))], onChanged: (value) { setState(() => _role = value); _load(); }),
            DropdownButton<AccountStatus?>(value: _status, hint: const Text('Trạng thái: Tất cả'), items: [const DropdownMenuItem(value: null, child: Text('Tất cả trạng thái')), ...AccountStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label)))], onChanged: (value) { setState(() => _status = value); _load(); }),
            TextButton.icon(onPressed: _clearFilters, icon: const Icon(Icons.filter_alt_off), label: const Text('Xóa bộ lọc')),
          ]),
        ])),
        if (_loading && _accounts.isEmpty) const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null && _accounts.isEmpty) Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('Thử lại'))])))
        else if (_accounts.isEmpty) Expanded(child: Center(child: Text(
          _search.text.trim().isEmpty && _role == null && _status == null
              ? 'Chưa có tài khoản Sinh viên hoặc Kỹ thuật viên nào.'
              : 'Không tìm thấy tài khoản phù hợp',
        )))
        else Expanded(child: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Họ tên')), DataColumn(label: Text('Mã định danh')), DataColumn(label: Text('Vai trò')), DataColumn(label: Text('Trạng thái'))], rows: _accounts.map((a) => DataRow(cells: [DataCell(Text(a.fullName)), DataCell(Text(a.identityCode)), DataCell(Text(a.role.label)), DataCell(Text(a.status.label))])).toList())),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
          if (_hasMore) Center(child: TextButton(onPressed: _loading ? null : () => _load(append: true), child: const Text('Tải thêm'))),
        ]))),
      ]),
    );
  }
}
