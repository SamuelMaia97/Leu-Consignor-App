import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';

Future<void> showSyncReportDialog(
  BuildContext context,
  List<RemoteReportFieldIssue> issues,
) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final width = math.min(760.0, math.max(280.0, size.width - 48));
      final height = math.min(560.0, math.max(260.0, size.height - 96));

      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: width,
          height: issues.isEmpty ? null : height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
            child: Column(
              mainAxisSize:
                  issues.isEmpty ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Abacus report fields',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                if (issues.isEmpty)
                  const Text(
                    'No missing report fields were found in the last sync.',
                  )
                else ...[
                  Text(
                    '${issues.length} report row${issues.length == 1 ? '' : 's'} had fields missing from /get-all.',
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: issues.length,
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final issue = issues[index];
                        return _ReportIssueTile(issue: issue);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ReportIssueTile extends StatelessWidget {
  const _ReportIssueTile({required this.issue});

  final RemoteReportFieldIssue issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missingText = issue.missingFields.join(', ');
    final availableText = issue.availableFields.isEmpty
        ? 'No fields'
        : issue.availableFields.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(issue.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text('Missing: $missingText'),
        const SizedBox(height: 4),
        Text(
          'Available: $availableText',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
