// test/main/route_guard_test.dart
//
// RED phase — SDD F4 Unified Boot Splash.
// Each test maps 1-to-1 with an AC from:
//   infra/meta/specs/runwar/mvp/boot-splash-unified/requirements.md
//
// Files under test (do not yet exist in their redesigned form):
//   lib/main.dart              — _RouteGuardState (redesigned), _ErrorOverlay (new), _GateLoading (DELETED)
//   lib/services/error_log_service.dart  — ErrorLogService (new)
//
// Framework: flutter_test + flutter_riverpod + mocktail (mirrors project conventions).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Providers consumed by _RouteGuardState.build() ───────────────────────────
import 'package:runwar_app/providers/auth_provider.dart';
import 'package:runwar_app/providers/showcase_provider.dart';
import 'package:runwar_app/providers/profile_provider.dart';
import 'package:runwar_app/providers/cities_provider.dart';
import 'package:runwar_app/providers/mission_provider.dart';
import 'package:runwar_app/services/trial_service.dart';

// trialStatusProvider lives in main.dart at top level
import 'package:runwar_app/main.dart' show trialStatusProvider, RunWarApp;

// The new service under test — does not exist yet (RED).
import 'package:runwar_app/services/error_log_service.dart';

// SplashScreen — referenced in assertions; already exists.
import 'package:runwar_app/screens/splash_screen.dart';

// Destination screens — for routing assertions.
import 'package:runwar_app/screens/auth/login_screen.dart';
import 'package:runwar_app/screens/intro_screen.dart';
import 'package:runwar_app/screens/main_shell.dart';

// AuthService — needed to construct AuthNotifier stubs.
import 'package:runwar_app/services/auth_service.dart';

// ── Stub AuthNotifier subclasses ──────────────────────────────────────────────

/// AuthNotifier that immediately emits [AuthState] with no user (unauthenticated).
class _UnauthAuthNotifier extends AuthNotifier {
  _UnauthAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(user: null);
  }

  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
}

/// AuthNotifier that emits an authenticated [AuthState] immediately.
class _AuthedAuthNotifier extends AuthNotifier {
  _AuthedAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(user: {'id': 'user-abc-123'});
  }

  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
}

/// AuthNotifier that stays in the loading state (isLoading: true).
/// Simulates authProvider never settling — splash must hold.
class _LoadingAuthNotifier extends AuthNotifier {
  _LoadingAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(isLoading: true);
  }

  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
}

// NOTE: _RouteGuardState.build() currently reads `authState.isLoading` as the
// loading signal for authProvider (it's a StateNotifier, not AsyncValue).
// The redesign wraps the auth watch in AsyncValue — the isLoading flag on
// AuthState drives `anyLoading` for the auth branch per design.md §Provider Watch Strategy.

// ── Showcase provider overrides ───────────────────────────────────────────────

/// showcaseSeenProvider that stays loading (never emits).
final _loadingShowcaseOverride = showcaseSeenProvider.overrideWith(
  (ref) async {
    await Completer<void>().future; // never completes
    return false;
  },
);

/// showcaseSeenProvider that resolves to true.
final _showcaseSeenOverride = showcaseSeenProvider.overrideWith(
  (ref) async => true,
);

/// showcaseSeenProvider that resolves to false.
final _showcaseNotSeenOverride = showcaseSeenProvider.overrideWith(
  (ref) async => false,
);

/// showcaseSeenProvider that throws an error.
final _showcaseErrorOverride = showcaseSeenProvider.overrideWith(
  (ref) async {
    throw Exception('showcase db unreachable');
  },
);

// ── userId-scoped provider overrides ─────────────────────────────────────────

/// hasPhoneProvider that never settles (loading).
Override _loadingHasPhoneOverride(String userId) =>
    hasPhoneProvider(userId).overrideWith(
      (ref) async {
        await Completer<void>().future;
        return false;
      },
    );

/// profileGateProvider that throws an error.
Override _profileErrorOverride(String userId) =>
    profileGateProvider(userId).overrideWith(
      (ref) async {
        throw Exception('profile fetch failed');
      },
    );

/// All 5 userId-scoped providers resolving to values that clear all gates.
List<Override> _allUserProvidersCleared(String userId) => [
      hasPhoneProvider(userId).overrideWith((ref) async => true),
      joinedCitySlugsProvider(userId)
          .overrideWith((ref) async => ['valencia']),
      profileGateProvider(userId).overrideWith((ref) async => {
            'username': 'alice',
            'invited_at': '2025-01-01T00:00:00Z',
          }),
      missionStatusProvider(userId).overrideWith(
        (ref) async => MissionStatus(
          firstMissionCompletedAt: null,
          firstAttackCompletedAt: DateTime.fromMillisecondsSinceEpoch(1),
          zoneCount: 1,
        ),
      ),
      trialStatusProvider(userId).overrideWith(
        (ref) async =>
            const TrialStatus(started: false, daysRemaining: 14, streak: 0),
      ),
    ];

// ── Widget wrapper ─────────────────────────────────────────────────────────────

Widget _scope(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: const RunWarApp(),
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // AC-1  Single splash held during parallel provider load
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-1: single SplashScreen held while any provider is AsyncLoading', () {
    // GIVEN the app launches cold and authProvider is in loading state
    // WHEN _RouteGuard.build() executes
    // THEN exactly one SplashScreen with statusLabel 'SYNCING TERRITORY' is shown
    //   AND the old _GateLoading 20×20 spinner SizedBox is not in the tree
    testWidgets(
        'shows SplashScreen with SYNCING TERRITORY when authProvider is loading',
        (tester) async {
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _LoadingAuthNotifier()),
      ]));
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget,
          reason: 'SplashScreen must be the only top-level widget while loading');
      expect(find.text('SYNCING TERRITORY'), findsOneWidget,
          reason: 'statusLabel must read SYNCING TERRITORY during boot load');

      // _GateLoading (deleted) had a distinctive 20×20 SizedBox + CircularProgressIndicator.
      expect(
        find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 20 && w.height == 20),
        findsNothing,
        reason:
            '_GateLoading 20×20 SizedBox must not exist — class must be deleted',
      );
    });

    // GIVEN auth resolves to null AND showcaseSeenProvider stays loading
    // WHEN the widget tree is rebuilt after auth settles
    // THEN SplashScreen persists (showcase still loading)
    testWidgets(
        'splash persists when showcaseSeenProvider is still loading after auth resolves',
        (tester) async {
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _UnauthAuthNotifier()),
        _loadingShowcaseOverride,
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SplashScreen), findsOneWidget,
          reason: 'Splash must remain until ALL applicable providers resolve');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-2  Providers watched in parallel within the same build frame
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-2: all applicable providers watched in parallel within one build()', () {
    // GIVEN userId is known AND hasPhoneProvider is still loading
    // WHEN _RouteGuard.build() runs after auth resolves
    // THEN splash holds (hasPhoneProvider is still loading — it was watched in the same frame as auth)
    testWidgets(
        'splash holds after auth resolves when a userId-scoped provider is still loading',
        (tester) async {
      const userId = 'user-abc-123';
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _AuthedAuthNotifier()),
        _showcaseSeenOverride,
        _loadingHasPhoneOverride(userId),
        // remaining userId providers not overridden — may error, which is also valid RED
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SplashScreen), findsOneWidget,
          reason:
              'Splash must remain after auth resolves while hasPhoneProvider is loading — '
              'proves providers are watched in parallel, not serially');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-3  Unauthenticated boot — userId-scoped providers not watched
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-3: unauthenticated boot routes without watching userId-scoped providers',
      () {
    // GIVEN user == null AND showcaseSeenProvider resolves true
    // WHEN _RouteGuard.build() evaluates
    // THEN LoginScreen is shown; SplashScreen is gone
    testWidgets(
        'routes to LoginScreen when user is null and showcase has been seen',
        (tester) async {
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _UnauthAuthNotifier()),
        _showcaseSeenOverride,
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget,
          reason:
              'Unauthenticated user who has seen showcase must reach LoginScreen');
      expect(find.byType(SplashScreen), findsNothing,
          reason: 'SplashScreen must be removed once all applicable providers settled');
    });

    // GIVEN user == null AND showcaseSeenProvider resolves false
    // WHEN _RouteGuard source is inspected
    // THEN IntroScreen is referenced as the routing destination
    //   AND it is guarded by the negated showcaseSeen condition (showcaseSeen == false)
    // Source-level check: avoids instantiating FlutterMap which generates 939
    // HTTP-400 tile errors in TestWidgetsFlutterBinding fake-async environment.
    test('routes to IntroScreen when user is null and showcase not yet seen', () {
      final mainDart = File('lib/main.dart');
      expect(mainDart.existsSync(), isTrue, reason: 'lib/main.dart must exist');
      final content = mainDart.readAsStringSync();

      // The routing destination must be present.
      expect(
        content.contains('IntroScreen'),
        isTrue,
        reason: 'lib/main.dart must reference IntroScreen as a routing destination',
      );

      // The IntroScreen branch must be the "not seen" branch of the routing
      // logic. Acceptable patterns (any one suffices):
      //   • `!showcaseSeen`          — explicit negation
      //   • `showcaseSeen == false`  — equality check
      //   • `showcaseSeen != true`   — inequality check
      //   • `seen ? ... : IntroScreen` — ternary where seen=false → IntroScreen
      //     (variable may be named `seen`, `showcaseSeen`, or similar)
      // We check by finding `IntroScreen` in the routing region and confirming
      // it is the else/false branch of a conditional on the showcase flag.
      final introIndex = content.indexOf('IntroScreen');
      expect(introIndex, greaterThan(0),
          reason: 'IntroScreen must appear in main.dart source');
      final precedingSource = content.substring(0, introIndex);
      // Pattern A: explicit negation or equality forms
      final hasExplicitNegation = precedingSource.contains('!showcaseSeen') ||
          precedingSource.contains('showcaseSeen == false') ||
          precedingSource.contains('showcaseSeen != true');
      // Pattern B: ternary — a boolean flag (seen / showcaseSeen) appears just
      // before the ternary that places IntroScreen on the false branch.
      // The line containing IntroScreen must have `?` earlier (i.e. it is the
      // false-branch of a ternary: `seen ? LoginScreen() : IntroScreen()`).
      final introLineStart = content.lastIndexOf('\n', introIndex);
      final introLine = content.substring(introLineStart, introIndex);
      final hasTernaryFalseBranch = introLine.contains(':') &&
          (precedingSource.contains('final seen') ||
              precedingSource.contains('showcaseSeen'));
      expect(
        hasExplicitNegation || hasTernaryFalseBranch,
        isTrue,
        reason:
            'IntroScreen must be reached via the negated showcaseSeen guard. '
            'Expected one of: !showcaseSeen, showcaseSeen==false, '
            'or a ternary where IntroScreen is the false (else) branch.',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-4  Boot completes — direct route without re-showing splash
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-4: _bootComplete set on first full resolution; MainShell returned', () {
    // GIVEN all 7 providers resolve successfully
    // WHEN _RouteGuard.build() evaluates the gate order
    // THEN MainShell is returned and SplashScreen is gone
    testWidgets('renders MainShell after all providers resolve', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });
      const userId = 'user-abc-123';
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _AuthedAuthNotifier()),
        _showcaseSeenOverride,
        ..._allUserProvidersCleared(userId),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MainShell), findsOneWidget,
          reason: 'MainShell must be visible when all gates clear');
      expect(find.byType(SplashScreen), findsNothing,
          reason: 'SplashScreen must be removed once _bootComplete is true');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-5  Mid-session provider re-load — splash does NOT re-appear
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-5: mid-session AsyncLoading does not re-mount splash after _bootComplete',
      () {
    // GIVEN _bootComplete is true (MainShell showing)
    // WHEN trialStatusProvider is invalidated and re-enters AsyncLoading
    // THEN SplashScreen is NOT shown; MainShell remains
    testWidgets(
        'MainShell stays visible when trialStatusProvider re-enters loading after boot',
        (tester) async {
      const userId = 'user-abc-123';

      // Use a Completer so we can re-trigger loading after boot completes.
      var trialCallCount = 0;
      final secondCallCompleter = Completer<TrialStatus>();

      final container = ProviderContainer(overrides: [
        authProvider.overrideWith((ref) => _AuthedAuthNotifier()),
        _showcaseSeenOverride,
        hasPhoneProvider(userId).overrideWith((ref) async => true),
        joinedCitySlugsProvider(userId)
            .overrideWith((ref) async => ['valencia']),
        profileGateProvider(userId).overrideWith((ref) async => {
              'username': 'alice',
              'invited_at': '2025-01-01T00:00:00Z',
            }),
        missionStatusProvider(userId).overrideWith(
          (ref) async => MissionStatus(
            firstMissionCompletedAt: null,
            firstAttackCompletedAt: DateTime.fromMillisecondsSinceEpoch(1),
            zoneCount: 1,
          ),
        ),
        trialStatusProvider(userId).overrideWith((ref) async {
          trialCallCount++;
          if (trialCallCount == 1) {
            return const TrialStatus(started: false, daysRemaining: 14, streak: 0);
          }
          // Second call simulates re-fetch that takes a long time
          return await secondCallCompleter.future;
        }),
      ]);
      addTearDown(container.dispose);

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RunWarApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Sanity: boot completed, MainShell visible
      expect(find.byType(MainShell), findsOneWidget,
          reason: 'Sanity check: MainShell must be visible after boot');

      // Invalidate to re-trigger loading
      container.invalidate(trialStatusProvider(userId));
      await tester.pump();

      expect(find.byType(SplashScreen), findsNothing,
          reason:
              'SplashScreen must NOT re-appear after _bootComplete is true, '
              'even if trialStatusProvider is AsyncLoading again');
      expect(find.byType(MainShell), findsOneWidget,
          reason: 'MainShell must remain visible during mid-session provider reload');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-6  Provider error during boot — inline error overlay shown
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-6: provider error during boot shows _ErrorOverlay on top of SplashScreen',
      () {
    // GIVEN _bootComplete == false AND profileGateProvider returns an error
    // WHEN _RouteGuard.build() detects profileAsync.hasError
    // THEN SplashScreen remains; overlay shows 'PROFILE FAILED' / err text / 'TAP TO RETRY'
    testWidgets(
        'shows PROFILE FAILED overlay on SplashScreen when profileGateProvider errors',
        (tester) async {
      const userId = 'user-abc-123';
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _AuthedAuthNotifier()),
        _showcaseSeenOverride,
        hasPhoneProvider(userId).overrideWith((ref) async => true),
        joinedCitySlugsProvider(userId)
            .overrideWith((ref) async => ['valencia']),
        _profileErrorOverride(userId),
        missionStatusProvider(userId).overrideWith(
          (ref) async => MissionStatus(
            firstMissionCompletedAt: null,
            firstAttackCompletedAt: DateTime.fromMillisecondsSinceEpoch(1),
            zoneCount: 1,
          ),
        ),
        trialStatusProvider(userId).overrideWith(
          (ref) async =>
              const TrialStatus(started: false, daysRemaining: 14, streak: 0),
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsOneWidget,
          reason: 'SplashScreen must remain as background during error state');
      expect(find.text('PROFILE FAILED'), findsOneWidget,
          reason: 'Error overlay line 1 must read PROFILE FAILED');
      expect(find.text('TAP TO RETRY'), findsOneWidget,
          reason: 'Error overlay line 3 must read TAP TO RETRY');
    });

    // GIVEN an error during boot
    // WHEN the overlay is rendered
    // THEN Line 2 shows the error message truncated to ≤120 chars
    testWidgets('error overlay line 2 shows error message truncated to ≤120 chars',
        (tester) async {
      const userId = 'user-abc-123';
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _AuthedAuthNotifier()),
        _showcaseSeenOverride,
        hasPhoneProvider(userId).overrideWith((ref) async => true),
        joinedCitySlugsProvider(userId)
            .overrideWith((ref) async => ['valencia']),
        profileGateProvider(userId).overrideWith((ref) async {
          throw Exception('profile fetch failed');
        }),
        missionStatusProvider(userId).overrideWith(
          (ref) async => MissionStatus(
            firstMissionCompletedAt: null,
            firstAttackCompletedAt: DateTime.fromMillisecondsSinceEpoch(1),
            zoneCount: 1,
          ),
        ),
        trialStatusProvider(userId).overrideWith(
          (ref) async =>
              const TrialStatus(started: false, daysRemaining: 14, streak: 0),
        ),
      ]));
      await tester.pumpAndSettle();

      // Line 2 must contain the error message text
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is Text) {
            final data = widget.data ?? widget.textSpan?.toPlainText() ?? '';
            return data.contains('profile fetch failed');
          }
          return false;
        }),
        findsAtLeastNWidgets(1),
        reason: 'Error overlay line 2 must display the error message',
      );

      // No single Text widget in the overlay may exceed 120 chars
      final allTexts = tester.widgetList<Text>(find.byType(Text));
      for (final t in allTexts) {
        final data = t.data ?? t.textSpan?.toPlainText() ?? '';
        expect(data.length, lessThanOrEqualTo(120),
            reason: 'No overlay text line may exceed 120 characters');
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-7  Tap-to-retry invalidates failed provider
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-7: tapping error overlay invalidates the failed provider', () {
    // GIVEN error overlay visible for AUTH FAILED, retryCount < 3
    // WHEN user taps TAP TO RETRY
    // THEN provider re-enters loading; splash shows; TAP TO RETRY disappears
    testWidgets('tapping TAP TO RETRY re-enters loading state', (tester) async {
      int authCallCount = 0;
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) {
          authCallCount++;
          if (authCallCount == 1) {
            // First notifier: error state
            return _ErrorAuthNotifier();
          }
          // Subsequent: loading (never settles)
          return _LoadingAuthNotifier();
        }),
        _showcaseSeenOverride,
      ]));
      await tester.pumpAndSettle();

      expect(find.text('AUTH FAILED'), findsOneWidget,
          reason: 'AUTH FAILED overlay must appear after authProvider errors');
      expect(find.text('TAP TO RETRY'), findsOneWidget,
          reason: 'TAP TO RETRY must be visible when retryCount < 3');

      await tester.tap(find.text('TAP TO RETRY'));
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget,
          reason: 'SplashScreen must remain after retry tap');
      expect(find.text('TAP TO RETRY'), findsNothing,
          reason: 'TAP TO RETRY must disappear once loading resumes');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-8  Persistent error — taps disabled after 3 retries within 60 s
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-8: overlay becomes non-interactive after 3 retries within 60 s', () {
    // GIVEN same provider fails on every attempt
    // WHEN user taps TAP TO RETRY 3 times within 60 s
    // THEN overlay shows 'PERSISTENT ERROR — RELAUNCH APP' and 'TAP TO RETRY' is gone
    testWidgets(
        'shows PERSISTENT ERROR label and hides TAP TO RETRY after 3 retries',
        (tester) async {
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _ErrorAuthNotifier()),
        _showcaseSeenOverride,
      ]));

      for (var i = 0; i < 3; i++) {
        await tester.pumpAndSettle();
        final retryFinder = find.text('TAP TO RETRY');
        if (retryFinder.evaluate().isNotEmpty) {
          await tester.tap(retryFinder);
        }
      }
      await tester.pumpAndSettle();

      expect(find.text('PERSISTENT ERROR — RELAUNCH APP'), findsOneWidget,
          reason: 'After 3 retries the overlay must show PERSISTENT ERROR label');
      expect(find.text('TAP TO RETRY'), findsNothing,
          reason: 'TAP TO RETRY must be absent when overlay is locked');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-9  Multi-error — first overlay shown, subsequent errors logged silently
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-9: only the first failing provider overlay is shown', () {
    // GIVEN authProvider errors (first in watch order) AND profileGate also errors
    // WHEN _RouteGuard.build() processes both errors
    // THEN only 'AUTH FAILED' overlay is shown; 'PROFILE FAILED' is not visible
    testWidgets(
        'shows AUTH FAILED only when both authProvider and profileGateProvider error',
        (tester) async {
      const userId = 'user-abc-123';
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _ErrorAuthNotifier()),
        _showcaseSeenOverride,
        hasPhoneProvider(userId).overrideWith((ref) async => true),
        joinedCitySlugsProvider(userId)
            .overrideWith((ref) async => ['valencia']),
        _profileErrorOverride(userId),
        missionStatusProvider(userId).overrideWith(
          (ref) async => MissionStatus(
            firstMissionCompletedAt: null,
            firstAttackCompletedAt: DateTime.fromMillisecondsSinceEpoch(1),
            zoneCount: 1,
          ),
        ),
        trialStatusProvider(userId).overrideWith(
          (ref) async =>
              const TrialStatus(started: false, daysRemaining: 14, streak: 0),
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('AUTH FAILED'), findsOneWidget,
          reason: 'First-failing provider overlay must be shown');
      expect(find.text('PROFILE FAILED'), findsNothing,
          reason: 'Second-failing provider must not appear as a second overlay');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-10  showcaseSeenProvider error — tap-to-retry overlay shown
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-10: showcaseSeenProvider error shows tap-to-retry overlay', () {
    // GIVEN user == null AND showcaseSeenProvider errors
    // WHEN _RouteGuard.build() detects showcaseSeenAsync.hasError
    // THEN SplashScreen holds; overlay shows 'SHOWCASE SEEN FAILED' / 'TAP TO RETRY'
    //   AND no routing to LoginScreen or IntroScreen occurs
    testWidgets(
        'shows SHOWCASE SEEN FAILED overlay when showcaseSeenProvider errors',
        (tester) async {
      await tester.pumpWidget(_scope([
        authProvider.overrideWith((ref) => _UnauthAuthNotifier()),
        _showcaseErrorOverride,
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsOneWidget,
          reason: 'SplashScreen must hold while showcaseSeenProvider is in error');
      expect(find.text('SHOWCASE SEEN FAILED'), findsOneWidget,
          reason: 'Overlay line 1 must read SHOWCASE SEEN FAILED');
      expect(find.text('TAP TO RETRY'), findsOneWidget,
          reason: 'Overlay line 3 must read TAP TO RETRY');
      expect(find.byType(LoginScreen), findsNothing,
          reason: 'LoginScreen must NOT appear while error overlay is shown');
      expect(find.byType(IntroScreen), findsNothing,
          reason: 'IntroScreen must NOT appear while error overlay is shown');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-11  _GateLoading class deleted
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-11: _GateLoading class does not exist in main.dart', () {
    // GIVEN the feature branch is applied to main.dart
    // WHEN the file is searched for '_GateLoading'
    // THEN zero matches are found
    test('main.dart contains no _GateLoading class declaration', () {
      // Resolve main.dart relative to the test runner's working directory.
      // flutter test runs from the package root (runwar_app/).
      final mainDart = File('lib/main.dart');
      expect(mainDart.existsSync(), isTrue,
          reason: 'lib/main.dart must exist');
      final content = mainDart.readAsStringSync();
      expect(content.contains('class _GateLoading'), isFalse,
          reason:
              '_GateLoading class declaration must not exist in main.dart after deletion');
      expect(content.contains('_GateLoading('), isFalse,
          reason: 'No call site for _GateLoading() must remain in main.dart');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-12  ErrorLogService.logClientError never throws
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-12: ErrorLogService.logClientError never throws', () {
    // GIVEN the edge function is unreachable
    // WHEN logClientError is called
    // THEN the method returns without throwing
    test('logClientError returns normally when Supabase is unreachable',
        () async {
      expect(
        () async => ErrorLogService.logClientError(
          provider: 'authProvider',
          error: Exception('network offline'),
          stackTrace: StackTrace.current,
          retryCount: 0,
          userId: null,
        ),
        returnsNormally,
        reason:
            'logClientError must never throw, even when Supabase is unreachable',
      );
    });

    // GIVEN logClientError is called with valid args
    // WHEN the returned Future completes
    // THEN no exception propagates to the caller
    test('logClientError future completes without error (fire-and-forget)',
        () async {
      await expectLater(
        ErrorLogService.logClientError(
          provider: 'profileGateProvider',
          error: StateError('something broke'),
          stackTrace: StackTrace.current,
          retryCount: 2,
          userId: 'user-abc-123',
        ),
        completes,
        reason:
            'logClientError must return a completed Future and never throw',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // AC-13  Required new files exist (structural gate for flutter analyze)
  // ──────────────────────────────────────────────────────────────────────────
  group('AC-13: required new files exist for flutter analyze to pass', () {
    // GIVEN the feature branch is applied
    // WHEN file existence is checked
    // THEN all new files are present

    test('lib/services/error_log_service.dart exists', () {
      expect(File('lib/services/error_log_service.dart').existsSync(), isTrue,
          reason: 'error_log_service.dart must be created at lib/services/');
    });

    test('client_errors migration exists in runwar_database/supabase/migrations/', () {
      final migrationsDir = Directory(
        '../runwar_database/supabase/migrations',
      );
      final files = migrationsDir.existsSync()
          ? migrationsDir
              .listSync()
              .map((e) => e.path.split('/').last)
              .toList()
          : <String>[];
      expect(
        files.any((name) => name.contains('client_errors')),
        isTrue,
        reason: 'A migration file containing client_errors must exist',
      );
    });

    test('log_client_error edge function index.ts exists', () {
      expect(
        File('../runwar_database/supabase/functions/log_client_error/index.ts')
            .existsSync(),
        isTrue,
        reason: 'log_client_error/index.ts edge function must be created',
      );
    });
  });
}

// ── Additional stub — AuthNotifier that emits an error state ─────────────────

/// AuthNotifier that immediately emits an error state.
/// Used for AC-7, AC-8, AC-9 tests where auth failure must be visible.
class _ErrorAuthNotifier extends AuthNotifier {
  _ErrorAuthNotifier() : super(AuthService.instance) {
    state = const AuthState(error: 'auth network error');
  }

  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
}
