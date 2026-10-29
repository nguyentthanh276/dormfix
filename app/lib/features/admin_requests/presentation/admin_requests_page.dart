import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/admin_request_repository.dart';
import '../models/admin_request.dart';
import 'admin_request_detail_page.dart';

/// DF-043/044: Admin đọc mọi yêu cầu và lọc theo nhiều điều kiện AND.
class AdminRequestsPage extends StatefulWidget {
  const AdminRequestsPage({
    super.key,
    required this.repository,
    required this.isAdmin,
    required this.onSignOut,
    this.onBack,
  });

  final AdminRequestRepository repository;
  final bool isAdmin;
  final VoidCallback onSignOut;
  final VoidCallback? onBack;

  @override
  State<AdminRequestsPage> createState() => _AdminRequestsPageState();
}

class _AdminRequestsPageState extends State<AdminRequestsPage> {
  static const _pageSize = 20;
  AdminRequestFilterOptions? _options;
  List<AdminRequestSummary> _requests = const [];
  RepairStatus? _status;
  String? _roomId;
  String? _categoryId;
  String? _technicianId;
  AdminRequestDateField? _dateField;
  DateTimeRange? _dateRange;
  bool _loading = true;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isAdmin) _load();
  }

  AdminRequestFilters get _filters {
    if (_dateField != null && _dateRange != null) {
      return AdminRequestFilters.forSaigonDateRange(
        status: _status,
        roomId: _roomId,
        categoryId: _categoryId,
        technicianId: _technicianId,
        dateField: _dateField!,
        fromDate: _dateRange!.start,
        toDate: _dateRange!.end,
      );
    }
    return AdminRequestFilters(
      status: _status,
      roomId: _roomId,
      categoryId: _categoryId,
      technicianId: _technicianId,
    );
  }

  Future<void> _load({bool append = false}) async {
    if (!widget.isAdmin) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _offset = 0;
    });
    try {
      final options = _options ?? await widget.repository.fetchFilterOptions();
      final page = await widget.repository.fetchRequests(
        filters: _filters,
        offset: append ? _offset : 0,
        limit: _pageSize + 1,
      );
      if (!mounted) return;
      setState(() {
        _options = options;
        _hasMore = page.length > _pageSize;
        _requests = append
            ? [..._requests, ...page.take(_pageSize)]
            : page.take(_pageSize).toList();
        _offset = append ? _offset + _pageSize : _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is AdminRequestFailure
            ? error.message
            : 'Không thể tải yêu cầu sửa chữa. Vui lòng thử lại.';
      });
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2019),
      lastDate: now,
      initialDateRange: _dateRange,
      helpText: 'Chọn khoảng ngày',
      saveText: 'ÁP DỤNG',
      cancelText: 'HỦY',
      builder: (context, child) =>
          Theme(data: Theme.of(context), child: child!),
    );
    if (picked == null || !mounted) return;
    if (picked.start.isAfter(picked.end)) {
      setState(() => _error = 'Ngày bắt đầu không được sau ngày kết thúc.');
      return;
    }
    setState(() => _dateRange = picked);
    await _load();
  }

  void _clearFilters() {
    setState(() {
      _status = null;
      _roomId = null;
      _categoryId = null;
      _technicianId = null;
      _dateField = null;
      _dateRange = null;
    });
    _load();
  }

  bool get _hasFilters =>
      _status != null ||
      _roomId != null ||
      _categoryId != null ||
      _technicianId != null ||
      _dateRange != null;

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền truy cập màn hình này.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yêu cầu sửa chữa'),
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 650 ? 16 : 28,
              vertical: 22,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heading(context),
                      const SizedBox(height: 18),
                      _filterPanel(context),
                      const SizedBox(height: 18),
                      _requestList(context),
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

  Widget _heading(BuildContext context) => Row(
    children: [
      Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(
          Icons.home_repair_service_outlined,
          color: AppColors.primaryDark,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quản lý yêu cầu',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              'Xem thông tin, người xử lý và lịch sử của mọi yêu cầu.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _filterPanel(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bộ lọc',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _select<RepairStatus?>(
              label: 'Tất cả trạng thái',
              value: _status,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tất cả trạng thái'),
                ),
                ...RepairStatus.values.map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(status.label),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _status = value);
                _load();
              },
            ),
            _select<String?>(
              label: 'Tất cả phòng',
              value: _roomId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tất cả phòng'),
                ),
                ...?_options?.rooms.map(
                  (option) => DropdownMenuItem(
                    value: option.id,
                    child: Text(option.label),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _roomId = value);
                _load();
              },
            ),
            _select<String?>(
              label: 'Tất cả loại sự cố',
              value: _categoryId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tất cả loại sự cố'),
                ),
                ...?_options?.categories.map(
                  (option) => DropdownMenuItem(
                    value: option.id,
                    child: Text(option.label),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _categoryId = value);
                _load();
              },
            ),
            _select<String?>(
              label: 'Tất cả Kỹ thuật viên',
              value: _technicianId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tất cả Kỹ thuật viên'),
                ),
                ...?_options?.technicians.map(
                  (option) => DropdownMenuItem(
                    value: option.id,
                    child: Text(option.label),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _technicianId = value);
                _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 255,
              child: DropdownButtonFormField<AdminRequestDateField?>(
                initialValue: _dateField,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Lọc thời gian theo',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Không lọc theo ngày'),
                  ),
                  ...AdminRequestDateField.values.map(
                    (field) => DropdownMenuItem(
                      value: field,
                      child: Text(field.label, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _dateField = value;
                    if (value == null) _dateRange = null;
                  });
                  if (value == null || _dateRange != null) _load();
                },
              ),
            ),
            if (_dateField != null)
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  _dateRange == null
                      ? 'Chọn khoảng ngày'
                      : '${_formatDate(_dateRange!.start)} – ${_formatDate(_dateRange!.end)}',
                ),
              ),
            TextButton.icon(
              onPressed: _hasFilters ? _clearFilters : null,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Xóa bộ lọc'),
            ),
          ],
        ),
        if (_dateField != null && _dateRange == null) ...[
          const SizedBox(height: 8),
          Text(
            'Chọn ngày bắt đầu và ngày kết thúc để áp dụng bộ lọc thời gian.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.black54),
          ),
        ],
      ],
    ),
  );

  Widget _select<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => SizedBox(
    width: 225,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged,
    ),
  );

  Widget _requestList(BuildContext context) => _Panel(
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
                      'Danh sách yêu cầu',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Chọn một yêu cầu để xem chi tiết và lịch sử.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              if (_requests.isNotEmpty)
                _ResultPill(
                  label: '${_requests.length}${_hasMore ? '+' : ''} yêu cầu',
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_loading && _requests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 50),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null && _requests.isEmpty)
          _stateMessage(
            context,
            icon: Icons.cloud_off_outlined,
            message: _error!,
            action: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          )
        else if (_requests.isEmpty)
          _stateMessage(
            context,
            icon: Icons.search_off_outlined,
            message: _hasFilters
                ? 'Không tìm thấy yêu cầu phù hợp.'
                : 'Chưa có yêu cầu sửa chữa nào.',
          )
        else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final request in _requests) _requestTile(context, request),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _load(append: true),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Tải thêm yêu cầu'),
                ),
              ),
            ),
        ],
      ],
    ),
  );

  Widget _requestTile(BuildContext context, AdminRequestSummary request) =>
      InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => AdminRequestDetailPage(
              repository: widget.repository,
              requestId: request.id,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    request.requestCode,
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  StatusChip(request.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                request.title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _meta(Icons.meeting_room_outlined, request.roomCode),
                  _meta(Icons.category_outlined, request.categoryName),
                  _meta(Icons.person_outline, request.studentName),
                  _meta(
                    Icons.engineering_outlined,
                    request.technicianName ?? 'Chưa phân công',
                  ),
                  _meta(
                    Icons.schedule,
                    'Tạo ${_formatDateTime(request.createdAt)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: Colors.black54),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(color: Colors.black87, fontSize: 13)),
    ],
  );

  Widget _stateMessage(
    BuildContext context, {
    required IconData icon,
    required String message,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 36, 24, 40),
    child: Column(
      children: [
        Icon(icon, size: 42, color: Colors.black38),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 8), action],
      ],
    ),
  );

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _formatDateTime(DateTime date) =>
      '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
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
    child: child,
  );
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.pageBg,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
