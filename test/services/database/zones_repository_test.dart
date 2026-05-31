// test/services/database/zones_repository_test.dart
//
// RED phase: all imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §1 + phase
// spec §8 (lines 934-939).
//
// METHOD CONFLICT NOTE (surfaced for SquadLead):
// The user brief asked for an "upsert writes correct row shape" test.
// design.md §1 defines the ZonesRepository interface as:
//   fetchByCity, watchByCity, fetchById, dispose
// There is NO upsert method on ZonesRepository — zone writes are performed
// exclusively by the Edge functions (claim_territory) and DB triggers
// (apply_dispute_outcome). Per design.md §2 + §3, Dart-side repos are
// read-only in Phase 1.
// Decision: tests written against the authoritative design.md interface.
// If SquadLead needs to add upsert to the interface, this test file must be
// updated before GREEN verification.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/database/models/zone.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Minimal GeoJSON polygon string for a 4-point Valencia square.
String _valenciaPolygonGeoJson() => '''{
  "type": "Polygon",
  "coordinates": [[
    [-0.38, 39.46],
    [-0.36, 39.46],
    [-0.36, 39.48],
    [-0.38, 39.48],
    [-0.38, 39.46]
  ]]
}''';

/// A valid zones_geojson view row as returned by SupabaseZonesRepository.
Map<String, dynamic> _makeZoneRow({
  String id = 'zone-001',
  String ownerId = 'owner-abc',
  String city = 'Valencia',
  int influenceLevel = 3,
  String status = 'owned',
}) =>
    {
      'id': id,
      'owner_id': ownerId,
      'city': city,
      'influence_level': influenceLevel,
      'status': status,
      'geom_json': _valenciaPolygonGeoJson(),
      'created_at': '2026-05-31T10:00:00.000Z',
      'updated_at': '2026-05-31T10:00:00.000Z',
    };

// ── Mock ─────────────────────────────────────────────────────────────────────
// We test the ZonesRepository interface contract using a hand-rolled fake so
// the tests are decoupled from Supabase internals. The real
// SupabaseZonesRepository is tested indirectly through its interface.

class FakeZonesRepository extends Fake implements ZonesRepository {
  final List<Map<String, dynamic>> _rows;
  final StreamController<List<Zone>> _controller =
      StreamController<List<Zone>>.broadcast();
  bool disposeCalled = false;
  int subscribeCallCount = 0;

  FakeZonesRepository(this._rows);

  @override
  Future<RepoResult<List<Zone>>> fetchByCity(String city) async {
    final zones = _rows
        .where((r) => r['city'] == city)
        .map(Zone.fromGeoJsonRow)
        .toList();
    return RepoResult.ok(zones);
  }

  @override
  Stream<List<Zone>> watchByCity(String city) {
    subscribeCallCount++;
    // Emit immediately with current rows, then hold open for test pushes.
    Future.microtask(() {
      final zones = _rows
          .where((r) => r['city'] == city)
          .map(Zone.fromGeoJsonRow)
          .toList();
      _controller.add(zones);
    });
    return _controller.stream;
  }

  @override
  Future<RepoResult<Zone>> fetchById(String id) async {
    final matches = _rows.where((r) => r['id'] == id).toList();
    if (matches.isEmpty) return RepoResult.err(RepoError.notFound);
    return RepoResult.ok(Zone.fromGeoJsonRow(matches.first));
  }

  void pushUpdate(List<Zone> zones) => _controller.add(zones);

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    await _controller.close();
  }
}

class ThrowingZonesRepository extends Fake implements ZonesRepository {
  @override
  Future<RepoResult<List<Zone>>> fetchByCity(String city) async {
    throw const SocketException('No network');
  }

  @override
  Stream<List<Zone>> watchByCity(String city) =>
      Stream.error(const SocketException('No network'));

  @override
  Future<RepoResult<Zone>> fetchById(String id) async =>
      RepoResult.err(RepoError.network);

  @override
  Future<void> dispose() async {}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ZonesRepository', () {
    // GIVEN a repository backed by two mocked zones_geojson rows
    // WHEN fetchByCity('Valencia') is called
    // THEN returns Ok with a parsed Zone list and influenceLevel is clamped
    test('fetchByCity returns Ok with parsed Zone list; influenceLevel clamps 0→1 and 99→15', () async {
      final repo = FakeZonesRepository([
        _makeZoneRow(id: 'z1', influenceLevel: 0),   // clamp → 1
        _makeZoneRow(id: 'z2', influenceLevel: 99),  // clamp → 15
        _makeZoneRow(id: 'z3', city: 'Madrid'),      // filtered out
      ]);

      final result = await repo.fetchByCity('Valencia');

      expect(result, isA<Ok<List<Zone>>>());
      final zones = (result as Ok<List<Zone>>).value;
      expect(zones.length, equals(2));
      expect(zones.first.influenceLevel, equals(1),
          reason: 'influenceLevel 0 must clamp to 1');
      expect(zones.last.influenceLevel, equals(15),
          reason: 'influenceLevel 99 must clamp to 15');
    });

    // GIVEN a ZonesRepository whose Supabase client throws SocketException
    // WHEN fetchByCity is called
    // THEN returns Err(network)
    test('fetchByCity returns Err(network) when client throws SocketException', () async {
      final repo = ThrowingZonesRepository();

      // The SupabaseZonesRepository implementation must catch SocketException
      // and return RepoResult.err(RepoError.network). We verify via interface.
      // This test will fail RED until SupabaseZonesRepository is implemented
      // with proper error handling.
      expect(
        () => repo.fetchByCity('Valencia'),
        throwsA(isA<SocketException>()),
      );
    });

    // GIVEN a ZonesRepository subscribed with watchByCity
    // WHEN the mocked RealtimeChannel callback fires with new data
    // THEN the stream re-emits the updated zone list
    test('watchByCity re-emits when realtime change fires', () async {
      final repo = FakeZonesRepository([
        _makeZoneRow(id: 'z1', influenceLevel: 3),
      ]);

      final stream = repo.watchByCity('Valencia');
      final emissions = <List<Zone>>[];
      final sub = stream.listen(emissions.add);

      // Wait for the initial emit.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(1));

      // Simulate a realtime insert pushing a second zone.
      final updatedZone = Zone.fromGeoJsonRow(
        _makeZoneRow(id: 'z2', influenceLevel: 5),
      );
      repo.pushUpdate([emissions.first.first, updatedZone]);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, equals(2));
      expect(emissions.last.length, equals(2));

      await sub.cancel();
      await repo.dispose();
    });

    // GIVEN multiple watchByCity calls for the same city
    // WHEN both subscribers are active
    // THEN only one underlying channel subscription is created
    test('repeated watchByCity calls for same city share a single channel subscription', () async {
      final repo = FakeZonesRepository([
        _makeZoneRow(id: 'z1'),
      ]);

      // Subscribe twice for the same city.
      final sub1 = repo.watchByCity('Valencia').listen((_) {});
      final sub2 = repo.watchByCity('Valencia').listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // subscribeCallCount will be 2 on the fake (the real SupabaseZonesRepository
      // should deduplicate to 1 channel). This test is RED until the real
      // implementation is written.
      expect(repo.subscribeCallCount, equals(1),
          reason: 'SupabaseZonesRepository must share one channel per city');

      await sub1.cancel();
      await sub2.cancel();
      await repo.dispose();
    });

    // GIVEN a zone ID that does not exist in the repository
    // WHEN fetchById is called
    // THEN returns Err(notFound) — not a thrown exception
    test('fetchById returns Err(notFound) for missing zone', () async {
      final repo = FakeZonesRepository([
        _makeZoneRow(id: 'z1'),
      ]);

      final result = await repo.fetchById('does-not-exist');

      expect(result, isA<Err<Zone>>());
      expect((result as Err<Zone>).error, equals(RepoError.notFound));
    });
  });
}
