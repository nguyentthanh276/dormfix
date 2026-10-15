import 'package:flutter/material.dart';

/// Giao diện khi danh sách rỗng: biểu tượng và một dòng chữ.
class EmptyView extends StatelessWidget {
  final String text;

  const EmptyView(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
