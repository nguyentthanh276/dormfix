import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/profile_repository.dart';
import '../models/phone_rules.dart';
import 'active_change_password_page.dart';
import 'profile_controller.dart';

/// Màn hình Hồ sơ cá nhân (DF-005, DF-018, DF-006, DF-019).
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.controller,
    this.profileRepository,
    this.onSignOut,
    this.title = 'Hồ sơ cá nhân',
  });

  final AuthController controller;
  final ProfileRepository? profileRepository;
  final VoidCallback? onSignOut;
  final String title;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileController _profileController;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneInputController;

  @override
  void initState() {
    super.initState();
    _profileController = ProfileController(
      authController: widget.controller,
      repository: widget.profileRepository,
    );
    _phoneInputController = TextEditingController(
      text: widget.controller.profile?.phone ?? '',
    );
  }

  @override
  void dispose() {
    _phoneInputController.dispose();
    _profileController.dispose();
    super.dispose();
  }

  Future<void> _submitPhone() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate() || _profileController.isLoading) {
      return;
    }

    final success = await _profileController.updatePhone(
      _phoneInputController.text,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cập nhật số điện thoại thành công.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _profileController]),
      builder: (context, _) {
        final profile = widget.controller.profile;

        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.account_circle_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Không tìm thấy thông tin hồ sơ.',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: widget.onSignOut ?? widget.controller.signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Đăng xuất'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final isStudent = profile.role == AppRole.student;
        final identityLabel = isStudent ? 'Mã sinh viên' : 'Mã kỹ thuật viên';
        final roomCode = profile.room?.code ?? 'Chưa được gắn phòng';

        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Card Avatar & Tên tóm tắt (Họ tên hiển thị duy nhất tại đây)
              SectionCard(
                child: Row(
                  children: [
                    UserAvatar(profile.fullName ?? '?', radius: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.fullName ?? 'Chưa có tên',
                            key: const Key('profile-name'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.role?.label ?? 'Người dùng',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Card thông tin cá nhân (Read-only)
              SectionCard(
                title: 'Thông tin',
                child: Column(
                  children: [
                    if (profile.identityCode != null)
                      InfoRow(identityLabel, profile.identityCode!),
                    if (profile.email != null) InfoRow('Email', profile.email!),
                    if (isStudent) InfoRow('Phòng', roomCode),
                    InfoRow(
                      'Số điện thoại',
                      profile.phone != null && profile.phone!.isNotEmpty
                          ? profile.phone!
                          : 'Chưa có số điện thoại',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Nút Đăng xuất ở vị trí hiển thị ngay trên màn hình chuẩn
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  key: const Key('profile-logout-btn'),
                  onPressed: _profileController.isLoading
                      ? null
                      : (widget.onSignOut ?? widget.controller.signOut),
                  icon: const Icon(Icons.logout),
                  label: const Text('Đăng xuất'),
                ),
              ),

              const SizedBox(height: 16),

              // Card Cập nhật số điện thoại (Editable)
              SectionCard(
                title: 'Cập nhật số điện thoại',
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('profile-phone-input'),
                        controller: _phoneInputController,
                        enabled: !_profileController.isLoading,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submitPhone(),
                        onChanged: (_) => _profileController.clearError(),
                        decoration: const InputDecoration(
                          labelText: 'Số điện thoại mới',
                          prefixIcon: Icon(Icons.phone_outlined),
                          hintText: 'Nhập số điện thoại (VD: 0901234567)',
                          isDense: true,
                        ),
                        validator: PhoneRules.validatePhone,
                      ),
                      if (_profileController.error case final error?) ...[
                        const SizedBox(height: 8),
                        Text(
                          error,
                          key: const Key('profile-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: const Key('profile-save-phone-btn'),
                        onPressed: _profileController.isLoading
                            ? null
                            : _submitPhone,
                        icon: _profileController.isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Lưu thay đổi'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Card Đổi mật khẩu (DF-004)
              SectionCard(
                title: 'Bảo mật tài khoản',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Đổi mật khẩu định kỳ để bảo vệ an toàn cho tài khoản.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('profile-change-password-btn'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ActiveChangePasswordPage(
                              controller: widget.controller,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.lock_reset_outlined),
                      label: const Text('Đổi mật khẩu'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
