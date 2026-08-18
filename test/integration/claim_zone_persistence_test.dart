// test/integration/claim_zone_persistence_test.dart
//
// Behavioral confirmation of AC-A1: a claimed zone must stay rendered
// through a zonesProvider invalidate/reload frame and through a subsequent
// stream error, with the error banner shown - never a blank frame in
// between. Also doubles as AC-E5's "assertable independent of whether
// gps_samples/track_json logic is correct" requirement: userRunPointsProvider
// is overridden to an intentionally empty list, and the zone still renders
// because it is owned by the current user.
//
// Modeled directly on test/integration/dispute_flow_test.dart's structure
// (MockZonesRepository (mocktail) + StreamController<List<Zone>>.broadcast()
// + makeTestContainer + UncontrolledProviderScope + MaterialApp(home:
// MapScreen())), with the flutter-test-patterns.md FlutterMap timer-drain
// teardown and bounded-pump settle helper.
//
// RED today: the current loading:/error: branches in zonesAsync.when() pass
// a bare const [] unconditionally, so the zone disappears on both the
// invalidate-triggered reload and the subsequent error.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:runwar_app/screens/map_screen.dart';
import 'package:runwar_app/services/database/repository.dart';
import 'package:runwar_app/services/database/zones_repository.dart';
import 'package:runwar_app/services/database/models/zone.dart';
import 'package:runwar_app/providers/auth_provider.dart';
import 'package:runwar_app/providers/cities_provider.dart';
import 'package:runwar_app/providers/profile_provider.dart';
import 'package:runwar_app/providers/run_recorder_provider.dart';
import 'package:runwar_app/providers/runs_provider.dart';
import 'package:runwar_app/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../_helpers/test_container.dart';

class _InMemoryGotrueStorage extends GotrueAsyncStorage {
  final _store = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _store[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _store[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _store.remove(key);
}

class _FakeRef extends Fake implements Ref {}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(user: {'id': _kCurrentUserId, 'city': 'Valencia'});
  }
}

class _StubRunRecorderNotifier extends RunRecorderNotifier {
  _StubRunRecorderNotifier() : super(_FakeRef());
}

class MockZonesRepository extends Mock implements ZonesRepository {}

const _kOwnedZoneId = 'z-owned-1';
const _kCurrentUserId = 'current-player';

Map<String, dynamic> _ownedZoneRow({String status = 'owned'}) => {
      'id': _kOwnedZoneId,
      'owner_id': _kCurrentUserId,
      'city': 'Valencia',
      'influence_level': 2,
      'status': status,
      'geom_json': '{"type":"Polygon","coordinates":[[[-0.378,39.469],[-0.374,39.469],[-0.374,39.471],[-0.378,39.471],[-0.378,39.469]]]}',
      'created_at': '2026-05-31T10:00:00.000Z',
      'updated_at': '2026-05-31T10:00:00.000Z',
    };

// Bounded pump sequence - MapScreen's repeating pulse animation never stops,
// so pumpAndSettle() hangs forever. See dispute_flow_test.dart's identical
// helper/rationale.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://placeholder-test.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0In0.placeholder',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _InMemoryGotrueStorage(),
      ),
    );
    registerFallbackValues();
  });

  group('claimed zone stays rendered through reload and error frames', () {
    late MockZonesRepository mockZonesRepo;
    late StreamController<List<Zone>> zonesController;

    setUp(() {
      mockZonesRepo = MockZonesRepository();
      zonesController = StreamController<List<Zone>>.broadcast();

      when(() => mockZonesRepo.watchByCity('Valencia'))
          .thenAnswer((_) => zonesController.stream);
      when(() => mockZonesRepo.fetchByCity('Valencia')).thenAnswer(
        (_) async => RepoResult.ok([Zone.fromGeoJsonRow(_ownedZoneRow())]),
      );
      when(() => mockZonesRepo.dispose()).thenAnswer((_) async {});
    });

    tearDown(() async {
      await zonesController.close();
    });

    testWidgets('zone renders through invalidate reload and a subsequent stream error, with the error banner shown',
        (tester) async {
      final container = makeTestContainer(
        zonesRepo: mockZonesRepo,
        overrides: [
          authProvider.overrideWith((_) => _FakeAuthNotifier()),
          profileGateProvider.overrideWith(
            (_, userId) async => <String, dynamic>{'id': userId, 'city': 'Valencia'},
          ),
          runRecorderProvider.overrideWith((_) => _StubRunRecorderNotifier()),
          joinedCitySlugsProvider(_kCurrentUserId)
              .overrideWith((ref) async => ['valencia']),
          // Fog source is deliberately empty/irrelevant - AC-A1's persistence
          // claim must hold regardless of whether E1-E4's gps_samples logic
          // is itself correct, and this zone is owned so AC-E5's guard is
          // exercised too.
          userRunPointsProvider((userId: _kCurrentUserId, city: 'Valencia'))
              .overrideWith((ref) async => const <LatLng>[]),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MapScreen()),
        ),
      );

      await _settle(tester);
      zonesController.add([Zone.fromGeoJsonRow(_ownedZoneRow())]);
      await _settle(tester);

      expect(find.byKey(ValueKey('zone-$_kOwnedZoneId')), findsOneWidget,
          reason: 'the owned zone must render after the initial claim/fetch');

      // Reload transition: re-trigger the stream (mirrors a claim-triggered
      // ref.invalidate(zonesProvider(city)) reload). The zone must still be
      // present, not blanked, through this frame.
      zonesController.add([Zone.fromGeoJsonRow(_ownedZoneRow())]);
      await _settle(tester);

      expect(find.byKey(ValueKey('zone-$_kOwnedZoneId')), findsOneWidget,
          reason: 'the zone must remain rendered through a reload frame, not vanish (AC-A1)');

      // Transient network failure: the stream errors. Last-good zones must
      // stay visible and the error banner must appear.
      zonesController.addError(Exception('network'));
      await _settle(tester);

      expect(find.byKey(ValueKey('zone-$_kOwnedZoneId')), findsOneWidget,
          reason: 'the zone must remain rendered even after the zones stream errors (AC-A1)');
      expect(find.text('Could not load zone data'), findsOneWidget,
          reason: 'an error banner must still be surfaced on the error branch (showError: true)');
    });
  });
}
