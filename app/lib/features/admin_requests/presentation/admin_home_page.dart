import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/role_navigation_bar.dart';
import '../../admin_accounts/data/admin_account_management_repository.dart';
import '../../admin_accounts/data/admin_accounts_repository.dart';
import '../../admin_accounts/presentation/admin_accounts_page.dart';
import '../../admin_rooms/data/admin_room_repository.dart';
import '../../admin_rooms/presentation/admin_room_list_screen.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../incident_categories/data/incident_category_repository.dart';
import '../../incident_categories/presentation/category_list_screen.dart';
import '../data/admin_request_repository.dart';
import 'admin_requests_page.dart';

/// All Admin routes belong to this authenticated Home, including dialogs.
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({
    super.key,
    required this.controller,
    this.accountsRepository,
    this.accountManagementRepository,
    this.requestsRepository,
    this.roomsRepository,
    this.categoriesRepository,
  });

  final AuthController controller;
  final AdminAccountsRepository? accountsRepository;
  final AdminAccountManagementRepository? accountManagementRepository;
  final AdminRequestRepository? requestsRepository;
  final AdminRoomRepository? roomsRepository;
  final IncidentCategoryRepository? categoriesRepository;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  static const _titles = [
    'Quản lý yêu cầu',
    'Quản lý tài khoản',
    'Quản lý phòng',
    'Loại sự cố',
  ];
  final _navigatorKey = GlobalKey<NavigatorState>();
  final List<Widget?> _pages = List.filled(4, null);
  int _tab = 0;
  String? _identity;

  bool get _hasAccess {
    final profile = widget.controller.profile;
    return widget.controller.state == AuthViewState.authenticated &&
        profile?.role == AppRole.admin &&
        profile?.status == 'active' &&
        profile?.canAccess == true &&
        profile?.mustChangePassword == false;
  }

  @override
  void initState() {
    super.initState();
    _identity = widget.controller.profile?.id;
    widget.controller.addListener(_authChanged);
  }

  @override
  void didUpdateWidget(covariant AdminHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_authChanged);
      widget.controller.addListener(_authChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.accountsRepository != widget.accountsRepository ||
        oldWidget.accountManagementRepository !=
            widget.accountManagementRepository ||
        oldWidget.requestsRepository != widget.requestsRepository ||
        oldWidget.roomsRepository != widget.roomsRepository ||
        oldWidget.categoriesRepository != widget.categoriesRepository) {
      _resetPages();
    }
  }

  void _resetPages() {
    _pages.fillRange(0, _pages.length, null);
    _tab = 0;
  }

  void _authChanged() {
    if (!mounted) return;
    final identity = widget.controller.profile?.id;
    setState(() {
      if (!_hasAccess || identity != _identity) _resetPages();
      _identity = identity;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_authChanged);
    super.dispose();
  }

  Widget _page(int index) => _pages[index] ??= switch (index) {
    0 =>
      widget.requestsRepository == null
          ? const Center(child: Text('Dịch vụ yêu cầu sửa chữa chưa sẵn sàng.'))
          : AdminRequestsPage(
              repository: widget.requestsRepository!,
              isAdmin: true,
              onSignOut: widget.controller.signOut,
              embedded: true,
            ),
    1 =>
      widget.accountsRepository == null
          ? const Center(
              child: Text('Dịch vụ quản lý tài khoản chưa sẵn sàng.'),
            )
          : AdminAccountsPage(
              repository: widget.accountsRepository!,
              managementRepository: widget.accountManagementRepository,
              roomRepository: widget.roomsRepository,
              isAdmin: true,
              embedded: true,
            ),
    2 => AdminRoomListScreen(
      repository: widget.roomsRepository ?? UnavailableAdminRoomRepository(),
      embedded: true,
    ),
    _ => CategoryListScreen(
      repository:
          widget.categoriesRepository ??
          UnavailableIncidentCategoryRepository(),
      embedded: true,
    ),
  };

  Future<void> _accountMenu(BuildContext context) async {
    final profile = widget.controller.profile;
    final shouldSignOut = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                profile?.fullName ?? 'Admin',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(profile?.email ?? ''),
              const SizedBox(height: 4),
              const Text('Admin'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: widget.controller.isLoading
                    ? null
                    : () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && _hasAccess && shouldSignOut == true) {
      await widget.controller.signOut();
    }
  }

  Widget _shell(BuildContext context) {
    _page(_tab);
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) setState(() => _tab = 0);
      },
      child: Scaffold(
        appBar: DormFixAppBar(
          title: _titles[_tab],
          roleLabel: 'Admin',
          fullName: widget.controller.profile?.fullName,
          automaticallyImplyLeading: false,
          onAccountTap: () => unawaited(_accountMenu(context)),
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: List.generate(
              4,
              (index) => TickerMode(
                enabled: index == _tab,
                child: _pages[index] ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        bottomNavigationBar: RoleNavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment),
              label: 'Yêu cầu',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Tài khoản',
            ),
            NavigationDestination(
              icon: Icon(Icons.meeting_room_outlined),
              selectedIcon: Icon(Icons.meeting_room),
              label: 'Phòng',
            ),
            NavigationDestination(
              icon: Icon(Icons.category_outlined),
              selectedIcon: Icon(Icons.category),
              label: 'Loại sự cố',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền truy cập.')),
      );
    }
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (result) => _navigatorKey.currentState?.maybePop(result),
      child: Navigator(
        key: _navigatorKey,
        pages: [
          MaterialPage<void>(
            key: ValueKey('admin-shell-$_identity'),
            child: Builder(builder: _shell),
          ),
        ],
        onDidRemovePage: (_) {},
      ),
    );
  }
}
