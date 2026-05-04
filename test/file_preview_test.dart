import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/utils/file_preview.dart';

void main() {
  group('FilePreview', () {
    test('classifies image files', () {
      final preview = FilePreview.fromPath('/tmp/image.JPG');
      expect(preview.isImage, isTrue);
      expect(preview.icon, Icons.image_outlined);
    });

    test('classifies pdf and word files distinctly', () {
      final pdf = FilePreview.fromPath('/tmp/contract.pdf');
      final docx = FilePreview.fromPath('/tmp/contract.docx');

      expect(pdf.kind, FilePreviewKind.pdf);
      expect(pdf.icon, Icons.picture_as_pdf_outlined);
      expect(docx.kind, FilePreviewKind.word);
      expect(docx.icon, Icons.description_outlined);
    });
  });
}
