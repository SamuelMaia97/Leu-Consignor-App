import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';

import '../models/contract_record.dart';
import '../screens/camera_capture_screen.dart';
import '../storage/local_store.dart';

class FileService {
  final ImagePicker _picker = ImagePicker();

  Future<List<String>> pickFiles({
    bool imagesOnly = false,
    bool allowMultiple = true,
  }) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      type: imagesOnly ? FileType.image : FileType.any,
    );

    return result?.paths.whereType<String>().toList(growable: false) ??
        const [];
  }

  Future<List<String>> importFilesForUpload(
    List<String> sourcePaths,
    UploadType type,
  ) async {
    if (sourcePaths.isEmpty) {
      return const [];
    }

    final targetDirectory = await _directoryForUploadType(type);
    final importedPaths = <String>[];

    for (final sourcePath in sourcePaths) {
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        continue;
      }

      final copiedPath = await _copyFileToDirectory(
        sourceFile: sourceFile,
        targetDirectory: targetDirectory,
        preferredFileName: _fileNameFromPath(sourcePath),
      );

      importedPaths.add(copiedPath);
    }

    return importedPaths;
  }

  Future<String?> captureImage({
    required BuildContext context,
    required UploadType type,
    required String filePrefix,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 95,
        maxWidth: 4096,
        maxHeight: 4096,
      );

      if (picked == null) {
        return null;
      }

      return _copyCapturedFile(
        sourcePath: picked.path,
        fallbackName: picked.name,
        filePrefix: filePrefix,
        type: type,
      );
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final capturedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => CameraCaptureScreen(filePrefix: filePrefix),
          fullscreenDialog: true,
        ),
      );

      if (capturedPath == null || capturedPath.trim().isEmpty) {
        return null;
      }

      return _copyCapturedFile(
        sourcePath: capturedPath,
        fallbackName: _fileNameFromPath(capturedPath),
        filePrefix: filePrefix,
        type: type,
      );
    }

    final paths = await pickFiles(imagesOnly: true, allowMultiple: false);
    if (paths.isEmpty) {
      return null;
    }

    final imported = await importFilesForUpload(paths, type);
    return imported.isEmpty ? null : imported.first;
  }

  Future<void> open(String path) async {
    if (path.trim().isEmpty) {
      return;
    }

    await OpenFilex.open(path);
  }

  Future<String> getSuggestedPdfPath(String fileName) async {
    final directory = await contractsDirectory();

    return _uniqueTargetPath(
      targetDirectory: directory,
      originalFileName: fileName,
    );
  }

  Future<String> _copyCapturedFile({
    required String sourcePath,
    required String fallbackName,
    required String filePrefix,
    required UploadType type,
  }) async {
    final sourceFile = File(sourcePath);
    final targetDirectory = await _directoryForUploadType(type);

    final fallbackExtension = _extensionFromPath(fallbackName);
    final sourceExtension = _extensionFromPath(sourcePath);
    final extension = fallbackExtension.isNotEmpty
        ? fallbackExtension
        : sourceExtension.isNotEmpty
            ? sourceExtension
            : '.jpg';

    final preferredFileName =
        '${_sanitizeFileName(filePrefix)}_${DateTime.now().millisecondsSinceEpoch}$extension';

    return _copyFileToDirectory(
      sourceFile: sourceFile,
      targetDirectory: targetDirectory,
      preferredFileName: preferredFileName,
    );
  }

  Future<String> _copyFileToDirectory({
    required File sourceFile,
    required Directory targetDirectory,
    required String preferredFileName,
  }) async {
    await targetDirectory.create(recursive: true);

    if (_isInsideDirectory(sourceFile.path, targetDirectory.path)) {
      return sourceFile.path;
    }

    final targetPath = await _uniqueTargetPath(
      targetDirectory: targetDirectory,
      originalFileName: preferredFileName,
    );

    final copiedFile = await sourceFile.copy(targetPath);
    return copiedFile.path;
  }

  Future<Directory> _directoryForUploadType(UploadType type) {
    switch (type) {
      case UploadType.passport:
        return idPicturesDirectory();

      case UploadType.product:
        return productPicturesDirectory();

      case UploadType.agreement:
        return contractsDirectory();
    }
  }

  static Future<Directory> consignorAppDirectory() {
    return LocalStore.appDirectory();
  }

  static Future<Directory> contractsDirectory() {
    return LocalStore.contractsDirectory();
  }

  static Future<Directory> idPicturesDirectory() {
    return LocalStore.idPicturesDirectory();
  }

  static Future<Directory> productPicturesDirectory() {
    return LocalStore.productPicturesDirectory();
  }

  Future<String> _uniqueTargetPath({
    required Directory targetDirectory,
    required String originalFileName,
  }) async {
    final safeName = _sanitizeFileName(originalFileName);
    final extension = _extensionFromPath(safeName);
    final baseName = extension.isEmpty
        ? safeName
        : safeName.substring(0, safeName.length - extension.length);

    var candidate = '${targetDirectory.path}${Platform.pathSeparator}$safeName';
    var counter = 1;

    while (await File(candidate).exists()) {
      candidate =
          '${targetDirectory.path}${Platform.pathSeparator}${baseName}_$counter$extension';
      counter++;
    }

    return candidate;
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? 'file' : parts.last;
  }

  String _extensionFromPath(String path) {
    final fileName = _fileNameFromPath(path);
    final index = fileName.lastIndexOf('.');

    if (index <= 0 || index == fileName.length - 1) {
      return '';
    }

    return fileName.substring(index);
  }

  String _sanitizeFileName(String fileName) {
    final trimmed = fileName.trim().isEmpty ? 'file' : fileName.trim();

    return trimmed.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
  }

  bool _isInsideDirectory(String filePath, String directoryPath) {
    final normalizedFile = _normalizePath(filePath);
    final normalizedDirectory = _normalizePath(directoryPath);

    return normalizedFile == normalizedDirectory ||
        normalizedFile.startsWith(
          '$normalizedDirectory${Platform.pathSeparator}',
        );
  }

  String _normalizePath(String value) {
    final normalized = value
        .replaceAll('\\', Platform.pathSeparator)
        .replaceAll('/', Platform.pathSeparator);

    if (Platform.isWindows) {
      return normalized.toLowerCase();
    }

    return normalized;
  }
}
