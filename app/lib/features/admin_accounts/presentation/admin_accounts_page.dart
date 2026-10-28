import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../data/admin_accounts_repository.dart';
import '../models/managed_account.dart';

/// DF-028/029/030: danh sách, tìm kiếm và lọc tài khoản dành riêng cho Admin.
class AdminAccountsPage extends StatefulWidget {
  const AdminAccountsPage({
    super.key,
    required this.repository,
    required this.isAdmin,
    this.onBack,
  });

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
  void initState() {
    super.initState();
    if (widget.isAdmin) _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (!widget.isAdmin) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _offset = 0;
    });
    try {
      final items = await widget.repository.list(
        query: _search.text,
        role: _role,
        status: _status,
        offset: append ? _offset : 0,
        limit: _pageSize + 1,
      );
      if (!mounted) return;
      final hasMore = items.length > _pageSize;
      setState(() {
        _accounts = append
            ? [..._accounts, ...items.take(_pageSize)]
            : items.take(_pageSize).toList();
        _hasMore = hasMore;
        _offset = append ? _offset + _pageSize : _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is AdminAccountsFailure
              ? error.message
              : 'Không thể tải danh sách tài khoản. Vui lòng thử lại.';
        });
      }
    }
  }

  void _searchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load());
  }

  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _role = null;
      _status = null;
    });
    _load();
  }

  bool get _hasFilters =>
      _search.text.trim().isNotEmpty || _role != null || _status != null;

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền truy cập màn hình này.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý tài khoản'),
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 600 ? 16 : 28,
              vertical: 24,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _pageHeading(context),
                      const SizedBox(height: 22),
                      _filterCard(context),
                      const SizedBox(height: 20),
                      _accountsCard(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageHeading(BuildContext context) => Row(
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.manage_accounts_outlined,
          color: AppColors.primaryDark,
          size: 28,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tài khoản',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              'Danh sách Sinh viên và Kỹ thuật viên',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _filterCard(BuildContext context) => _SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tìm kiếm và lọc',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: _searchChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Nhập họ tên hoặc mã định danh',
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa từ khóa',
                    onPressed: () {
                      _debounce?.cancel();
                      _search.clear();
                      setState(() {});
                      _load();
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _roleDropdown(),
            _statusDropdown(),
            TextButton.icon(
              onPressed: _hasFilters ? _clearFilters : null,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 19),
              label: const Text('Xóa bộ lọc'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _roleDropdown() => _FilterDropdown<AppRole?>(
    icon: Icons.badge_outlined,
    value: _role,
    hint: 'Tất cả vai trò',
    items: [
      const DropdownMenuItem(value: null, child: Text('Tất cả vai trò')),
      ...[
        AppRole.student,
        AppRole.technician,
      ].map((role) => DropdownMenuItem(value: role, child: Text(role.label))),
    ],
    onChanged: (value) {
      setState(() => _role = value);
      _load();
    },
  );

  Widget _statusDropdown() => _FilterDropdown<AccountStatus?>(
    icon: Icons.toggle_on_outlined,
    value: _status,
    hint: 'Tất cả trạng thái',
    items: [
      const DropdownMenuItem(value: null, child: Text('Tất cả trạng thái')),
      ...AccountStatus.values.map(
        (status) => DropdownMenuItem(value: status, child: Text(status.label)),
      ),
    ],
    onChanged: (value) {
      setState(() => _status = value);
      _load();
    },
  );

  Widget _accountsCard(BuildContext context) => _SurfaceCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Danh sách tài khoản',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Thông tin tài khoản theo bộ lọc hiện tại',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              if (_accounts.isNotEmpty)
                _CountPill(
                  label: '${_accounts.length}${_hasMore ? '+' : ''} tài khoản',
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_loading && _accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 52),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null && _accounts.isEmpty)
          _messageState(
            context,
            icon: Icons.cloud_off_outlined,
            message: _error!,
            action: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          )
        else if (_accounts.isEmpty)
          _messageState(
            context,
            icon: _hasFilters ? Icons.search_off : Icons.people_outline,
            message: _hasFilters
                ? 'Không tìm thấy tài khoản phù hợp'
                : 'Chưa có tài khoản Sinh viên hoặc Kỹ thuật viên nào.',
          )
        else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              horizontalMargin: 20,
              columnSpacing: 34,
              headingRowHeight: 54,
              dataRowMinHeight: 68,
              dataRowMaxHeight: 76,
              headingRowColor: WidgetStatePropertyAll(
                AppColors.pageBg.withValues(alpha: 0.75),
              ),
              columns: const [
                DataColumn(label: Text('Họ tên')),
                DataColumn(label: Text('Mã định danh')),
                DataColumn(label: Text('Vai trò')),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: _accounts.map(_accountRow).toList(),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _load(append: true),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Tải thêm tài khoản'),
                ),
              ),
            ),
        ],
      ],
    ),
  );

  DataRow _accountRow(ManagedAccount account) => DataRow(
    cells: [
      DataCell(
        SizedBox(
          width: 230,
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  _initials(account.fullName),
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  account.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
      DataCell(
        Text(
          account.identityCode,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
      DataCell(_RolePill(role: account.role)),
      DataCell(_StatusPill(status: account.status)),
    ],
  );

  Widget _messageState(
    BuildContext context, {
    required IconData icon,
    required String message,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 38, 24, 42),
    child: Column(
      children: [
        Icon(icon, size: 42, color: Colors.black38),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Colors.black87),
        ),
        if (action != null) ...[const SizedBox(height: 8), action],
      ],
    ),
  );

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    String firstRune(String value) => String.fromCharCode(value.runes.first);
    if (parts.length == 1) return firstRune(parts.first).toUpperCase();
    return '${firstRune(parts.first)}${firstRune(parts.last)}'.toUpperCase();
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEDE5DE)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A3E2C20),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    padding: padding,
    child: child,
  );
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.pageBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE4D8CE)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text(hint, overflow: TextOverflow.ellipsis),
              isExpanded: true,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.pageBg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final color = role == AppRole.student
        ? const Color(0xFF2563EB)
        : const Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final AccountStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (status) {
      AccountStatus.active => (
        const Color(0xFF15803D),
        const Color(0xFFEAF7EE),
      ),
      AccountStatus.locked => (
        const Color(0xFFB45309),
        const Color(0xFFFFF4E5),
      ),
      AccountStatus.revoked => (
        const Color(0xFF64748B),
        const Color(0xFFF1F4F7),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
