import 'package:flutter/material.dart';

import '../utils/workflow_status.dart';
import 'status_badge.dart';

class PassportStatusBadge extends StatelessWidget {
  const PassportStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final PassportStatusInfo status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: compact ? _compactLabel(status) : _label(status),
      tone: _tone(status.kind),
      icon: _icon(status.kind),
    );
  }

  static String _label(PassportStatusInfo status) {
    final date = status.validUntil;
    if (date == null) return status.label;
    return '${status.label} until ${_formatDate(date)}';
  }

  static String _compactLabel(PassportStatusInfo status) {
    final date = status.validUntil;
    if (date == null) return status.label;
    return '${status.label}: ${_formatDate(date)}';
  }

  static String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  static StatusBadgeTone _tone(PassportStatusKind kind) {
    switch (kind) {
      case PassportStatusKind.valid:
        return StatusBadgeTone.success;
      case PassportStatusKind.expired:
        return StatusBadgeTone.error;
      case PassportStatusKind.missing:
      case PassportStatusKind.expiryMissing:
        return StatusBadgeTone.warning;
    }
  }

  static IconData _icon(PassportStatusKind kind) {
    switch (kind) {
      case PassportStatusKind.valid:
        return Icons.verified_outlined;
      case PassportStatusKind.expired:
        return Icons.warning_amber_rounded;
      case PassportStatusKind.missing:
        return Icons.no_photography_outlined;
      case PassportStatusKind.expiryMissing:
        return Icons.event_busy_outlined;
    }
  }
}
