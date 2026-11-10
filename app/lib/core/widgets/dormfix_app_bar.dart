import 'package:flutter/material.dart';

/// Shared mobile header. Root pages supply the role and an account shortcut;
/// pushed pages use the same header with Flutter's normal Back button.
class DormFixAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DormFixAppBar({
    super.key,
    required this.title,
    this.roleLabel,
    this.fullName,
    this.onAccountTap,
    this.leading,
    this.actions = const [],
    this.automaticallyImplyLeading = true,
  });

  final String title;
  final String? roleLabel;
  final String? fullName;
  final VoidCallback? onAccountTap;
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => Size.fromHeight(roleLabel == null ? 56 : 72);

  @override
  Widget build(BuildContext context) {
    final name = fullName?.trim() ?? '';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.characters.first.toUpperCase()
        : '${parts.first.characters.first}${parts.last.characters.first}'
              .toUpperCase();
    return AppBar(
      toolbarHeight: preferredSize.height,
      centerTitle: false,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (roleLabel != null)
            Text(
              'DormFix · $roleLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
        ],
      ),
      actions: [
        ...actions,
        if (onAccountTap != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              key: const Key('dormfix-account-menu'),
              tooltip: 'Tài khoản cá nhân',
              onPressed: onAccountTap,
              icon: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70),
                ),
                child: Text(
                  initials,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
