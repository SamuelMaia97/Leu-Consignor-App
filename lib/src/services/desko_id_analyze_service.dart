import 'dart:io';

const _executableName = 'ID_Analyze.exe';

class DeskoIdAnalyzeService {
  Future<void> ensureReady({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!Platform.isWindows) {
      throw const DeskoIdAnalyzeException(
        'DESKO ID Analyze can only be started on Windows.',
      );
    }

    if (!await _isRunning()) {
      final executable = await _findExecutable();
      if (executable == null) {
        throw const DeskoIdAnalyzeException(
          'DESKO ID Analyze is not installed or could not be found.',
        );
      }

      await Process.start(
        executable.path,
        const [],
        mode: ProcessStartMode.detached,
        workingDirectory: executable.parent.path,
      );
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isReady()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    throw const DeskoIdAnalyzeException(
      'DESKO ID Analyze did not become ready within 30 seconds.',
    );
  }

  Future<bool> _isRunning() async {
    final result = await Process.run(
      'tasklist.exe',
      const ['/FI', 'IMAGENAME eq ID_Analyze.exe', '/NH', '/FO', 'CSV'],
    );
    return result.exitCode == 0 &&
        result.stdout.toString().toLowerCase().contains(
              '"${_executableName.toLowerCase()}"',
            );
  }

  Future<bool> _isReady() async {
    const script = r'''
$process = Get-Process -Name 'ID_Analyze' -ErrorAction SilentlyContinue |
  Select-Object -First 1
if ($null -eq $process) { exit 1 }
try {
  if ($process.MainWindowHandle -ne 0 -or $process.WaitForInputIdle(1000)) {
    exit 0
  }
} catch {}
exit 2
''';

    final result = await Process.run(
      'powershell.exe',
      const [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ],
    );
    return result.exitCode == 0;
  }

  Future<File?> _findExecutable() async {
    final environment = Platform.environment;
    final roots = <String?>[
      environment['ProgramFiles(x86)'],
      environment['ProgramFiles'],
    ];

    for (final root in roots) {
      if (root == null || root.isEmpty) continue;
      final candidate = File(
        '$root${Platform.pathSeparator}DESKO GmbH'
        '${Platform.pathSeparator}ID_Analyze'
        '${Platform.pathSeparator}$_executableName',
      );
      if (await candidate.exists()) {
        return candidate;
      }
    }

    final whereResult = await Process.run('where.exe', const [_executableName]);
    if (whereResult.exitCode != 0) {
      return null;
    }

    for (final line in whereResult.stdout.toString().split(RegExp(r'\r?\n'))) {
      final path = line.trim();
      if (path.isEmpty) continue;
      final candidate = File(path);
      if (await candidate.exists()) {
        return candidate;
      }
    }
    return null;
  }
}

class DeskoIdAnalyzeException implements Exception {
  const DeskoIdAnalyzeException(this.message);

  final String message;

  @override
  String toString() => message;
}
