import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/phone_capture_service.dart';

class PhoneCaptureDialog extends StatefulWidget {
  const PhoneCaptureDialog({
    super.key,
    required this.targets,
    this.initialTargetId,
  });

  final List<PhoneCaptureTarget> targets;
  final String? initialTargetId;

  static Future<List<PhoneCaptureUpload>> capture({
    required BuildContext context,
    required List<PhoneCaptureTarget> targets,
    String? initialTargetId,
  }) async {
    final uploads = await showDialog<List<PhoneCaptureUpload>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhoneCaptureDialog(
        targets: targets,
        initialTargetId: initialTargetId,
      ),
    );

    return uploads ?? const [];
  }

  @override
  State<PhoneCaptureDialog> createState() => _PhoneCaptureDialogState();
}

class _PhoneCaptureDialogState extends State<PhoneCaptureDialog> {
  PhoneCaptureSession? _session;
  String? _error;
  bool _starting = true;
  bool _keepReceivedFiles = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) {
      unawaited(session.dispose(deleteFiles: !_keepReceivedFiles));
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final session = await PhoneCaptureService.startSession(
        targets: widget.targets,
        initialTargetId: widget.initialTargetId,
      );
      if (!mounted) {
        await session.dispose(deleteFiles: true);
        return;
      }
      setState(() {
        _session = session;
        _starting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _starting = false;
      });
    }
  }

  void _done() {
    final uploads = _session?.uploads.value ?? const <PhoneCaptureUpload>[];
    _keepReceivedFiles = true;
    Navigator.of(context).pop(uploads);
  }

  void _cancel() {
    Navigator.of(context).pop(const <PhoneCaptureUpload>[]);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return AlertDialog(
      title: const Text('Capture with phone'),
      content: SizedBox(
        width: 760,
        child: _starting
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? _ErrorState(message: _error!)
                : session == null
                    ? const _ErrorState(
                        message: 'Phone capture could not be started.',
                      )
                    : _CaptureSessionView(session: session),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: Text(_error == null ? 'Cancel' : 'Close'),
        ),
        if (_error == null)
          FilledButton.icon(
            onPressed: session == null ? null : _done,
            icon: const Icon(Icons.check_outlined),
            label: const Text('Done'),
          ),
      ],
    );
  }
}

class _CaptureSessionView extends StatelessWidget {
  const _CaptureSessionView({required this.session});

  final PhoneCaptureSession session;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: QrImageView(
                data: session.url,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phone photo capture',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Scan once. On the phone, choose the destination before taking each photo.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'If the phone cannot open the page, allow the Windows firewall prompt and make sure both devices are on the same local network.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    session.url,
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ValueListenableBuilder<List<PhoneCaptureUpload>>(
          valueListenable: session.uploads,
          builder: (context, uploads, _) {
            if (uploads.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Text('No phone photos received yet.'),
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${uploads.length} photo${uploads.length == 1 ? '' : 's'} received',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final target in session.targets) ...[
                      _TargetUploadGroup(
                        target: target,
                        uploads: uploads
                            .where((upload) => upload.targetId == target.id)
                            .toList(growable: false),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TargetUploadGroup extends StatelessWidget {
  const _TargetUploadGroup({
    required this.target,
    required this.uploads,
  });

  final PhoneCaptureTarget target;
  final List<PhoneCaptureUpload> uploads;

  @override
  Widget build(BuildContext context) {
    if (uploads.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${target.label} (${uploads.length})',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final upload in uploads) _ReceivedPhotoTile(upload: upload),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceivedPhotoTile extends StatelessWidget {
  const _ReceivedPhotoTile({required this.upload});

  final PhoneCaptureUpload upload;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(upload.path),
              width: 92,
              height: 92,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  width: 92,
                  height: 92,
                  color: Colors.grey.shade100,
                  child: const Icon(Icons.image_outlined),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatBytes(upload.sizeBytes),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
