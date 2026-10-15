import 'package:flutter/material.dart';

import 'info_row.dart';
import 'section_card.dart';
import 'user_avatar.dart';

/// Tab "Tài khoản" dùng chung cho kỹ thuật viên và quản lý: tên, vai trò, vài dòng thông tin, nút đăng xuất.
class AccountView extends StatelessWidget {
  final String name;
  final String roleLabel;
  final Map<String, String> info; // nhãn -> giá trị
  final VoidCallback onSignOut;

  const AccountView({
    super.key,
    required this.name,
    required this.roleLabel,
    required this.onSignOut,
    this.info = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            child: Row(
              children: [
                UserAvatar(name, radius: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        roleLabel,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (info.isNotEmpty)
            SectionCard(
              title: 'Thông tin',
              child: Column(
                children: [
                  for (final e in info.entries) InfoRow(e.key, e.value),
                ],
              ),
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
      ),
    );
  }
}
