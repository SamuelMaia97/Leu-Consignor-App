import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Renders captured signatures without discarding strokes or alpha detail.
class SignatureImageService {
  const SignatureImageService();

  Future<Uint8List?> renderPng(List<List<ui.Offset>> strokes) async {
    const outputWidth = 900;
    const outputHeight = 300;
    final signatureBounds = _signatureBounds(strokes);
    if (signatureBounds == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..color = const ui.Color(0xff000000)
      ..strokeWidth = 4.5
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = ui.PaintingStyle.stroke;

    const padding = 24.0;
    final scale = math.min(
      (outputWidth - padding * 2) / signatureBounds.width,
      (outputHeight - padding * 2) / signatureBounds.height,
    );
    final offset = ui.Offset(
      (outputWidth - signatureBounds.width * scale) / 2 -
          signatureBounds.left * scale,
      (outputHeight - signatureBounds.height * scale) / 2 -
          signatureBounds.top * scale,
    );

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = ui.Path()
        ..moveTo(
          stroke.first.dx * scale + offset.dx,
          stroke.first.dy * scale + offset.dy,
        );
      for (final point in stroke.skip(1)) {
        path.lineTo(
          point.dx * scale + offset.dx,
          point.dy * scale + offset.dy,
        );
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(outputWidth, outputHeight);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;
      final rgba = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      // Every pixel is black with one of 256 alpha values. Using alpha as a
      // palette index retains every antialiased edge exactly, while storing
      // one byte per pixel instead of four before lossless PNG compression.
      final palette = img.PaletteUint8(256, 4);
      for (var alpha = 0; alpha < 256; alpha++) {
        palette.setRgba(alpha, 0, 0, 0, alpha);
      }
      final indices = Uint8List(outputWidth * outputHeight);
      for (var pixel = 0; pixel < indices.length; pixel++) {
        indices[pixel] = rgba[pixel * 4 + 3];
      }
      final indexedImage = img.Image.fromBytes(
        width: outputWidth,
        height: outputHeight,
        bytes: indices.buffer,
        numChannels: 1,
        palette: palette,
      );
      return img.encodePng(indexedImage, level: 9);
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  ui.Rect? _signatureBounds(List<List<ui.Offset>> strokes) {
    double? left;
    double? top;
    double? right;
    double? bottom;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      for (final point in stroke) {
        left = left == null ? point.dx : math.min(left, point.dx);
        top = top == null ? point.dy : math.min(top, point.dy);
        right = right == null ? point.dx : math.max(right, point.dx);
        bottom = bottom == null ? point.dy : math.max(bottom, point.dy);
      }
    }

    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    return ui.Rect.fromLTWH(
      left,
      top,
      math.max(right - left, 1.0),
      math.max(bottom - top, 1.0),
    );
  }
}
