import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../models/repair_request.dart';
import 'category_icon.dart';

/// The same hierarchy as the shared mobile proposal: code/status, title, metadata.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final RepairRequest request;
  final VoidCallback? onTap;

  String _two(int n) => n.toString().padLeft(2, '0');

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    final secondary = Theme.of(context).textTheme.bodySmall;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(r.requestCode, style: secondary),
                  StatusChip(r.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.meeting_room_outlined, size: 16),
                  Text(
                    r.roomCode,
                    style: const TextStyle(color: AppColors.primaryDark),
                  ),
                  Text('· ${r.categoryName}', style: secondary),
                  Icon(categoryIcon(r.categoryName), size: 16),
                ],
              ),
              const SizedBox(height: 8),
              Text(_date(r.createdAt), style: secondary),
            ],
          ),
        ),
      ),
    );
  }
}
