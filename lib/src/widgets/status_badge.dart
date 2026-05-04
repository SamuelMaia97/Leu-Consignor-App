import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.onTap,
  });

  final String label;
  final StatusBadgeTone tone;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final config = switch (tone) {
      StatusBadgeTone.success => (
          palette.success.withValues(alpha: 0.12),
          palette.success,
        ),
      StatusBadgeTone.warning => (
          palette.warning.withValues(alpha: 0.12),
          palette.warning,
        ),
      StatusBadgeTone.error => (
          palette.error.withValues(alpha: 0.12),
          palette.error,
        ),
      StatusBadgeTone.info => (
          palette.info.withValues(alpha: 0.12),
          palette.info,
        ),
      StatusBadgeTone.neutral => (palette.brandSoft, palette.textMuted),
    };

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: config.$1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: config.$2.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: config.$2),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: config.$2,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

enum StatusBadgeTone { success, warning, error, info, neutral }