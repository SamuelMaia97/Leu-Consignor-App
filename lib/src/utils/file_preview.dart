import 'package:flutter/material.dart';

class FilePreviewDescriptor {
  const FilePreviewDescriptor({
    required this.kind,
    required this.icon,
    required this.label,
  });

  final FilePreviewKind kind;
  final IconData icon;
  final String label;

  bool get isImage => kind == FilePreviewKind.image;
}

enum FilePreviewKind {
  image,
  pdf,
  word,
  generic,
}

class FilePreview {
  static FilePreviewDescriptor fromPath(String path) {
    final lowerPath = path.toLowerCase();

    if (_imagePattern.hasMatch(lowerPath)) {
      return const FilePreviewDescriptor(
        kind: FilePreviewKind.image,
        icon: Icons.image_outlined,
        label: 'Image preview',
      );
    }

    if (lowerPath.endsWith('.pdf')) {
      return const FilePreviewDescriptor(
        kind: FilePreviewKind.pdf,
        icon: Icons.picture_as_pdf_outlined,
        label: 'PDF preview',
      );
    }

    if (_wordPattern.hasMatch(lowerPath)) {
      return const FilePreviewDescriptor(
        kind: FilePreviewKind.word,
        icon: Icons.description_outlined,
        label: 'Word preview',
      );
    }

    return const FilePreviewDescriptor(
      kind: FilePreviewKind.generic,
      icon: Icons.insert_drive_file_outlined,
      label: 'File preview',
    );
  }

  static final RegExp _imagePattern = RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp)$');
  static final RegExp _wordPattern = RegExp(r'\.(doc|docx|rtf)$');
}
