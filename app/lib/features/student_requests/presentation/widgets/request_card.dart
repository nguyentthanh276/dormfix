import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/status_colors.dart';
import '../../models/repair_request.dart';
import 'category_icon.dart';

/// Thẻ một yêu cầu: mã, loại, phòng, tiêu đề, ngày gửi; chân thẻ màu cam hiện trạng thái.
class RequestCard extends StatelessWidget {
  final RepairRequest request;
  final VoidCallback? onTap; // bấm thẻ để mở chi tiết

  const RequestCard({super.key, required this.request, this.onTap});

  String _two(int n) => n.toString().padLeft(2, '0');

  String _date(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        r.requestCode,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        categoryIcon(r.categoryName),
                        size: 16,
                        color: Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        r.categoryName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Phòng: ', style: TextStyle(fontSize: 13)),
                      Text(
                        r.roomCode,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _date(r.createdAt),
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Container(
              color: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: r.status.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Trạng thái : ${r.status.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
