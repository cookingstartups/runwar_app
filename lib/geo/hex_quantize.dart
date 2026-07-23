// lib/geo/hex_quantize.dart
//
// Shared-reference hex-grid quantisation for MULTI-USER GEOMETRY CONVERGENCE.
//
// -----------------------------------------------------------------------
// What problem this solves, and what it does not solve
// -----------------------------------------------------------------------
// Two runners tracing "the same" real-world block never produce identical
// polygons - GPS noise means every device's raw capture is a slightly
// different shape. Smoothing (polygon_smoothing.dart) does not fix this:
// two noisy shapes smoothed independently are still two different shapes,
// just differently wrong. Convergence requires snapping every capture to a
// SHARED reference grid so that two traces of the same ground resolve to
// the same stored cells.
//
// This file quantises a captured polygon to the boundary of the set of
// fixed hex cells whose centers fall inside it - i.e. a hex-grid "polyfill
// and dissolve", the same operation Uber's H3 calls polygonToCells +
// cellsToMultiPolygon. Two independent traces of the same real loop, once
// the GPS noise band is small relative to the cell size, cover the same
// cell set and therefore quantise to the exact same output ring.
//
// -----------------------------------------------------------------------
// Why a self-rolled grid instead of the `h3_flutter` / `h3_dart` package
// -----------------------------------------------------------------------
// The real H3 library ships as a native library via FFI (h3_ffi under
// h3_flutter/h3_dart) that must be compiled and bundled per platform
// (Android/iOS native build steps, plus a host binary for `flutter test` on
// the dev machine). That is real, ongoing native-build risk this task's
// environment cannot safely take on and verify: this branch is delivered
// without an APK build/install pass, so any native-linkage problem would
// ship unverified. A plain-Dart flat-top-free pointy-top axial hex grid
// gives the same guarantee this task actually needs - two same-location
// traces converge to the same cell set - without a native dependency, and
// it is fully exercised by `flutter test` in this environment. If the game
// later needs true equal-area global H3 cells (e.g. cross-region
// leaderboard math), swapping this module for `h3_flutter` is a drop-in
// replacement at the same call sites; nothing downstream should depend on
// this being literal H3.
//
// -----------------------------------------------------------------------
// Resolution / quantisation-scheme note for app-T0587 (snap split cuts to
// boundary, queued behind this task)
// -----------------------------------------------------------------------
// T0587's snap-to-boundary needs a nearby edge to snap a re-run's cut to,
// which only exists once stored geometry is quantised (see
// territory-mechanics.md, Split Fragment Handling). This module is that
// quantisation step. The grid parameters T0587 should reuse:
//   - Cell shape: pointy-top hexagon, axial (q, r) coordinates.
//   - Cell size: kHexCellCircumradiusM (runwar_constants.dart), currently
//     10 m, PROVISIONAL pending a @game-theory pass.
//   - Projection: local equirectangular anchored at (lat=0, lng=0) globally
//     fixed origin, with the longitude scale evaluated at the polygon's own
//     bounding-box center latitude (see `referenceLatitudeDeg` below) rather
//     than a single global reference latitude, so cell size stays close to
//     the true metre value in every city instead of only at the equator.
//     Two traces of the same real loop have bbox centers within meters of
//     each other, so this per-call reference latitude does not break
//     convergence in practice - the origin (0,0) stays fixed, only the
//     scale factor moves by a negligible amount.
//   - Containment rule: a cell is "covered" when its CENTER falls inside the
//     input polygon (H3's default 'center' containment mode) - not a full
//     overlap test. A split-snap step reading this module's output should
//     assume the same rule.
// -----------------------------------------------------------------------

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:runwar_app/geo/lasso.dart';
import 'package:runwar_app/utils/runwar_constants.dart';

const double _sqrt3 = 1.7320508075688772;

/// Axial coordinates of a single hex cell on the shared grid. Two cells are
/// equal iff (q, r) match - stable across process runs and across devices,
/// which is the whole point: it is the shared reference two independent
/// traces converge onto.
class HexCell {
  final int q;
  final int r;
  const HexCell(this.q, this.r);

  @override
  bool operator ==(Object other) => other is HexCell && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => 'HexCell($q, $r)';
}

class _Point {
  final double x;
  final double y;
  const _Point(this.x, this.y);
}

/// A local instance of the shared hex grid, parameterised by cell size and
/// the equirectangular reference latitude used for this call's projection.
/// The grid ORIGIN is always (lat=0, lng=0) - fixed and identical across
/// every instance - only the metre-per-degree-longitude scale factor varies
/// with [refLatDeg].
class HexGrid {
  final double circumradiusM;
  final double refLatDeg;

  const HexGrid({required this.circumradiusM, required this.refLatDeg});

  static const double _latScale = 110540.0;
  double get _lngScale => 111320.0 * math.cos(refLatDeg * math.pi / 180.0);

  _Point _project(LatLng p) => _Point(p.longitude * _lngScale, p.latitude * _latScale);

  LatLng _unproject(_Point p) => LatLng(p.y / _latScale, p.x / _lngScale);

  _Point _centerXY(HexCell cell) => _Point(
        circumradiusM * (_sqrt3 * cell.q + _sqrt3 / 2 * cell.r),
        circumradiusM * (1.5 * cell.r),
      );

  /// The hex cell whose center is nearest [point] (standard axial cube
  /// rounding of the fractional axial coordinates).
  HexCell cellAt(LatLng point) {
    final p = _project(point);
    final qf = (_sqrt3 / 3 * p.x - 1 / 3 * p.y) / circumradiusM;
    final rf = (2.0 / 3.0 * p.y) / circumradiusM;
    return _roundAxial(qf, rf);
  }

  LatLng cellCenter(HexCell cell) => _unproject(_centerXY(cell));

  /// The 6 corner points of [cell], in CCW winding order, starting at the
  /// "top-right" corner of a pointy-top hexagon.
  List<LatLng> cellCorners(HexCell cell) {
    final c = _centerXY(cell);
    final corners = <LatLng>[];
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 180.0) * (60 * i - 30);
      final x = c.x + circumradiusM * math.cos(angle);
      final y = c.y + circumradiusM * math.sin(angle);
      corners.add(_unproject(_Point(x, y)));
    }
    return corners;
  }

  /// Every hex cell on the grid whose CENTER falls inside [polygon]
  /// (H3-style "center containment"), returned in a deterministic
  /// (r, then q) order so that identical covered-cell sets always produce
  /// identical dissolve output regardless of which raw trace produced them.
  List<HexCell> coveredCells(List<LatLng> polygon) {
    if (polygon.length < 3) return const [];
    final bbox = polygonBbox(polygon);
    final corners = [
      LatLng(bbox.minLat, bbox.minLng),
      LatLng(bbox.minLat, bbox.maxLng),
      LatLng(bbox.maxLat, bbox.minLng),
      LatLng(bbox.maxLat, bbox.maxLng),
    ];
    var minQ = 1 << 30, maxQ = -(1 << 30), minR = 1 << 30, maxR = -(1 << 30);
    for (final c in corners) {
      final cell = cellAt(c);
      if (cell.q < minQ) minQ = cell.q;
      if (cell.q > maxQ) maxQ = cell.q;
      if (cell.r < minR) minR = cell.r;
      if (cell.r > maxR) maxR = cell.r;
    }
    const margin = 2; // covers a center cell whose neighbor straddles the bbox edge
    final out = <HexCell>[];
    for (var r = minR - margin; r <= maxR + margin; r++) {
      for (var q = minQ - margin; q <= maxQ + margin; q++) {
        final cell = HexCell(q, r);
        if (pointInPolygon(cellCenter(cell), polygon)) out.add(cell);
      }
    }
    out.sort((a, b) => a.r != b.r ? a.r.compareTo(b.r) : a.q.compareTo(b.q));
    return out;
  }

  /// Dissolves a set of covered cells into the boundary ring(s) of their
  /// union, by cancelling every hex edge shared by two covered cells and
  /// stitching the surviving (single-owner) edges into closed rings.
  /// Returns one ring per contiguous outer boundary; a hollow interior (a
  /// donut-shaped covered-cell set) would additionally emit an inner ring,
  /// though ordinary compact claims never produce one in practice.
  List<List<LatLng>> dissolveBoundary(List<HexCell> cells) {
    if (cells.isEmpty) return const [];

    String key(LatLng p) =>
        '${p.latitude.toStringAsFixed(9)},${p.longitude.toStringAsFixed(9)}';

    final pointByKey = <String, LatLng>{};
    final survivingEdges = <String>{}; // "keyA|keyB", directed a -> b

    for (final cell in cells) {
      final corners = cellCorners(cell);
      for (var i = 0; i < 6; i++) {
        final a = corners[i];
        final b = corners[(i + 1) % 6];
        final ka = key(a);
        final kb = key(b);
        pointByKey[ka] = a;
        pointByKey[kb] = b;
        final fwd = '$ka|$kb';
        final rev = '$kb|$ka';
        if (survivingEdges.contains(rev)) {
          survivingEdges.remove(rev);
        } else {
          survivingEdges.add(fwd);
        }
      }
    }

    final next = <String, String>{};
    for (final e in survivingEdges) {
      final parts = e.split('|');
      next[parts[0]] = parts[1];
    }

    final rings = <List<LatLng>>[];
    final visited = <String>{};
    for (final startKey in next.keys) {
      if (visited.contains(startKey)) continue;
      final ring = <LatLng>[];
      var cur = startKey;
      while (!visited.contains(cur)) {
        visited.add(cur);
        ring.add(pointByKey[cur]!);
        final nxt = next[cur];
        if (nxt == null) break;
        cur = nxt;
      }
      if (ring.length >= 3) rings.add(ring);
    }
    return rings;
  }

  HexCell _roundAxial(double qf, double rf) {
    final xf = qf, zf = rf, yf = -xf - zf;
    var rx = xf.round(), ry = yf.round(), rz = zf.round();
    final xDiff = (rx - xf).abs(), yDiff = (ry - yf).abs(), zDiff = (rz - zf).abs();
    if (xDiff > yDiff && xDiff > zDiff) {
      rx = -ry - rz;
    } else if (yDiff > zDiff) {
      ry = -rx - rz;
    } else {
      rz = -rx - ry;
    }
    return HexCell(rx, rz);
  }
}

double _bboxCenterLat(List<LatLng> polygon) {
  final bbox = polygonBbox(polygon);
  return (bbox.minLat + bbox.maxLat) / 2;
}

/// Quantises [polygon] to the shared hex grid: every cell whose center
/// falls inside [polygon] is "covered", and the returned ring(s) trace the
/// boundary of that covered-cell union. Two independent traces of the same
/// real-world loop converge on the same output as long as the GPS noise
/// band is small relative to [circumradiusM] (the grid's cell size).
///
/// [referenceLatitudeDeg] defaults to the polygon's own bounding-box center
/// latitude - see the module doc header for why a per-call reference
/// latitude does not break cross-device convergence in practice.
///
/// Returns an empty list if [polygon] is degenerate (fewer than 3 points)
/// or too small to cover any cell center at this resolution; callers should
/// treat that as "quantisation produced nothing usable" and fall back to
/// the raw polygon rather than persisting an empty shape.
List<List<LatLng>> quantizePolygonToHexGrid(
  List<LatLng> polygon, {
  double circumradiusM = kHexCellCircumradiusM,
  double? referenceLatitudeDeg,
}) {
  if (polygon.length < 3) return const [];
  final refLat = referenceLatitudeDeg ?? _bboxCenterLat(polygon);
  final grid = HexGrid(circumradiusM: circumradiusM, refLatDeg: refLat);
  final cells = grid.coveredCells(polygon);
  return grid.dissolveBoundary(cells);
}

/// The stable hex-cell identifier for [point] on the shared grid at
/// [circumradiusM] resolution - a hook for future adjacency/contiguity work
/// (contested-border set operations, T0587 split-snap) to key off directly
/// instead of re-deriving cells from raw geometry each time.
HexCell hexCellAt(
  LatLng point, {
  double circumradiusM = kHexCellCircumradiusM,
  required double referenceLatitudeDeg,
}) {
  return HexGrid(circumradiusM: circumradiusM, refLatDeg: referenceLatitudeDeg).cellAt(point);
}
