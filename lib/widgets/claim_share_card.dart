import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

// ── Public entry point ───────────────────────────────────────────────────────

/// Renders a claim card offscreen, saves it to [Directory.systemTemp], and
/// shares it via share_plus v9 [Share.shareXFiles].
Future<void> shareClaimCard({
  required List<LatLng> polygon,
  required String zoneName,
  required String ownerName,
  required BuildContext context,
}) async {
  // Pre-warm fonts so the offscreen PNG uses the correct typefaces.
  await GoogleFonts.pendingFonts([
    GoogleFonts.bebasNeue(),
    GoogleFonts.spaceGrotesk(),
  ]);

  final key = GlobalKey();
  OverlayEntry? entry;

  try {
    // Insert the card into the Overlay at position (-10000, -10000) so it is
    // laid out by the framework but never visible to the user.
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: -10000,
        child: RepaintBoundary(
          key: key,
          child: _ClaimCardWidget(
            polygon: polygon,
            zoneName: zoneName,
            ownerName: ownerName,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(entry);

    // Wait for the framework to lay out and paint the widget.
    await WidgetsBinding.instance.endOfFrame;

    // Capture to PNG.
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) return;

    // Write to a temporary file (no path_provider needed — dart:io only).
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/runwar_claim.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());

    // Share via share_plus v9 API.
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'I claimed $zoneName on RunWar 🔥',
    );
  } finally {
    entry?.remove();
  }
}

// ── Offscreen widget ─────────────────────────────────────────────────────────

class _ClaimCardWidget extends StatelessWidget {
  const _ClaimCardWidget({
    required this.polygon,
    required this.zoneName,
    required this.ownerName,
  });

  final List<LatLng> polygon;
  final String zoneName;
  final String ownerName;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final claimedLabel =
        'CLAIMED ${now.day} ${_monthName(now.month)} ${now.year}';

    return SizedBox(
      width: 800,
      height: 800,
      child: ColoredBox(
        color: kBg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Polygon canvas ──
            SizedBox(
              width: 400,
              height: 400,
              child: CustomPaint(
                painter: _PolygonPainter(polygon: polygon),
              ),
            ),

            const SizedBox(height: 24),

            // ── Zone name ──
            Text(
              zoneName.toUpperCase(),
              style: GoogleFonts.bebasNeue(
                fontSize: 48,
                color: kFg,
                letterSpacing: 2.0,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // ── Owner name ──
            Text(
              ownerName.toUpperCase(),
              style: GoogleFonts.bebasNeue(
                fontSize: 32,
                color: kAccent,
                letterSpacing: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // ── Claimed date ──
            Text(
              claimedLabel,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                color: const Color(0x99FFFFFF), // kFgMuted
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // ── RUNWAR wordmark ──
            Text(
              'RUNWAR',
              style: GoogleFonts.bebasNeue(
                fontSize: 24,
                color: kAccent,
                letterSpacing: 4.0,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _monthName(int month) {
    const names = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return names[month - 1];
  }
}

// ── Polygon painter ──────────────────────────────────────────────────────────

class _PolygonPainter extends CustomPainter {
  const _PolygonPainter({required this.polygon});

  final List<LatLng> polygon;

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 20.0;
    final drawArea = size.width - margin * 2; // same for both axes (square)

    final paint = Paint()
      ..color = kAccent.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final path = ui.Path();

    if (polygon.length < 3) {
      // Fallback: filled square centred in the draw area.
      final squareSize = drawArea * 0.6;
      final left = margin + (drawArea - squareSize) / 2;
      final top = margin + (drawArea - squareSize) / 2;
      path.addRect(Rect.fromLTWH(left, top, squareSize, squareSize));
    } else {
      // Compute bounding box over LatLng values.
      double minLat = polygon[0].latitude;
      double maxLat = polygon[0].latitude;
      double minLng = polygon[0].longitude;
      double maxLng = polygon[0].longitude;

      for (final p in polygon) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }

      final latRange = maxLat - minLat;
      final lngRange = maxLng - minLng;

      // Avoid division-by-zero for degenerate polygons.
      final scaleX =
          lngRange > 0 ? drawArea / lngRange : drawArea;
      final scaleY =
          latRange > 0 ? drawArea / latRange : drawArea;

      // Keep aspect ratio by using the smaller scale factor.
      final scale = scaleX < scaleY ? scaleX : scaleY;

      final projWidth = lngRange > 0 ? lngRange * scale : drawArea;
      final projHeight = latRange > 0 ? latRange * scale : drawArea;

      // Centre the projected polygon inside the draw area.
      final offsetX = margin + (drawArea - projWidth) / 2;
      final offsetY = margin + (drawArea - projHeight) / 2;

      bool first = true;
      for (final p in polygon) {
        // Longitude → X (left to right)
        final x = offsetX + (p.longitude - minLng) * scale;
        // Latitude  → Y (north = up → flip)
        final y = offsetY + (maxLat - p.latitude) * scale;

        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
    }

    canvas.drawPath(path, paint);

    // Subtle stroke on top.
    final strokePaint = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_PolygonPainter old) => old.polygon != polygon;
}
