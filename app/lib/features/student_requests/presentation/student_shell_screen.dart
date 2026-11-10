import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/role_navigation_bar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/data/mock_notification_repository.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/presentation/student_notifications_screen.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_page.dart';
import '../../student_confirmation/data/confirmation_repository.dart';
import '../../student_confirmation/presentation/awaiting_confirmation_screen.dart';
import '../data/request_repository.dart';
import 'create_request_screen.dart';
import 'my_requests_screen.dart';
import 'student_account_screen.dart';

/// Tab state belongs to one authenticated StudentHome and is discarded on logout.
class StudentShellScreen extends StatefulWidget {
  const StudentShellScreen({
    super.key,
    required this.repository,
    required this.name,
    required this.roomCode,
    required this.onSignOut,
    this.controller,
    this.profileRepository,
    this.notificationRepository,
  });

  final RequestRepository repository;
  final String? name;
  final String? roomCode;
  final VoidCallback onSignOut;
  final AuthController? controller;
  final ProfileRepository? profileRepository;
  final NotificationRepository? notificationRepository;

  @override
  State<StudentShellScreen> createState() => _StudentShellScreenState();
}

class _StudentShellScreenState extends State<StudentShellScreen>
    with WidgetsBindingObserver {
  static const _titles = [
    'Yêu cầu của tôi',
    'Chờ xác nhận',
    'Thông báo',
    'Tài khoản cá nhân',
  ];
  final _storage = PageStorageBucket();
  final _visitedTabs = <int>{0};
  late ConfirmationRepository _confirmationRepository;
  late NotificationRepository _notificationRepository;
  int _tab = 0;
  int _refreshRevision = 0;
  int _unreadCount = 0;
  int _unreadGeneration = 0;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _confirmationRepository = AdapterConfirmationRepository(widget.repository);
    _notificationRepository =
        widget.notificationRepository ?? MockNotificationRepository();
    unawaited(_loadUnreadCount());
  }

  @override
  void didUpdateWidget(covariant StudentShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _confirmationRepository = AdapterConfirmationRepository(
        widget.repository,
      );
      _refreshRevision++;
    }
    if (oldWidget.notificationRepository != widget.notificationRepository) {
      _notificationRepository =
          widget.notificationRepository ?? MockNotificationRepository();
      _unreadCount = 0;
      unawaited(_loadUnreadCount());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadUnreadCount());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    final generation = ++_unreadGeneration;
    int count;
    try {
      count = await _notificationRepository.getUnreadCount();
    } catch (_) {
      count = 0;
    }
    if (!mounted || generation != _unreadGeneration || count == _unreadCount) {
      return;
    }
    setState(() => _unreadCount = count);
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
      _visitedTabs.add(index);
    });
    // The inbox refreshes its own unread count after loading.
    if (index != 2) unawaited(_loadUnreadCount());
  }

  Future<void> _createRequest() async {
    if (_creating) return;
    _creating = true;
    var created = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => CreateRequestScreen(
          repository: widget.repository,
          roomCode: widget.roomCode,
          onCreated: () {
            created = true;
            Navigator.of(routeContext).pop();
          },
        ),
      ),
    );
    if (!mounted) return;
    _creating = false;
    if (created) setState(() => _refreshRevision++);
  }

  Widget _page(int index) {
    if (!_visitedTabs.contains(index)) return const SizedBox.shrink();
    final active = _tab == index;
    return TickerMode(
      enabled: active,
      child: switch (index) {
        0 => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.roomCode == null
                          ? 'Chưa được gắn phòng'
                          : 'Phòng ${widget.roomCode}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('student-create-request'),
                    onPressed: _createRequest,
                    icon: const Icon(Icons.add),
                    label: const Text('Tạo yêu cầu'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MyRequestsScreen(
                repository: widget.repository,
                notificationRepository: _notificationRepository,
                embedded: true,
                active: active,
                refreshRevision: _refreshRevision,
              ),
            ),
          ],
        ),
        1 => AwaitingConfirmationScreen(
          repository: _confirmationRepository,
          requestRepository: widget.repository,
          embedded: true,
          active: active,
          refreshRevision: _refreshRevision,
        ),
        2 => StudentNotificationsScreen(
          notificationRepository: _notificationRepository,
          requestRepository: widget.repository,
          embedded: true,
          active: active,
          refreshRevision: _refreshRevision,
          onUnreadStateChanged: _loadUnreadCount,
        ),
        _ =>
          widget.controller != null
              ? ProfilePage(
                  controller: widget.controller!,
                  profileRepository: widget.profileRepository,
                  onSignOut: widget.onSignOut,
                  title: 'Tài khoản cá nhân',
                  embedded: true,
                  active: active,
                )
              : StudentAccountScreen(
                  name: widget.name,
                  roomCode: widget.roomCode,
                  onSignOut: widget.onSignOut,
                  embedded: true,
                ),
      },
    );
  }

  Widget _notificationIcon(IconData icon) {
    final iconWidget = Icon(icon);
    if (_unreadCount <= 0) return iconWidget;
    return Badge.count(count: _unreadCount, maxCount: 99, child: iconWidget);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: DormFixAppBar(
      title: _titles[_tab],
      roleLabel: 'Sinh viên',
      fullName: widget.name,
      automaticallyImplyLeading: false,
      onAccountTap: () => _selectTab(3),
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: PageStorage(
        bucket: _storage,
        child: IndexedStack(index: _tab, children: List.generate(4, _page)),
      ),
    ),
    bottomNavigationBar: RoleNavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: _selectTab,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment),
          label: 'Yêu cầu',
        ),
        const NavigationDestination(
          icon: Icon(Icons.assignment_turned_in_outlined),
          selectedIcon: Icon(Icons.assignment_turned_in),
          label: 'Chờ xác nhận',
        ),
        NavigationDestination(
          icon: _notificationIcon(Icons.notifications_outlined),
          selectedIcon: _notificationIcon(Icons.notifications),
          label: 'Thông báo',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Cá nhân',
        ),
      ],
    ),
  );
}
