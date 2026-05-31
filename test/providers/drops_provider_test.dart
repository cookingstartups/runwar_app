// test/providers/drops_provider_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Failures will be "Target of URI doesn't exist" compile errors — expected.
// Each test maps to exactly one GIVEN/WHEN/THEN from design.md §5.1 + spec §6.3.
//
// Design contract (design.md §5.1):
//   final activeDropsProvider = StreamProvider.family<List<Drop>, String>(
//     (r, city) => r.read(dropsRepoProvider).watchActive(city));

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/providers/drops/active_drops_provider.dart';
import 'package:runwar_app/services/database/drops_repository.dart';

import '../_helpers/test_container.dart';

// ── Fake ─────────────────────────────────────────────────────────────────────

class FakeDropsRepoForProvider implements DropsRepository {
  final StreamController<List<Drop>> _ctrl = StreamController<List<Drop>>.broadcast();
  List<Drop> _drops;

  FakeDropsRepoForProvider(this._drops);

  void pushDrops(List<Drop> drops) {
    _drops = drops;
    _ctrl.add(drops);
  }

  @override
  Stream<List<Drop>> watchActive(String city) {
    Future.microtask(() {
      _ctrl.add(_drops.where((d) => d.city == city).toList());
    });
    return _ctrl.stream;
  }

  @override
  Future<ClaimDropResult> claim(String dropId, double lat, double lng) async =>
      const ClaimDropFailure('not_found');

  Future<void> dispose() async => _ctrl.close();
}

Drop _makeDrop({
  String id = 'drop-001',
  String city = 'Valencia',
  String dropType = 'credits_cache',
}) =>
    Drop(
      id: id,
      city: city,
      lat: 39.47,
      lng: -0.37,
      dropType: dropType,
      value: 50,
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      status: 'active',
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('activeDropsProvider', () {
    // GIVEN a dropsRepoProvider overridden with 2 Valencia drops
    // WHEN activeDropsProvider('Valencia') is read
    // THEN resolves to AsyncData with both drops
    test('resolves to AsyncData with the list of active drops for the city', () async {
      final drops = [
        _makeDrop(id: 'd1', city: 'Valencia'),
        _makeDrop(id: 'd2', city: 'Valencia'),
      ];
      final fakeRepo = FakeDropsRepoForProvider(drops);
      final container = makeTestContainer(dropsRepo: fakeRepo);
      addTearDown(container.dispose);

      final sub = container.listen(
        activeDropsProvider('Valencia'),
        (_, __) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = container.read(activeDropsProvider('Valencia'));

      expect(state, isA<AsyncData<List<Drop>>>());
      expect(state.value!.length, equals(2));

      sub.close();
      await fakeRepo.dispose();
    });

    // GIVEN an active drops provider
    // WHEN a new drop is pushed via realtime
    // THEN provider updates to include the new drop
    test('updates when the drops stream emits a new list', () async {
      final fakeRepo = FakeDropsRepoForProvider([_makeDrop(id: 'd1')]);
      final container = makeTestContainer(dropsRepo: fakeRepo);
      addTearDown(container.dispose);

      final emissions = <AsyncValue<List<Drop>>>[];
      final sub = container.listen(
        activeDropsProvider('Valencia'),
        (_, next) => emissions.add(next),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      fakeRepo.pushDrops([_makeDrop(id: 'd1'), _makeDrop(id: 'd2')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dataEmissions = emissions.whereType<AsyncData<List<Drop>>>().toList();
      expect(dataEmissions.isNotEmpty, isTrue);
      expect(dataEmissions.last.value!.length, equals(2),
          reason: 'Provider must reflect the updated drop list');

      sub.close();
      await fakeRepo.dispose();
    });

    // GIVEN different city keys as the family argument
    // WHEN activeDropsProvider('Valencia') and activeDropsProvider('Madrid') are read
    // THEN they are separate provider instances (family isolation)
    test('activeDropsProvider.family creates separate instances per city', () {
      final provValencia = activeDropsProvider('Valencia');
      final provMadrid   = activeDropsProvider('Madrid');

      expect(provValencia == provMadrid, isFalse,
          reason: 'Different city keys must produce different provider instances');
    });
  });
}
