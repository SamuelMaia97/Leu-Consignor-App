import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:leu_consignor_app/src/services/signature_image_service.dart';

void main() {
  const service = SignatureImageService();

  test('does not create an image without a drawable stroke', () async {
    expect(await service.renderPng([]), isNull);
    expect(
        await service.renderPng([
          [],
          [const ui.Offset(12, 34)]
        ]),
        isNull);
  });

  final cases = <String, List<List<ui.Offset>>>{
    'horizontal line': [
      [const ui.Offset(10, 45), const ui.Offset(300, 45)],
    ],
    'vertical line': [
      [const ui.Offset(45, 10), const ui.Offset(45, 150)],
    ],
    'multi-stroke signature': [
      [
        const ui.Offset(10, 50),
        const ui.Offset(30, 5),
        const ui.Offset(40, 70),
        const ui.Offset(90, 20),
        const ui.Offset(110, 50),
      ],
      [const ui.Offset(15, 80), const ui.Offset(115, 85)],
      // An isolated tap remains ignored, including when computing bounds.
      [const ui.Offset(-10000, -10000)],
    ],
    'dense signature': _denseSignature(),
  };

  for (final entry in cases.entries) {
    testWidgets('preserves every rendered RGBA pixel for ${entry.key}',
        (tester) async {
      await tester.runAsync(() async {
        final originalPng = await _renderOriginalPng(entry.value);
        final compactPng = (await service.renderPng(entry.value))!;
        final original = img.decodePng(originalPng)!;
        final compact = img.decodePng(compactPng)!;

        expect(compact.width, 900);
        expect(compact.height, 300);
        expect(
          compact
              .convert(numChannels: 4)
              .getBytes(order: img.ChannelOrder.rgba),
          orderedEquals(original.getBytes(order: img.ChannelOrder.rgba)),
        );
        expect(compact.getPixel(0, 0).a, 0);
        expect(compact.any((pixel) => pixel.a > 0 && pixel.a < 255), isTrue);
        expect(compact.any((pixel) => pixel.a == 255), isTrue);

        if (entry.key == 'dense signature') {
          // Dense ink increases the signed PDF request payload.
          // Keep the fix accountable to a material payload reduction.
          expect(compactPng.length, lessThan(originalPng.length * 0.75));
        }
      });
    });
  }
}

List<List<ui.Offset>> _denseSignature() => [
      for (var stroke = 0; stroke < 24; stroke++)
        [
          for (var point = 0; point < 260; point++)
            ui.Offset(
              point * 2.0,
              75 +
                  stroke * 3 +
                  35 * math.sin(point * 0.19 + stroke * 0.8) +
                  20 * math.cos(point * 0.37 + stroke),
            ),
        ],
    ];

// The previous wizard renderer is retained here as a regression reference for
// geometry and Flutter's native PNG output, independently of the new encoder.
Future<Uint8List> _renderOriginalPng(List<List<ui.Offset>> strokes) async {
  const outputWidth = 900.0;
  const outputHeight = 300.0;
  final points = strokes.where((stroke) => stroke.length >= 2).expand((s) => s);
  final left = points.map((point) => point.dx).reduce(math.min);
  final top = points.map((point) => point.dy).reduce(math.min);
  final right = points.map((point) => point.dx).reduce(math.max);
  final bottom = points.map((point) => point.dy).reduce(math.max);
  final signatureBounds = ui.Rect.fromLTWH(
    left,
    top,
    math.max(right - left, 1.0),
    math.max(bottom - top, 1.0),
  );

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
  final image =
      await picture.toImage(outputWidth.toInt(), outputHeight.toInt());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    picture.dispose();
    image.dispose();
  }
}
