import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_page.dart';
import '../data/technician_jobs_repository.dart';
import '../data/technician_workflow_repository.dart';
import '../models/technician_job.dart';
import 'technician_job_detail_page.dart';
import 'technician_job_widgets.dart';

class TechnicianHomePage extends StatefulWidget {
  const TechnicianHomePage({
    super.key,
    required this.controller,
    this.repository,
    this.workflowRepository,
    this.profileRepository,
  });

  final AuthController controller;
  final TechnicianJobsRepository? repository;
  final TechnicianWorkflowRepository? workflowRepository;
  final ProfileRepository? profileRepository;

  @override
  State<TechnicianHomePage> createState() => _TechnicianHomePageState();
}

class _TechnicianHomePageState extends State<TechnicianHomePage>
    with WidgetsBindingObserver {
  List<TechnicianJob> _jobs = [];
  String? _identity;
  String? _selectedJobId;
  String? _error;
  bool _loading = false;
  bool _refreshQueued = false;
  bool _allowed = false;
  int _generation = 0;

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
        oldWidget.workflowRepository != widget.workflowRepository) {
      _reset();
      _allowed = _hasAccess;
      _identity = _allowed ? widget.controller.profile!.id : null;
      unawaited(_loadJobs());
    }
  }

  void _reset() {
    _generation++;
    _jobs = [];
    _selectedJobId = null;
    _error = null;
    _loading = false;
    _refreshQueued = false;
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
    if (state == AppLifecycleState.resumed && _selectedJobId == null) {
      unawaited(_loadJobs());
    }
  }

  bool _isCurrent(int generation, String identity) =>
      mounted &&
      generation == _generation &&
      _hasAccess &&
      widget.controller.profile?.id == identity;

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

  void _backToList() {
    setState(() => _selectedJobId = null);
    unawaited(_loadJobs());
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
    final selectedId = _selectedJobId;
    // Detail is local state, never a route on the application's Navigator.
    // Removing this authenticated Home removes every detail and photo.
    return PopScope(
      canPop: selectedId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedJobId != null) _backToList();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: selectedId == null
              ? null
              : BackButton(onPressed: _backToList),
          title: Text(
            selectedId == null
                ? 'DormFix - Kỹ thuật viên'
                : 'Chi tiết công việc',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              key: const Key('technician-profile-btn'),
              tooltip: 'Hồ sơ cá nhân',
              icon: const Icon(Icons.person_outline),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfilePage(
                      controller: widget.controller,
                      profileRepository: widget.profileRepository,
                      onSignOut: () {
                        Navigator.of(context).pop();
                        unawaited(widget.controller.signOut());
                      },
                    ),
                  ),
                );
              },
            ),
            TextButton.icon(
              onPressed: widget.controller.isLoading
                  ? null
                  : () => unawaited(widget.controller.signOut()),
              icon: widget.controller.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
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
                child: selectedId != null && widget.repository != null
                    ? TechnicianJobDetailPage(
                        key: ValueKey('$_identity:$selectedId'),
                        requestId: selectedId,
                        repository: widget.repository!,
                        onAccessDenied: _detailAccessDenied,
                        workflowRepository: widget.workflowRepository,
                        onJobChanged: () => _jobWriteFinished(identity),
                      )
                    : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          : ListView.separated(
              key: const Key('technician-jobs-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final job = _jobs[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() => _selectedJobId = job.id),
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
    );
  }
}
