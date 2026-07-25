// test/providers/dispute_countdown_provider_test.dart
//
// RED phase: disputeCountdownProvider is re-pointed at the zone's own
// status/dispute_at fields (sourced from ZonesRepository), not the dead
// disputes table via DisputesRepository. The family key and the
// Duration-computation/streaming contract (emit immediately, tick every
// second, close at Duration.zero) are unchanged - only the data source.
//
// This file intentionally imports Zone.disputeAt, a field that does not
// exist yet, and mocks ZonesRepository instead of DisputesRepository - both
// fail to compile/resolve until the zone-sourced countdown is implemented.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/providers/dispute_countdown_provider.dart';
import 'package:runwar_app/providers/zones_repository_provider.dart';
import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/database/models/zone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MockZonesRepository extends Mock implements ZonesRepository {}

/// Builds a Zone whose dispute expires [secsFromNow] seconds in the future
/// (or in the past, for a negative value). Uses the not-yet-existing
/// Zone.disputeAt field.
Zone _disputedZone(int secsFromNow, {String zoneId = 'zone-001'}) => Zone(
      id: zoneId,
      ownerId: 'defender-xyz',
      city: 'Valencia',
      influenceLevel: 3,
      status: ZoneStatus.disputed,
      points: const [],
      disputeAt: DateTime.now().toUtc().add(Duration(seconds: secsFromNow)),
    );

Zone _undisputedZone({String zoneId = 'zone-none'}) => Zone(
      id: zoneId,
      ownerId: 'defender-xyz',
      city: 'Valencia',
      influenceLevel: 3,
      status: ZoneStatus.owned,
      points: const [],
      disputeAt: null,
    );

void main() {
  group('disputeCountdownProvider: zone-sourced dispute state', () {
    test('emits decreasing Duration values sourced from the zone\'s own dispute_at', () async {
      final mockRepo = MockZonesRepository();
      when(() => mockRepo.fetchById('zone-001')).thenAnswer(
        (_) async => RepoResult.ok(_disputedZone(5)),
      );

      final container = ProviderContainer(overrides: [
        zonesRepositoryProvider.overrideWithValue(mockRepo),
      ]);
      addTearDown(container.dispose);

      final emissions = <Duration>[];
      final completer = Completer<void>();
      container
          .read(disputeCountdownProvider('zone-001'))
          .take(3)
          .toList()
          .then((list) {
        emissions.addAll(list);
        completer.complete();
      });

      await completer.future.timeout(const Duration(seconds: 5));

      expect(emissions.length, equals(3));
      for (var i = 1; i < emissions.length; i++) {
        expect(emissions[i], lessThan(emissions[i - 1]));
      }
    });

    test('stream terminates at Duration.zero when the zone dispute expires', () async {
      final mockRepo = MockZonesRepository();
      when(() => mockRepo.fetchById('zone-term')).thenAnswer(
        (_) async => RepoResult.ok(_disputedZone(2, zoneId: 'zone-term')),
      );

      final container = ProviderContainer(overrides: [
        zonesRepositoryProvider.overrideWithValue(mockRepo),
      ]);
      addTearDown(container.dispose);

      final allEmissions = <Duration>[];
      final doneCompleter = Completer<void>();

      container.read(disputeCountdownProvider('zone-term')).listen(
            allEmissions.add,
            onDone: () => doneCompleter.complete(),
          );

      await doneCompleter.future.timeout(const Duration(seconds: 5));

      expect(allEmissions.last, equals(Duration.zero));
    });

    test('emits Duration.zero immediately when the zone is not disputed', () async {
      final mockRepo = MockZonesRepository();
      when(() => mockRepo.fetchById('zone-none')).thenAnswer(
        (_) async => RepoResult.ok(_undisputedZone()),
      );

      final container = ProviderContainer(overrides: [
        zonesRepositoryProvider.overrideWithValue(mockRepo),
      ]);
      addTearDown(container.dispose);

      final firstEmission = await container
          .read(disputeCountdownProvider('zone-none'))
          .first
          .timeout(const Duration(seconds: 2));

      expect(firstEmission, equals(Duration.zero));
    });

    test('never queries the disputes table or DisputesRepository', () {
      // Source-level guard: the retired disputes/DisputesRepository symbols
      // must not appear in the provider implementation once it is
      // re-pointed at zones. Fails today because the provider still imports
      // disputes_repository_provider.dart.
      final src = File('lib/providers/dispute_countdown_provider.dart')
          .readAsStringSync();
      expect(src.contains('DisputesRepository'), isFalse,
          reason: 'disputeCountdownProvider must not reference DisputesRepository once re-pointed at zones');
      expect(src.contains('disputes_repository_provider'), isFalse,
          reason: 'disputeCountdownProvider must not import the retired disputes repository provider');
    });
  });
}
