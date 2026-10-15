import 'package:flutter/material.dart';

import '../../../core/models/repair_status.dart';

String technicianDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

class TechnicianStatusBadge extends StatelessWidget {
  const TechnicianStatusBadge({super.key, required this.status});

  final RepairStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      RepairStatus.completed => Colors.green.shade800,
      RepairStatus.cancelled || RepairStatus.rejected => scheme.error,
      RepairStatus.awaitingRework => Colors.deepOrange.shade800,
      _ => scheme.secondary,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(status.label, style: TextStyle(color: color)),
      ),
    );
  }
}

class TechnicianJobsMessage extends StatelessWidget {
  const TechnicianJobsMessage({
    super.key,
    required this.icon,
    required this.message,
    this.secondary,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? secondary;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (secondary != null) ...[
            const SizedBox(height: 12),
            Text(secondary!, textAlign: TextAlign.center),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
