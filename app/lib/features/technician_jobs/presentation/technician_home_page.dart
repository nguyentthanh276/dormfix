// Đóng góp của Nguyễn Tiến Thành (DF-020, DF-021, DF-022, DF-027).
// Phạm vi gồm danh sách, bộ lọc, mở chi tiết, lịch sử và thông báo.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../../core/models/repair_status.dart';
import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/role_navigation_bar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_page.dart';
import '../data/technician_jobs_repository.dart';
import '../data/technician_tracking_repository.dart';
import '../data/technician_workflow_repository.dart';
import '../models/technician_job.dart';
import 'technician_job_detail_page.dart';
import 'technician_job_widgets.dart';
import 'technician_tracking_views.dart';

enum _TechnicianSection { jobs, history, notifications, profile }

class TechnicianHomePage extends StatefulWidget {
  const TechnicianHomePage({
    super.key,
    required this.controller,
    this.repository,
    this.workflowRepository,
    this.trackingRepository,
    this.profileRepository,
  });

  final AuthController controller;
  final TechnicianJobsRepository? repository;
  final TechnicianWorkflowRepository? workflowRepository;
  final TechnicianTrackingRepository? trackingRepository;
  final ProfileRepository? profileRepository;

  @override
  State<TechnicianHomePage> createState() => _TechnicianHomePageState();
}

class _TechnicianHomePageState extends State<TechnicianHomePage>
    with WidgetsBindingObserver {
  static const _filterableStatuses = [
    RepairStatus.assigned,
    RepairStatus.inProgress,
    RepairStatus.awaitingConfirmation,
    RepairStatus.awaitingRework,
    RepairStatus.completed,
    RepairStatus.cancelled,
  ];

  List<TechnicianJob> _jobs = [];
  RepairStatus? _selectedStatus;
  _TechnicianSection _section = _TechnicianSection.jobs;
  String? _identity;
  String? _selectedJobId;
  String? _error;
  bool _loading = false;
  bool _refreshQueued = false;
  bool _allowed = false;
  int _generation = 0;
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final Set<_TechnicianSection> _visited = {_TechnicianSection.jobs};
  int _historyRevision = 0;
  int _notificationsRevision = 0;
  final ScrollController _jobsScrollController = ScrollController();
  GlobalKey<TechnicianJobDetailPageState> _detailKey = GlobalKey();
  bool _checkingLeave = false;

  bool get _hasAccess {
    final profile = widget.controller.profile;
    return widget.controller.state == AuthViewState.authenticated &&
        profile != null &&
        profile.status == 'active' &&
        profile.role == AppRole.technician &&
        !profile.mustChangePassword &&
        profile.canAccess;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_authChanged);
    _allowed = _hasAccess;
    _identity = _allowed ? widget.controller.profile!.id : null;
    unawaited(_loadJobs());
  }

  @override
  void didUpdateWidget(covariant TechnicianHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_authChanged);
      widget.controller.addListener(_authChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.repository != widget.repository ||
        oldWidget.workflowRepository != widget.workflowRepository ||
        oldWidget.trackingRepository != widget.trackingRepository) {
      _reset();
      _allowed = _hasAccess;
      _identity = _allowed ? widget.controller.profile!.id : null;
      unawaited(_loadJobs());
    }
  }

  void _reset() {
    _generation++;
    _jobs = [];
    _selectedStatus = null;
    _section = _TechnicianSection.jobs;
    _selectedJobId = null;
    _error = null;
    _loading = false;
    _refreshQueued = false;
    _visited
      ..clear()
      ..add(_TechnicianSection.jobs);
    _historyRevision = 0;
    _notificationsRevision = 0;
    // Nested password routes belong to this exact authenticated identity.
    _navigatorKey = GlobalKey<NavigatorState>();
    _detailKey = GlobalKey<TechnicianJobDetailPageState>();
    _checkingLeave = false;
    if (_jobsScrollController.hasClients) _jobsScrollController.jumpTo(0);
  }

  void _authChanged() {
    if (!mounted) return;
    final allowed = _hasAccess;
    final identity = allowed ? widget.controller.profile!.id : null;
    final changed = allowed != _allowed || identity != _identity;
    setState(() {
      if (changed) _reset();
      _allowed = allowed;
      _identity = identity;
    });
    if (changed && allowed) unawaited(_loadJobs());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _selectedJobId == null &&
        _section == _TechnicianSection.jobs) {
      unawaited(_loadJobs());
    }
  }

  bool _isCurrent(int generation, String identity) =>
      mounted &&
      generation == _generation &&
      _hasAccess &&
      widget.controller.profile?.id == identity;

  // DF-020: Tải danh sách theo phiên hiện tại và gộp các lượt tải lại đang chờ.
  Future<void> _loadJobs() async {
    final repository = widget.repository;
    if (!_hasAccess || repository == null) return;
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    final identity = widget.controller.profile!.id;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await repository.fetchJobs();
      if (!_isCurrent(generation, identity)) return;
      // The server owns assignment ordering; preserve its response.
      setState(() => _jobs = List.unmodifiable(jobs));
    } on TechnicianJobsFailure catch (failure) {
      if (!_isCurrent(generation, identity)) return;
      setState(() {
        _jobs = [];
        if (failure.accessDenied) _selectedJobId = null;
        _error = failure.accessDenied
            ? 'Bạn không còn quyền xem danh sách công việc. Vui lòng thử lại hoặc đăng nhập lại.'
            : failure.message;
      });
    } catch (_) {
      if (!_isCurrent(generation, identity)) return;
      setState(() {
        _jobs = [];
        _error = 'Không tải được công việc. Vui lòng thử lại.';
      });
    } finally {
      if (_isCurrent(generation, identity)) {
        setState(() => _loading = false);
        if (_refreshQueued) {
          _refreshQueued = false;
          unawaited(_loadJobs());
        }
      }
    }
  }

  Future<void> _backToList() async {
    if (_checkingLeave) return;
    final identity = _identity;
    final requestId = _selectedJobId;
    _checkingLeave = true;
    final canLeave =
        await (_detailKey.currentState?.confirmLeave() ?? Future.value(true));
    if (!mounted || _identity != identity || _selectedJobId != requestId) {
      return;
    }
    _checkingLeave = false;
    if (!canLeave) return;
    setState(() {
      _selectedJobId = null;
      if (_section == _TechnicianSection.history) _historyRevision++;
      if (_section == _TechnicianSection.notifications) {
        _notificationsRevision++;
      }
    });
    unawaited(_loadJobs());
  }

  // DF-027: Đổi tab và yêu cầu tải lại lịch sử hoặc thông báo khi được chọn.
  void _selectSection(int index) {
    final section = _TechnicianSection.values[index];
    setState(() {
      _section = section;
      _visited.add(section);
      if (section == _TechnicianSection.history) _historyRevision++;
      if (section == _TechnicianSection.notifications) _notificationsRevision++;
    });
    if (section == _TechnicianSection.jobs) unawaited(_loadJobs());
  }

  // DF-022: Mở chi tiết bằng ID từ thẻ công việc, lịch sử hoặc thông báo.
  void _openTrackedJob(String requestId) {
    if (!_hasAccess || widget.repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chi tiết công việc chưa sẵn sàng.')),
      );
      return;
    }
    setState(() {
      _detailKey = GlobalKey<TechnicianJobDetailPageState>();
      _selectedJobId = requestId;
    });
  }

  void _detailAccessDenied() {
    if (!mounted) return;
    // Do not retain the old card when an assignment is transferred away.
    setState(() {
      _generation++;
      _loading = false;
      _jobs = [];
    });
  }

  void _jobWriteFinished(String identity) {
    // A disposed detail may finish later, including after logout or switching
    // accounts. Only refresh the Home belonging to the original technician.
    if (!mounted ||
        !_hasAccess ||
        _identity != identity ||
        widget.controller.profile?.id != identity) {
      return;
    }
    unawaited(_loadJobs());
  }

  @override
  void dispose() {
    _generation++;
    _jobs = [];
    widget.controller.removeListener(_authChanged);
    WidgetsBinding.instance.removeObserver(this);
    _jobsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('DormFix')),
        body: TechnicianJobsMessage(
          icon: Icons.lock_outline,
          message: 'Không thể xác minh quyền truy cập. Vui lòng đăng nhập lại.',
          actionLabel: 'Đăng xuất',
          onAction: widget.controller.isLoading
              ? null
              : () => unawaited(widget.controller.signOut()),
        ),
      );
    }
    final identity = widget.controller.profile!.id;
    // Every pushed personal form remains inside this authenticated Home.
    // Removing Home on logout also removes the nested routes and private data.
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: _navigatorKey,
        pages: [
          MaterialPage<void>(
            key: ValueKey('technician-shell-$identity'),
            child: _buildShell(identity),
          ),
        ],
        onDidRemovePage: (_) {},
      ),
    );
  }

  Widget _buildShell(String identity) {
    final selectedId = _selectedJobId;
    final profile = widget.controller.profile!;
    final atRoot = selectedId == null;
    return PopScope(
      canPop: atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToList();
      },
      child: Scaffold(
        appBar: DormFixAppBar(
          title: selectedId != null
              ? 'Chi tiết công việc'
              : switch (_section) {
                  _TechnicianSection.jobs => 'Công việc được giao',
                  _TechnicianSection.history => 'Lịch sử công việc',
                  _TechnicianSection.notifications => 'Thông báo',
                  _TechnicianSection.profile => 'Tài khoản cá nhân',
                },
          roleLabel: 'Kỹ thuật viên',
          fullName: profile.fullName,
          automaticallyImplyLeading: false,
          leading: atRoot ? null : BackButton(onPressed: _backToList),
          onAccountTap: atRoot
              ? () => _selectSection(_TechnicianSection.profile.index)
              : null,
        ),
        bottomNavigationBar: atRoot
            ? RoleNavigationBar(
                selectedIndex: _section.index,
                onDestinationSelected: _selectSection,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_repair_service_outlined),
                    selectedIcon: Icon(Icons.home_repair_service),
                    label: 'Công việc',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(Icons.history),
                    label: 'Lịch sử',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.notifications_outlined),
                    selectedIcon: Icon(Icons.notifications),
                    label: 'Thông báo',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Cá nhân',
                  ),
                ],
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              if (widget.controller.error case final error?)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Offstage(
                      offstage: !atRoot,
                      child: TickerMode(
                        enabled: atRoot,
                        child: IndexedStack(
                          index: _section.index,
                          children: [
                            _buildList(),
                            // DF-027: Chỉ tạo màn theo dõi sau khi mở tab.
                            if (_visited.contains(_TechnicianSection.history))
                              TechnicianWorkHistoryView(
                                key: ValueKey('$identity:history'),
                                repository: widget.trackingRepository,
                                refreshRevision: _historyRevision,
                                onOpenDetail: _openTrackedJob,
                              )
                            else
                              const SizedBox.shrink(),
                            if (_visited.contains(
                              _TechnicianSection.notifications,
                            ))
                              TechnicianNotificationsView(
                                key: ValueKey('$identity:notifications'),
                                repository: widget.trackingRepository,
                                refreshRevision: _notificationsRevision,
                                onOpenDetail: _openTrackedJob,
                              )
                            else
                              const SizedBox.shrink(),
                            if (_visited.contains(_TechnicianSection.profile))
                              ProfilePage(
                                key: ValueKey('$identity:profile'),
                                embedded: true,
                                active:
                                    atRoot &&
                                    _section == _TechnicianSection.profile,
                                controller: widget.controller,
                                profileRepository: widget.profileRepository,
                                onSignOut: () =>
                                    unawaited(widget.controller.signOut()),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                    // DF-022: Truyền ID đã chọn vào màn chi tiết.
                    if (selectedId != null && widget.repository != null)
                      TechnicianJobDetailPage(
                        key: _detailKey,
                        requestId: selectedId,
                        repository: widget.repository!,
                        onAccessDenied: _detailAccessDenied,
                        workflowRepository: widget.workflowRepository,
                        onJobChanged: () => _jobWriteFinished(identity),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // DF-020: Hiển thị danh sách, trạng thái tải, rỗng và lỗi có nút thử lại.
  Widget _buildList() {
    if (widget.repository == null) {
      return const TechnicianJobsMessage(
        icon: Icons.cloud_off_outlined,
        message: 'Danh sách công việc chưa sẵn sàng. Vui lòng liên hệ quản trị viên.',
        secondary: 'Vai trò: Kỹ thuật viên',
      );
    }
    if (_loading && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: _error != null || _jobs.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: TechnicianJobsMessage(
                      icon: _error == null
                          ? Icons.assignment_outlined
                          : Icons.cloud_off_outlined,
                      message:
                          _error ?? 'Bạn chưa được phân công công việc nào.',
                      actionLabel: 'Thử lại',
                      onAction: () => unawaited(_loadJobs()),
                    ),
                  ),
                ],
              ),
            )
          : _buildFilteredJobs(),
    );
  }

  // DF-021: Lọc dữ liệu đã tải theo trạng thái đang chọn trên máy.
  Widget _buildFilteredJobs() {
    final visibleJobs = _selectedStatus == null
        ? _jobs
        : _jobs.where((job) => job.status == _selectedStatus).toList();

    return Column(
      children: [
        _buildStatusFilters(),
        Expanded(
          child: visibleJobs.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 240,
                      child: TechnicianJobsMessage(
                        icon: Icons.filter_list_off,
                        message:
                            'Không có công việc ở trạng thái ${_selectedStatus!.label}.',
                        actionLabel: 'Xóa bộ lọc',
                        onAction: () => setState(() => _selectedStatus = null),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  key: const Key('technician-jobs-list'),
                  controller: _jobsScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visibleJobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final job = visibleJobs[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        // DF-022: Dùng ID của thẻ vừa bấm để mở chi tiết.
                        onTap: () => _openTrackedJob(job.id),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                job.requestCode,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                job.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              TechnicianStatusBadge(status: job.status),
                              const SizedBox(height: 8),
                              Text('Phòng ${job.roomCode} · ${job.building}'),
                              Text('Loại sự cố: ${job.categoryName}'),
                              Text('Tạo lúc: ${technicianDate(job.createdAt)}'),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // DF-021: Cập nhật trạng thái lọc khi chọn một nhãn.
  Widget _buildStatusFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Row(
      children: [
        ChoiceChip(
          label: const Text('Tất cả'),
          selected: _selectedStatus == null,
          onSelected: (_) => setState(() => _selectedStatus = null),
        ),
        for (final status in _filterableStatuses) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text('${status.label} (${_statusCount(status)})'),
            selected: _selectedStatus == status,
            onSelected: (_) => setState(() => _selectedStatus = status),
          ),
        ],
      ],
    ),
  );

  // DF-021: Số trên mỗi nhãn được đếm từ danh sách gốc đã tải.
  int _statusCount(RepairStatus status) =>
      _jobs.where((job) => job.status == status).length;
}
