import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class PhoneCaptureTarget {
  const PhoneCaptureTarget({
    required this.id,
    required this.label,
    required this.filePrefix,
  });

  final String id;
  final String label;
  final String filePrefix;
}

class PhoneCaptureUpload {
  const PhoneCaptureUpload({
    required this.targetId,
    required this.targetLabel,
    required this.path,
    required this.fileName,
    required this.receivedAt,
    required this.sizeBytes,
  });

  final String targetId;
  final String targetLabel;
  final String path;
  final String fileName;
  final DateTime receivedAt;
  final int sizeBytes;
}

class PhoneCaptureSession {
  PhoneCaptureSession({
    required this.url,
    required this.targets,
    required this.uploads,
    required HttpServer server,
    required Directory tempDirectory,
    required Future<void> Function({required bool deleteFiles}) disposeSession,
  })  : _server = server,
        _tempDirectory = tempDirectory,
        _disposeSession = disposeSession;

  final String url;
  final List<PhoneCaptureTarget> targets;
  final ValueNotifier<List<PhoneCaptureUpload>> uploads;
  final HttpServer _server;
  final Directory _tempDirectory;
  final Future<void> Function({required bool deleteFiles}) _disposeSession;

  int get port => _server.port;

  Future<void> dispose({bool deleteFiles = false}) {
    return _disposeSession(deleteFiles: deleteFiles);
  }

  Future<void> deleteReceivedFiles() async {
    if (await _tempDirectory.exists()) {
      await _tempDirectory.delete(recursive: true);
    }
  }
}

class PhoneCaptureService {
  static const int _maxFilesPerSession = 40;
  static const int _maxFileBytes = 25 * 1024 * 1024;
  static const Duration _sessionLifetime = Duration(minutes: 15);
  static final HtmlEscape _htmlEscape = HtmlEscape();

  static Future<PhoneCaptureSession> startSession({
    required List<PhoneCaptureTarget> targets,
    String? initialTargetId,
  }) async {
    if (targets.isEmpty) {
      throw Exception('No phone capture targets were configured.');
    }

    final hostAddress = await _localNetworkAddress();
    if (hostAddress == null) {
      throw Exception(
        'No local network address was found. Connect the Surface to Wi-Fi and try again.',
      );
    }

    final normalizedTargets = targets
        .where((target) => target.id.trim().isNotEmpty)
        .map(
          (target) => PhoneCaptureTarget(
            id: target.id.trim(),
            label: target.label.trim().isEmpty
                ? target.id.trim()
                : target.label.trim(),
            filePrefix: _sanitizeFileName(target.filePrefix),
          ),
        )
        .toList(growable: false);

    if (normalizedTargets.isEmpty) {
      throw Exception('No valid phone capture targets were configured.');
    }

    final token = _newToken();
    final expiresAt = DateTime.now().add(_sessionLifetime);
    final tempDirectory =
        await Directory.systemTemp.createTemp('leu_phone_capture_');
    final uploads = ValueNotifier<List<PhoneCaptureUpload>>(const []);
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    var disposed = false;

    PhoneCaptureTarget selectedTarget(HttpRequest request) {
      return _selectedTarget(
        targets: normalizedTargets,
        requestedTargetId: request.uri.queryParameters['target'],
        fallbackTargetId: initialTargetId,
      );
    }

    Future<void> handleRequest(HttpRequest request) async {
      try {
        if (!_validToken(request, token)) {
          await _sendHtml(
            request,
            _page(
              title: 'Invalid session',
              body: '<p>This capture session is no longer valid.</p>',
            ),
            statusCode: HttpStatus.forbidden,
          );
          return;
        }

        if (DateTime.now().isAfter(expiresAt)) {
          await _sendHtml(
            request,
            _page(
              title: 'Session expired',
              body:
                  '<p>This capture session has expired. Start a new phone capture session on the Surface app.</p>',
            ),
            statusCode: HttpStatus.gone,
          );
          return;
        }

        if (request.method == 'GET' && request.uri.path == '/capture') {
          await _sendHtml(
            request,
            _capturePage(
              targets: normalizedTargets,
              selectedTarget: selectedTarget(request),
              token: token,
              uploads: uploads.value,
            ),
          );
          return;
        }

        if (request.method == 'POST' && request.uri.path == '/upload') {
          if (uploads.value.length >= _maxFilesPerSession) {
            await _sendJson(
              request,
              {
                'ok': false,
                'message':
                    'The maximum number of photos for this session was reached.',
                'counts': _uploadCounts(normalizedTargets, uploads.value),
                'totalCount': uploads.value.length,
              },
              statusCode: HttpStatus.badRequest,
            );
            return;
          }

          final target = selectedTarget(request);
          final received = await _receiveUpload(
            request: request,
            tempDirectory: tempDirectory,
            target: target,
            nextIndex: _uploadCountForTarget(uploads.value, target.id) + 1,
          );

          if (received == null) {
            await _sendJson(
              request,
              {
                'ok': false,
                'message': 'No image file was received. Please choose a photo.',
                'counts': _uploadCounts(normalizedTargets, uploads.value),
                'totalCount': uploads.value.length,
              },
              statusCode: HttpStatus.badRequest,
            );
            return;
          }

          uploads.value = [...uploads.value, received];
          await _sendJson(
            request,
            {
              'ok': true,
              'message': 'Photo received by the Surface app.',
              'counts': _uploadCounts(normalizedTargets, uploads.value),
              'totalCount': uploads.value.length,
            },
          );
          return;
        }

        await _sendHtml(
          request,
          _page(
            title: 'Not found',
            body: '<p>The requested capture page was not found.</p>',
          ),
          statusCode: HttpStatus.notFound,
        );
      } catch (error) {
        if (request.method == 'POST' && request.uri.path == '/upload') {
          await _sendJson(
            request,
            {
              'ok': false,
              'message': error.toString(),
              'counts': _uploadCounts(normalizedTargets, uploads.value),
              'totalCount': uploads.value.length,
            },
            statusCode: HttpStatus.internalServerError,
          );
          return;
        }

        await _sendHtml(
          request,
          _capturePage(
            targets: normalizedTargets,
            selectedTarget: selectedTarget(request),
            token: token,
            uploads: uploads.value,
            error: _htmlEscape.convert(error.toString()),
          ),
          statusCode: HttpStatus.internalServerError,
        );
      }
    }

    unawaited(
      server.forEach((request) {
        unawaited(handleRequest(request));
      }),
    );

    final selected = _selectedTarget(
      targets: normalizedTargets,
      requestedTargetId: initialTargetId,
    );
    final url =
        'http://$hostAddress:${server.port}/capture?token=${Uri.encodeQueryComponent(token)}&target=${Uri.encodeQueryComponent(selected.id)}';

    Future<void> disposeSession({required bool deleteFiles}) async {
      if (disposed) return;
      disposed = true;
      await server.close(force: true);
      uploads.dispose();
      if (deleteFiles && await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }

    return PhoneCaptureSession(
      url: url,
      targets: normalizedTargets,
      uploads: uploads,
      server: server,
      tempDirectory: tempDirectory,
      disposeSession: disposeSession,
    );
  }

  static PhoneCaptureTarget _selectedTarget({
    required List<PhoneCaptureTarget> targets,
    String? requestedTargetId,
    String? fallbackTargetId,
  }) {
    PhoneCaptureTarget? byId(String? id) {
      if (id == null || id.trim().isEmpty) return null;
      for (final target in targets) {
        if (target.id == id.trim()) return target;
      }
      return null;
    }

    return byId(requestedTargetId) ?? byId(fallbackTargetId) ?? targets.first;
  }

  static Future<PhoneCaptureUpload?> _receiveUpload({
    required HttpRequest request,
    required Directory tempDirectory,
    required PhoneCaptureTarget target,
    required int nextIndex,
  }) async {
    final originalFileName = Uri.decodeComponent(
      request.headers.value('x-file-name') ?? 'phone_photo.jpg',
    );
    final requestContentType = request.headers.contentType?.mimeType;

    if (!_looksLikeImage(
      fileName: originalFileName,
      contentType: requestContentType,
    )) {
      throw Exception('Only image uploads are accepted.');
    }

    final extension = _extensionForUpload(
      fileName: originalFileName,
      contentType: requestContentType,
    );
    final fileName =
        '${target.filePrefix}_${DateTime.now().millisecondsSinceEpoch}_$nextIndex$extension';
    final path = '${tempDirectory.path}${Platform.pathSeparator}$fileName';
    final bytes = BytesBuilder(copy: false);
    var size = 0;

    await for (final chunk in request) {
      size += chunk.length;
      if (size > _maxFileBytes) {
        throw Exception('The selected image is larger than 25 MB.');
      }
      bytes.add(chunk);
    }

    if (size == 0) {
      return null;
    }

    final file = File(path);
    await file.writeAsBytes(bytes.takeBytes(), flush: true);
    return PhoneCaptureUpload(
      targetId: target.id,
      targetLabel: target.label,
      path: file.path,
      fileName: fileName,
      receivedAt: DateTime.now(),
      sizeBytes: size,
    );
  }

  static bool _validToken(HttpRequest request, String expectedToken) {
    return request.uri.queryParameters['token'] == expectedToken;
  }

  static Future<void> _sendHtml(
    HttpRequest request,
    String html, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.html
      ..write(html);
    await request.response.close();
  }

  static Future<void> _sendJson(
    HttpRequest request,
    Map<String, Object?> payload, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    await request.response.close();
  }

  static String _capturePage({
    required List<PhoneCaptureTarget> targets,
    required PhoneCaptureTarget selectedTarget,
    required String token,
    required List<PhoneCaptureUpload> uploads,
    String? error,
  }) {
    final escapedToken = Uri.encodeQueryComponent(token);
    final counts = _uploadCounts(targets, uploads);
    final targetsJson = _scriptJson(
      targets
          .map(
            (target) => {
              'id': target.id,
              'label': target.label,
            },
          )
          .toList(growable: false),
    );
    final countsJson = _scriptJson(counts);
    final selectedTargetJson = _scriptJson(selectedTarget.id);
    final errorBlock = error == null
        ? ''
        : '<div class="notice error">${_htmlEscape.convert(error)}</div>';

    return _page(
      title: 'Leu photo capture',
      body: '''
        <div class="target">Capturing</div>
        <h1 id="targetTitle">${_htmlEscape.convert(selectedTarget.label)}</h1>
        <div class="target-options" id="targetOptions"></div>
        <div id="notice" class="notice" hidden></div>
        $errorBlock
        <p class="count"><span id="totalCount">${uploads.length}</span> photo<span id="totalPlural">${uploads.length == 1 ? '' : 's'}</span> received by the Surface app.</p>
        <form id="captureForm">
          <label class="capture-button">
            <span id="buttonText">Take photo</span>
            <input id="photoInput" name="photo" type="file" accept="image/*" capture="environment" required>
          </label>
        </form>
        <p class="hint">Choose the destination above. After you confirm a photo, it uploads automatically. Take as many as needed, then return to the Surface and press Done.</p>
        <script>
          const targets = $targetsJson;
          let uploadedCounts = $countsJson;
          let currentTargetId = $selectedTargetJson;
          let uploading = false;

          const targetTitle = document.getElementById('targetTitle');
          const targetOptions = document.getElementById('targetOptions');
          const form = document.getElementById('captureForm');
          const input = document.getElementById('photoInput');
          const buttonText = document.getElementById('buttonText');
          const notice = document.getElementById('notice');
          const totalCount = document.getElementById('totalCount');
          const totalPlural = document.getElementById('totalPlural');

          function selectedTarget() {
            return targets.find((target) => target.id === currentTargetId) || targets[0];
          }

          function totalUploaded() {
            return Object.values(uploadedCounts).reduce((sum, count) => sum + Number(count || 0), 0);
          }

          function setNotice(message, isError) {
            if (!message) {
              notice.hidden = true;
              notice.textContent = '';
              notice.className = 'notice';
              return;
            }
            notice.hidden = false;
            notice.textContent = message;
            notice.className = isError ? 'notice error' : 'notice success';
          }

          function renderTargets() {
            targetOptions.innerHTML = '';
            for (const target of targets) {
              const button = document.createElement('button');
              button.type = 'button';
              button.className = target.id === currentTargetId
                ? 'target-option selected'
                : 'target-option';
              button.dataset.targetId = target.id;
              const count = Number(uploadedCounts[target.id] || 0);
              button.textContent = count > 0
                ? target.label + ' (' + count + ')'
                : target.label;
              button.addEventListener('click', () => {
                if (uploading) return;
                currentTargetId = target.id;
                setNotice('', false);
                render();
              });
              targetOptions.appendChild(button);
            }
          }

          function render() {
            const target = selectedTarget();
            const targetCount = Number(uploadedCounts[target.id] || 0);
            const total = totalUploaded();
            targetTitle.textContent = target.label;
            totalCount.textContent = String(total);
            totalPlural.textContent = total === 1 ? '' : 's';
            buttonText.textContent = uploading
              ? 'Uploading...'
              : targetCount === 0
                ? 'Take photo'
                : 'Take another photo';
            renderTargets();
          }

          async function uploadSelectedPhoto() {
            if (uploading) return;
            const file = input.files && input.files[0];
            if (!file) return;
            const target = selectedTarget();
            uploading = true;
            input.disabled = true;
            setNotice('', false);
            render();
            try {
              const response = await fetch('/upload?token=$escapedToken&target=' + encodeURIComponent(target.id), {
                method: 'POST',
                headers: {
                  'Content-Type': file.type || 'image/jpeg',
                  'X-File-Name': encodeURIComponent(file.name || 'phone_photo.jpg')
                },
                body: file
              });
              const payload = await response.json();
              if (!response.ok || !payload.ok) {
                throw new Error(payload.message || 'Upload failed.');
              }
              uploadedCounts = payload.counts || uploadedCounts;
              setNotice(payload.message || 'Photo received by the Surface app.', false);
            } catch (error) {
              setNotice(error.message || 'Upload failed. Check that the Surface app is still open and on the same network.', true);
            } finally {
              uploading = false;
              input.disabled = false;
              input.value = '';
              render();
            }
          }

          input.addEventListener('change', uploadSelectedPhoto);
          form.addEventListener('submit', (event) => {
            event.preventDefault();
            uploadSelectedPhoto();
          });

          render();
        </script>
      ''',
    );
  }

  static String _page({
    required String title,
    required String body,
  }) {
    final escapedTitle = _htmlEscape.convert(title);
    return '''
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>$escapedTitle</title>
        <style>
          :root {
            color-scheme: light;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            background: #f5f7fb;
            color: #172033;
          }
          body {
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px;
            box-sizing: border-box;
          }
          main {
            width: min(100%, 520px);
            background: #fff;
            border: 1px solid #dde3ee;
            border-radius: 18px;
            padding: 24px;
            box-shadow: 0 20px 50px rgba(23, 32, 51, 0.12);
          }
          h1 {
            margin: 4px 0 14px;
            font-size: clamp(26px, 7vw, 38px);
            line-height: 1.08;
          }
          .target {
            color: #536175;
            font-size: 13px;
            font-weight: 800;
            letter-spacing: 0.08em;
            text-transform: uppercase;
          }
          .target-options {
            display: grid;
            gap: 8px;
            margin: 12px 0 16px;
          }
          .target-option {
            width: 100%;
            border: 1px solid #cfd7e6;
            border-radius: 12px;
            background: #f9fbfe;
            color: #172033;
            font: inherit;
            font-weight: 800;
            min-height: 44px;
            padding: 8px 12px;
            text-align: left;
          }
          .target-option.selected {
            border-color: #0f4f8f;
            background: #eaf3fc;
            color: #0f4f8f;
          }
          .count, .hint {
            color: #536175;
            line-height: 1.45;
          }
          .notice {
            border-radius: 12px;
            margin: 12px 0;
            padding: 12px 14px;
            font-weight: 700;
          }
          .notice[hidden] {
            display: none;
          }
          .success {
            background: #e9f8ef;
            color: #106333;
          }
          .error {
            background: #fff0ef;
            color: #a2231a;
          }
          form {
            margin-top: 18px;
          }
          .capture-button {
            display: flex;
            min-height: 56px;
            align-items: center;
            justify-content: center;
            font-weight: 800;
            border-radius: 12px;
            padding: 0 18px;
            box-sizing: border-box;
            background: #0f4f8f;
            color: #fff;
            font-size: 17px;
            text-align: center;
          }
          input[type="file"] {
            position: fixed;
            width: 1px;
            height: 1px;
            opacity: 0;
            pointer-events: none;
          }
        </style>
      </head>
      <body>
        <main>$body</main>
      </body>
      </html>
    ''';
  }

  static Map<String, int> _uploadCounts(
    List<PhoneCaptureTarget> targets,
    List<PhoneCaptureUpload> uploads,
  ) {
    final counts = {
      for (final target in targets) target.id: 0,
    };
    for (final upload in uploads) {
      counts[upload.targetId] = (counts[upload.targetId] ?? 0) + 1;
    }
    return counts;
  }

  static int _uploadCountForTarget(
    List<PhoneCaptureUpload> uploads,
    String targetId,
  ) {
    return uploads.where((upload) => upload.targetId == targetId).length;
  }

  static String _scriptJson(Object? value) {
    return jsonEncode(value).replaceAll('</', r'<\/');
  }

  static String _newToken() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<String?> _localNetworkAddress() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final addresses = interfaces
        .expand((interface) => interface.addresses)
        .where((address) => !address.isLoopback)
        .map((address) => address.address)
        .where((address) => !_isLinkLocal(address))
        .toList(growable: false);

    if (addresses.isEmpty) {
      return null;
    }

    final privateAddress = addresses.cast<String?>().firstWhere(
          (address) => address != null && _isPrivateIpv4(address),
          orElse: () => null,
        );

    return privateAddress ?? addresses.first;
  }

  static bool _isPrivateIpv4(String address) {
    if (address.startsWith('10.')) return true;
    if (address.startsWith('192.168.')) return true;
    final match = RegExp(r'^172\.(\d+)\.').firstMatch(address);
    if (match == null) return false;
    final second = int.tryParse(match.group(1) ?? '');
    return second != null && second >= 16 && second <= 31;
  }

  static bool _isLinkLocal(String address) => address.startsWith('169.254.');

  static String _extensionForUpload({
    required String fileName,
    required String? contentType,
  }) {
    final extension = _extensionFromPath(fileName).toLowerCase();
    if (_allowedExtensions.contains(extension)) {
      return extension;
    }

    return switch ((contentType ?? '').toLowerCase().split(';').first.trim()) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/heic' => '.heic',
      'image/heif' => '.heif',
      _ => '.jpg',
    };
  }

  static bool _looksLikeImage({
    required String fileName,
    required String? contentType,
  }) {
    final mimeType = (contentType ?? '').toLowerCase().split(';').first.trim();
    if (mimeType.startsWith('image/')) return true;
    return _allowedExtensions
        .contains(_extensionFromPath(fileName).toLowerCase());
  }

  static String _extensionFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot);
  }

  static String _sanitizeFileName(String value) {
    final trimmed = value.trim().isEmpty ? 'phone_photo' : value.trim();
    return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  }

  static const Set<String> _allowedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };
}
