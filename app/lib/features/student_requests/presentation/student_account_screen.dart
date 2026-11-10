import 'package:flutter/material.dart';

import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/user_avatar.dart';

/// Tab "Tài khoản" của sinh viên: thông tin cơ bản và nút đăng xuất.
/// (Hồ sơ đầy đủ và đổi mật khẩu là chức năng của An, sẽ gắn thêm vào đây.)
class StudentAccountScreen extends StatelessWidget {
  final String? name;
  final String? roomCode;
  final VoidCallback onSignOut;
  final bool embedded;

  const StudentAccountScreen({
    super.key,
    required this.name,
    required this.roomCode,
    required this.onSignOut,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          child: Row(
            children: [
              UserAvatar(name ?? '?', radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? 'Sinh viên',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Sinh viên',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Thông tin',
          child: InfoRow('Phòng', roomCode ?? 'Chưa được gắn phòng'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
        ),
      ],
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: body,
    );
  }
}
