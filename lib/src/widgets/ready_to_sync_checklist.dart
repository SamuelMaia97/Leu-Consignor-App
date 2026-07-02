import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/workflow_status.dart';

class ReadyToSyncChecklist extends StatelessWidget {
  const ReadyToSyncChecklist({
    super.key,
    required this.issues,
    this.emptyTitle = 'Ready to sync',
    this.emptyMessage = 'No missing or suspicious items detected.',
    this.maxVisibleItems,
  });

  final List<ReadinessIssue> issues;
  final String emptyTitle;
  final String emptyMessage;
  final int? maxVisibleItems;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return _ChecklistMessage(
        icon: Icons.check_circle_outline_rounded,
        color: context.palette.success,
        title: emptyTitle,
        message: emptyMessage,
      );
    }

    final visibleIssues = maxVisibleItems == null
        ? issues
        : issues.take(maxVisibleItems!).toList(growable: false);
    final hiddenCount = issues.length - visibleIssues.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final issue in visibleIssues)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _IssueRow(issue: issue),
          ),
        if (hiddenCount > 0)
          Text(
            '$hiddenCount more checklist item${hiddenCount == 1 ? '' : 's'} hidden.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
          ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});

  final ReadinessIssue issue;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = issue.severity == ReadinessSeverity.error
        ? palette.error
        : palette.warning;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            issue.severity == ReadinessSeverity.error
                ? Icons.error_outline_rounded
                : Icons.warning_amber_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(issue.detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistMessage extends StatelessWidget {
  const _ChecklistMessage({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
