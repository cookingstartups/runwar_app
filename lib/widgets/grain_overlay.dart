import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class GrainOverlay extends StatefulWidget {
  const GrainOverlay({super.key});

  @override
  State<GrainOverlay> createState() => _GrainOverlayState();
}

class _GrainOverlayState extends State<GrainOverlay> {
  ui.Image? _noise;

  @override
  void initState() {
    super.initState();
    _generateNoise();
  }

  Future<void> _generateNoise() async {
    const size = 256;
    final rng = Random();
    final pixels = List<int>.generate(size * size * 4, (i) {
      if (i % 4 == 3) return 255;
      final v = rng.nextInt(256);
      return v;
    });
    final bytes = Uint8List.fromList(pixels);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, size, size, ui.PixelFormat.rgba8888,
        (img) => completer.complete(img));
    final img = await completer.future;
    if (mounted) setState(() => _noise = img);
  }

  @override
  Widget build(BuildContext context) {
    if (_noise == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: _GrainPainter(_noise!)),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final ui.Image noise;
  _GrainPainter(this.noise);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..blendMode = BlendMode.overlay
      ..color = Colors.white.withValues(alpha: 0.035);
    // Tile the 256×256 noise across the full viewport
    for (double x = 0; x < size.width; x += 256) {
      for (double y = 0; y < size.height; y += 256) {
        canvas.drawImage(noise, Offset(x, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.noise != noise;
}
