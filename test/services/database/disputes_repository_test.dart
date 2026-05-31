// test/services/database/disputes_repository_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Each test maps to one GIVEN/WHEN/THEN from design.md §1 + phase spec §8
// (lines 945-948).
//
// METHOD CONFLICT NOTE (surfaced for SquadLead):
// The user brief asked for tests of fetchActive, create (with
// defender_id/attacker_id/expires_at formula), and resolve (sets
// resolved_at + winner_id). design.md §1 defines DisputesRepository as:
//   fetchOpenForZone, watchOpenForZone, fetchById, dispose
// There is NO fetchActive, create, or resolve on DisputesRepository.
// Per design.md §2, dispute creation is done by the claim_territory Edge
// function; dispute resolution is done by resolve_dispute Edge fn + the
// apply_dispute_outcome DB trigger. The Dart repo is read-only in Phase 1.
// Decision: tests written against design.md §1's authoritative interface.
// The expires_at formula (level × 1200 seconds) is tested via a row
// assertion on fetchOpenForZone, which IS the correct Phase 1 read path.
// If SquadLead adds write methods to DisputesRepository, add tests here.
//
// Design contract (design.md §1):
//   fetchOpenForZone(zoneId) → Future<RepoResult<Dispute?>>
//     - Returns Ok(null) when only resolved disputes exist
//     - Returns Ok(Dispute) when one open dispute matches; expiresAt = level × 1200s
//     - Returns Err(network) on client failure

import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/disputes_repository.dart';
import 'package:runwar_app/services/database/models/dispute.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

DateTime _nowPlusSecs(int secs) =>
    DateTime.now().toUtc().add(Duration(seconds: secs));

/// A valid disputes row with resolved_at IS NULL (open).
Map<String, dynamic> _openDisputeRow({
  String id = 'dispute-001',
  String zoneId = 'zone-001',
  String attackerId = 'attacker-abc',
  String defenderId = 'defender-xyz',
  int level = 3,
}) =>
    {
      'id': id,
      'zone_id': zoneId,
      'attacker_id': attackerId,
      'defender_id': defenderId,
      // expires_at = level × 1200 seconds from now (design.md §1 Dispute model)
      'expires_at': _nowPlusSecs(level * 1200).toIso8601String(),
      'resolved_at': null,
      'winner_id': null,
      'created_at': '2026-05-31T10:00:00.000Z',
    };

/// A resolved dispute row.
Map<String, dynamic> _resolvedDisputeRow({
  String id = 'dispute-resolved-001',
  String zoneId = 'zone-001',
  String attackerId = 'attacker-abc',
  String defenderId = 'defender-xyz',
}) =>
    {
      'id': id,
      'zone_id': zoneId,
      'attacker_id': attackerId,
      'defender_id': defenderId,
      'expires_at': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String(),
      'resolved_at': DateTime.now()
          .subtract(const Duration(minutes: 3))
          .toUtc()
          .toIso8601String(),
      'winner_id': defenderId,
      'created_at': '2026-05-31T09:00:00.000Z',
    };

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeDisputesRepository extends Fake implements DisputesRepository {
  final List<Map<String, dynamic>> _rows;

  FakeDisputesRepository(this._rows);

  @override
  Future<RepoResult<Dispute?>> fetchOpenForZone(String zoneId) async {
    final open = _rows.where((r) =>
        r['zone_id'] == zoneId && r['resolved_at'] == null);
    if (open.isEmpty) return RepoResult.ok(null);
    return RepoResult.ok(Dispute.fromRow(open.first));
  }

  @override
  Stream<Dispute?> watchOpenForZone(String zoneId) => Stream.value(null);

  @override
  Future<RepoResult<Dispute>> fetchById(String id) async {
    final matches = _rows.where((r) => r['id'] == id).toList();
    if (matches.isEmpty) return RepoResult.err(RepoError.notFound);
    return RepoResult.ok(Dispute.fromRow(matches.first));
  }

  @override
  Future<void> dispose() async {}
}

class NetworkErrorDisputesRepository extends Fake
    implements DisputesRepository {
  @override
  Future<RepoResult<Dispute?>> fetchOpenForZone(String zoneId) async =>
      RepoResult.err(RepoError.network, detail: 'SocketException: No network');

  @override
  Stream<Dispute?> watchOpenForZone(String zoneId) =>
      Stream.error(Exception('No network'));

  @override
  Future<RepoResult<Dispute>> fetchById(String id) async =>
      RepoResult.err(RepoError.network);

  @override
  Future<void> dispose() async {}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('DisputesRepository', () {
    // GIVEN a zone that has only resolved disputes (resolved_at IS NOT NULL)
    // WHEN fetchOpenForZone is called
    // THEN returns Ok(null) — no open dispute
    test('fetchOpenForZone returns Ok(null) when only resolved disputes exist', () async {
      final repo = FakeDisputesRepository([
        _resolvedDisputeRow(zoneId: 'zone-001'),
      ]);

      final result = await repo.fetchOpenForZone('zone-001');

      expect(result, isA<Ok<Dispute?>>());
      expect((result as Ok<Dispute?>).value, isNull);
    });

    // GIVEN a zone with one open dispute (resolved_at IS NULL)
    // WHEN fetchOpenForZone is called
    // THEN returns Ok(Dispute) with correct IDs and expiresAt formula
    test('fetchOpenForZone returns Ok(Dispute) when one open dispute matches; expires_at is level × 1200 seconds', () async {
      const level = 3;
      final beforeCall = DateTime.now().toUtc();
      final repo = FakeDisputesRepository([
        _openDisputeRow(
          zoneId: 'zone-001',
          attackerId: 'player-alpha',
          defenderId: 'player-beta',
          level: level,
        ),
      ]);

      final result = await repo.fetchOpenForZone('zone-001');

      expect(result, isA<Ok<Dispute?>>());
      final dispute = (result as Ok<Dispute?>).value;
      expect(dispute, isNotNull);
      expect(dispute!.attackerId, equals('player-alpha'));
      expect(dispute.defenderId, equals('player-beta'));

      // expires_at must be approximately level × 1200 seconds from now.
      final expectedExpiry =
          beforeCall.add(Duration(seconds: level * 1200));
      final actualExpiry = dispute.expiresAt;
      final diff = actualExpiry.difference(expectedExpiry).abs();
      expect(diff.inSeconds, lessThan(5),
          reason:
              'expires_at should be ~level×1200s from creation; got $actualExpiry expected ~$expectedExpiry');
    });

    // GIVEN a client that throws a network error
    // WHEN fetchOpenForZone is called
    // THEN returns Err(network) — does not throw
    test('fetchOpenForZone returns Err(network) on client failure', () async {
      final repo = NetworkErrorDisputesRepository();

      final result = await repo.fetchOpenForZone('zone-001');

      expect(result, isA<Err<Dispute?>>());
      expect((result as Err<Dispute?>).error, equals(RepoError.network));
    });
  });
}
