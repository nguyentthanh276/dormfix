import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../admin_accounts/data/admin_accounts_repository.dart';
import '../../admin_accounts/presentation/admin_accounts_page.dart';
import '../../admin_rooms/presentation/admin_room_list_screen.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../incident_categories/presentation/category_list_screen.dart';
import '../data/admin_request_repository.dart';
import 'admin_requests_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({
    super.key,
    required this.controller,
    this.accountsRepository,
    this.requestsRepository,
  });

  final AuthController controller;
  final AdminAccountsRepository? accountsRepository;
  final AdminRequestRepository? requestsRepository;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  bool _showAccounts = false;
  bool _showRequests = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    if (profile == null || profile.role != AppRole.admin) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền truy cập.')),
      );
    }

    if (_showAccounts) return _accountsPage();
    if (_showRequests) return _requestsPage();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text(
          'DormFix - Quản lý KTX',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: widget.controller.isLoading
                  ? null
                  : widget.controller.signOut,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.logout, size: 18, color: Colors.white),
              label: const Text(
                'Đăng xuất',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // A. Header Chào mừng (Welcome Banner / Profile Summary Card)
              SectionCard(
                child: Row(
                  children: [
                    UserAvatar(profile.fullName ?? 'Admin', radius: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Xin chào quản lý${profile.fullName == null ? '' : ', ${profile.fullName}'}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (profile.email != null) ...[
                                Text(
                                  profile.email!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                                const Text(
                                  '•',
                                  style: TextStyle(color: Colors.black38),
                                ),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'Quản trị viên KTX',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Tiêu đề khu vực chức năng
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  'Chức năng quản trị',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.1,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // B. Quick Access Grid / Feature Cards
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 600;
                  final cardWidth = isWide
                      ? (constraints.maxWidth - 14) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _DashboardActionCard(
                          title: 'Quản lý yêu cầu sửa chữa',
                          description: 'Tiếp nhận, điều phối kỹ thuật viên và theo dõi tiến độ xử lý sự cố KTX',
                          icon: Icons.home_repair_service_outlined,
                          iconColor: AppColors.primaryDark,
                          iconBgColor: AppColors.primary.withValues(
                            alpha: 0.12,
                          ),
                          onTap: () => setState(() => _showRequests = true),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _DashboardActionCard(
                          title: 'Quản lý tài khoản',
                          description: 'Cấp mới, cập nhật hồ sơ, khóa/thu hồi và đặt lại mật khẩu cho Sinh viên & Kỹ thuật viên',
                          icon: Icons.manage_accounts_outlined,
                          iconColor: const Color(0xFF0284C7),
                          iconBgColor: const Color(0xFFE0F2FE),
                          onTap: () => setState(() => _showAccounts = true),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _DashboardActionCard(
                          title: 'Quản lý phòng ở',
                          description: 'Tra cứu, tìm kiếm và kiểm tra tình trạng phòng ở theo từng tòa nhà',
                          icon: Icons.meeting_room_outlined,
                          iconColor: const Color(0xFF059669),
                          iconBgColor: const Color(0xFFD1FAE5),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AdminRoomListScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _DashboardActionCard(
                          title: 'Danh mục sự cố',
                          description: 'Cấu hình loại sự cố, thời gian cam kết xử lý (SLA) và trạng thái hoạt động',
                          icon: Icons.category_outlined,
                          iconColor: const Color(0xFF7C3AED),
                          iconBgColor: const Color(0xFFEDE9FE),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const CategoryListScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountsPage() {
    final repository = widget.accountsRepository;
    if (repository == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Quản lý tài khoản'),
          leading: BackButton(
            onPressed: () => setState(() => _showAccounts = false),
          ),
        ),
        body: const Center(
          child: Text('Dịch vụ quản lý tài khoản chưa sẵn sàng.'),
        ),
      );
    }
    return AdminAccountsPage(
      repository: repository,
      isAdmin: true,
      onBack: () => setState(() => _showAccounts = false),
    );
  }

  Widget _requestsPage() {
    final repository = widget.requestsRepository;
    if (repository == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Yêu cầu sửa chữa'),
          leading: BackButton(
            onPressed: () => setState(() => _showRequests = false),
          ),
        ),
        body: const Center(
          child: Text('Dịch vụ yêu cầu sửa chữa chưa sẵn sàng.'),
        ),
      );
    }
    return AdminRequestsPage(
      repository: repository,
      isAdmin: true,
      onSignOut: widget.controller.signOut,
      onBack: () => setState(() => _showRequests = false),
    );
  }
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.black.withValues(alpha: 0.08),
          width: 0.9,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
