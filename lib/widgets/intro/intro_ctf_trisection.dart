// lib/widgets/intro/intro_ctf_trisection.dart
//
// CTF trisection + base-spawn draw routines shared by IntroFlagDropMap
// (onboarding slide 7). Screen-space decorative overlay - not derived from
// the routes' real GPS bearings (operator decision: stylized abbreviation
// of the carry-and-return mechanic, not a literal chain-steal simulation).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme.dart';
import 'intro_helpers.dart';

/// Angular sweep of each of the 3 faction sectors (120 degrees, radians).
const double kCtfSectorSweep = 2 * math.pi / 3;

/// One faction's pie-sector wedge and the bearing its base marker spawns on.
class CtfFaction {
  final Color color;

  /// Canvas-angle convention: 0 = east, increasing clockwise (screen Y grows
  /// downward), matching Canvas.drawArc's own startAngle parameter.
  final double sectorStartAngle;

  const CtfFaction({required this.color, required this.sectorStartAngle});

  double get sectorCenterAngle => sectorStartAngle + kCtfSectorSweep / 2;

  /// Unit direction from the drop point toward this faction's own base.
  Offset get baseDirection =>
      Offset(math.cos(sectorCenterAngle), math.sin(sectorCenterAngle));
}

// Blue faces north (up), pink faces southeast, lime faces southwest - three
// seamless 120-degree wedges summing to a full circle around the drop point.
const ctfFactionBlue =
    CtfFaction(color: kSea, sectorStartAngle: -5 * math.pi / 6);
const ctfFactionPink =
    CtfFaction(color: kRunnerCPink, sectorStartAngle: -math.pi / 6);
const ctfFactionLime =
    CtfFaction(color: kLimeGreen, sectorStartAngle: math.pi / 2);

const List<CtfFaction> ctfFactions = [
  ctfFactionBlue,
  ctfFactionPink,
  ctfFactionLime,
];

/// Draws the 3-faction trisection wedge overlay centered on [center].
/// [revealScale] is 0..1 (radius sweep-in during the reveal beat), [opacity]
/// is the ambient global-fade multiplier applied on every frame.
void drawCtfTrisection(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required double revealScale,
  required double opacity,
}) {
  if (opacity <= 0 || revealScale <= 0) return;
  final r = radius * revealScale.clamp(0.0, 1.0);
  if (r <= 0) return;
  final rect = Rect.fromCircle(center: center, radius: r);
  for (final faction in ctfFactions) {
    canvas.drawArc(
      rect,
      faction.sectorStartAngle,
      kCtfSectorSweep,
      true,
      Paint()
        ..style = PaintingStyle.fill
        ..color = faction.color.withValues(alpha: opacity * 0.11),
    );
    canvas.drawArc(
      rect,
      faction.sectorStartAngle,
      kCtfSectorSweep,
      true,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = faction.color.withValues(alpha: opacity * 0.30),
    );
  }
}

/// Draws one base glyph at [pos]. [revealed] = true renders the carrier's
/// own base (solid diamond + ring in [color]); false renders an unlabeled
/// "?" marker in a muted neutral tone - rivals never see each other's base
/// (base-secrecy rule), so from this single-viewer slide the two non-carrier
/// bases always render hidden.
void drawCtfBaseMarker(
  Canvas canvas,
  Offset pos,
  Color color,
  double scale, {
  required bool revealed,
}) {
  final s = scale.clamp(0.0, 1.0);
  if (s <= 0) return;
  if (revealed) {
    canvas.drawCircle(
        pos,
        9 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.9 * s));
    final path = Path()
      ..moveTo(pos.dx, pos.dy - 7 * s)
      ..lineTo(pos.dx + 7 * s, pos.dy)
      ..lineTo(pos.dx, pos.dy + 7 * s)
      ..lineTo(pos.dx - 7 * s, pos.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.35 * s));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.9 * s));
  } else {
    canvas.drawCircle(
        pos,
        8 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = kFgMuted.withValues(alpha: 0.55 * s));
    final tp = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: kFgMuted.withValues(alpha: 0.85 * s),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }
}
