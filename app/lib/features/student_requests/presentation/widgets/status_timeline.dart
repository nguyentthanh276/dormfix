import 'package:flutter/material.dart';

import '../../../../core/theme/status_colors.dart';
import '../../models/history_entry.dart';

/// Dòng thời gian của yêu cầu: chấm màu theo trạng thái, nối nhau bằng đường kẻ dọc.
class StatusTimeline extends StatelessWidget {
  final List<HistoryEntry> entries;

  const StatusTimeline({super.key, required this.entries});

  String _two(int n) => n.toString().padLeft(2, '0');

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          // IntrinsicHeight để đường kẻ dọc kéo dài đúng bằng chiều cao nội dung.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: entries[i].status.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (i < entries.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: Colors.grey.shade300,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < entries.length - 1 ? 16 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entries[i].status.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: entries[i].status.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (entries[i].actorName case final actorName?)
                          Text(actorName, style: const TextStyle(fontSize: 12)),
                        Text(
                          entries[i].note,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _date(entries[i].createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
