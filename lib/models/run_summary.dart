import 'package:latlong2/latlong.dart';

/// Outcome of a single zone-claim attempt during a run session.
enum ClaimLineOutcome { claimed, conquered, disputed, failed }

/// One zone outcome accumulated during a recording session. Retained on
/// [RunSummary] purely to back the aggregate hero/reward figures and the
/// share target - never rendered as a per-zone breakdown list.
class ClaimLineItem {
  const ClaimLineItem({
    required this.label,
    required this.areaM2,
    required this.outcome,
    required this.polygon,
  });

  /// Ordinal display label ("Zone 1", "Zone 2", ...) - zones have no
  /// human-readable name anywhere in the schema.
  final String label;

  /// Server-authoritative area for this zone.
  final double areaM2;

  final ClaimLineOutcome outcome;

  /// The polygon this claim was dispatched with - kept so the share CTA can
  /// reuse it without a new union-polygon computation.
  final List<LatLng> polygon;

  /// Whether this claim counts toward the hero total, zone count, and
  /// reward line. Disputed and failed outcomes are excluded.
  bool get countsTowardHero =>
      outcome == ClaimLineOutcome.claimed || outcome == ClaimLineOutcome.conquered;
}

/// In-memory snapshot of one completed run session, built at the moment
/// stopRun() resolves. Never reads back from the database - built entirely
/// from session state already held by the recorder.
class RunSummary {
  const RunSummary({
    required this.distanceM,
    required this.duration,
    required this.claims,
    this.altitudeSamples = const <double>[],
  });

  final double distanceM;
  final Duration duration;

  /// Full per-zone outcome list for this session. Retained internally to
  /// compute the aggregate figures below - never rendered as a list.
  final List<ClaimLineItem> claims;

  /// Chronological per-fix altitude readings for this session's track, used
  /// only by the decorative elevation background. Empty when no altitude
  /// data exists for this run (pre-capture run, or a crash-recovered
  /// session) - the background then simply renders nothing, never a
  /// fabricated line.
  final List<double> altitudeSamples;

  /// Derived from distance and duration - never sourced from a live speed
  /// reading. Null when no distance was covered this session.
  Duration? get avgPacePerKm {
    if (distanceM <= 0) return null;
    final distanceKm = distanceM / 1000;
    return Duration(seconds: (duration.inSeconds / distanceKm).round());
  }

  Iterable<ClaimLineItem> get _heroClaims =>
      claims.where((c) => c.countsTowardHero);

  /// Total area across only claimed/conquered zones this session - disputed
  /// (and failed) zones are excluded entirely.
  double get totalAreaM2 =>
      _heroClaims.fold(0.0, (sum, c) => sum + c.areaM2);

  /// Aggregate zone count for the hero line ("N zones claimed").
  int get claimedZoneCount => _heroClaims.length;

  /// Which zone the single Share CTA acts on for a multi-claim session: the
  /// most recently claimed/conquered zone, not simply the last claim
  /// overall. Null when zero claimed/conquered zones exist this session.
  ClaimLineItem? get mostRecentShareableClaim {
    for (final claim in claims.reversed) {
      if (claim.countsTowardHero) return claim;
    }
    return null;
  }

  /// Passive-income-style reward figure for the reward line, expressed in
  /// credits per hour. Computed directly from the claimed/conquered area in
  /// square kilometers (influence level 1, one hour, multiplier 1) with no
  /// further rounding - reflects a freshly claimed zone's ongoing rate.
  double get rewardCreditsPerHour => totalAreaM2 / 1e6;
}
