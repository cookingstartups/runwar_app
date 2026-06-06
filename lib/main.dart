import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/fcm_service.dart';

import 'theme.dart';
import 'services/database_service.dart';
import 'services/supabase_service.dart';
import 'services/territory_service.dart';
import 'services/error_log_service.dart';
import 'providers/auth_provider.dart';
import 'services/auth_service.dart';
import 'providers/profile_provider.dart';
import 'providers/run_recorder_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/request_access_screen.dart';
import 'screens/success_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/phone_link_screen.dart';
import 'screens/auth/cities_selection_screen.dart';
import 'screens/auth/join_war_confirmation_screen.dart';
// import 'screens/waitlist_gate_screen.dart'; // kept for named route fallback
import 'screens/onboarding/sign_up_flow.dart';
import 'screens/main_shell.dart';
import 'screens/paywall_screen.dart';
import 'screens/first_mission_briefing_screen.dart';
import 'screens/first_attack_briefing_screen.dart';
import 'screens/map_screen.dart';
import 'models/mission_step.dart';
import 'providers/cities_provider.dart';
import 'providers/mission_provider.dart';
import 'providers/daily_missions_provider.dart';
import 'services/streak_reminder_scheduler.dart';
import 'services/trial_service.dart';
import 'services/run_recovery_service.dart';
import 'screens/recovery_gate.dart';
import 'providers/showcase_provider.dart';

/// Runs the daily trial tick then returns current trial status.
/// Re-evaluated on app foreground via _RouteGuard's WidgetsBindingObserver.
final trialStatusProvider =
    FutureProvider.family<TrialStatus, String>((ref, userId) async {
  await TrialService.instance.processDailyTick(userId);
  return TrialService.instance.getStatus(userId);
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StreakReminderScheduler.ensureTimezoneInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
  try {
    await initLocalNotifications();
    // Supabase must init first — DatabaseService and all callers use Supabase.instance.client.
    await SupabaseService.instance.init();
    await DatabaseService.instance.init();
    // Restore persisted Supabase session (Google sign-in). No-op if not authenticated.
    await SupabaseService.instance.signIn();
    // Restore in-memory session from persisted Supabase session (e.g. Google sign-in).
    await AuthService.instance.restoreSessionFromSupabase();
    // Sweep stale run_scratch rows (>12h old) before auth resolves (AC-11).
    await RunRecoveryService.instance.sweepStale();
    final sessionUserId = SupabaseService.instance.supabase.auth.currentSession?.user.id;
    debugPrint('[main] isConnected=${SupabaseService.instance.isConnected} session=$sessionUserId');
    // Demo seed + daily decay only make sense once a real user session exists.
    // Without a session, RLS blocks anon writes and seedDemoData is a wasted
    // round-trip on every cold boot of an unauthenticated app.
    if (sessionUserId != null) {
      try {
        await AuthService.instance.seedDemoDataIfNeeded();
      } catch (e) {
        debugPrint('[main] seedDemoData skipped: $e');
      }
      await TerritoryService.instance.runDailyDecayIfDue('Valencia', sessionUserId);
    }
  } catch (e) {
    runApp(_InitErrorApp(error: e.toString()));
    return;
  }
  runApp(const ProviderScope(child: RunWarApp()));
}

class RunWarApp extends StatelessWidget {
  const RunWarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RunWar',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // INVARIANT: _RouteGuard is the MaterialApp home and must never be replaced or
      // popped via Navigator.pushReplacement* or Navigator.pop. It manages all navigation
      // reactively by returning different widgets. To "navigate" to a new screen, change
      // provider state (e.g. ref.invalidate(showcaseSeenProvider)) — do NOT push a named route.
      home: const _RouteGuard(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const SplashScreen());
          case '/intro':
            return MaterialPageRoute(builder: (_) => const IntroScreen());
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginScreen());
          case '/request-access':
            final ref = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (_) => RequestAccessScreen(referralRef: ref),
            );
          case '/success':
            final args = settings.arguments as SuccessArgs;
            return MaterialPageRoute(
              builder: (_) => SuccessScreen(args: args),
            );
          default:
            return MaterialPageRoute(builder: (_) => const SplashScreen());
        }
      },
    );
  }
}

/// Route guard — watches auth + profile state reactively.
///
/// Boot sequence:
///   Phase A (unconditional): authProvider, showcaseSeenProvider
///   Phase B (when userId != null): hasPhoneProvider, joinedCitySlugsProvider,
///     profileGateProvider, missionStatusProvider, trialStatusProvider
///
/// All applicable providers are watched in parallel within the same build()
/// call so their async fetches initiate concurrently.
///
/// A single SplashScreen(showStatus: true, statusLabel: 'SYNCING TERRITORY')
/// is held until ALL applicable providers have resolved. Once _bootComplete is
/// set to true, the splash never re-appears even on mid-session invalidation.
///
/// Gate order:
///   user == null          → LoginScreen / IntroScreen
///   no phone linked       → PhoneLinkScreen
///   no cities joined      → CitiesSelectionScreen
///   username == ''        → SignUpFlow
///   invited_at == null    → JoinWarConfirmationScreen (waitlisted)
///   mission 1 pending     → FirstMissionBriefingScreen
///   mission 2 pending     → FirstAttackBriefingScreen
///   trial expired         → PaywallScreen
///   otherwise             → MainShell
class _RouteGuard extends ConsumerStatefulWidget {
  const _RouteGuard();

  @override
  ConsumerState<_RouteGuard> createState() => _RouteGuardState();
}

class _RouteGuardState extends ConsumerState<_RouteGuard>
    with WidgetsBindingObserver {
  // Set to true on the first frame all applicable providers have resolved.
  // Never reset — prevents splash re-appearing on mid-session invalidation.
  bool _bootComplete = false;

  // Retry state keyed by provider machine name.
  final Map<String, int> _retryCount = {};
  final Map<String, DateTime> _firstFailureAt = {};
  final Map<String, Object> _lastError = {};
  final Map<String, StackTrace> _lastStackTrace = {};

  // Tracks which provider's overlay is currently visible (first-failure wins).
  String? _activeOverlayProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final userId =
          ref.read(authProvider).user?['id'] as String?;
      if (userId != null) {
        ref.invalidate(trialStatusProvider(userId));
        ref.invalidate(missionStatusProvider(userId));
        ref.invalidate(todaysMissionsProvider(userId));
        ref.invalidate(dailyStreakProvider(userId));
      }
      final streak = ref.read(dailyStreakProvider(userId ?? '')).valueOrNull;
      if (streak != null) {
        StreakReminderScheduler.scheduleOrCancel(
          currentStreak: streak.current,
          lastLoginAt: streak.lastLoginAt,
        ).catchError((_) {});
      }
    }
  }

  // ── Retry / lockout helpers ──────────────────────────────────────────────

  bool _isLocked(String providerName) {
    final count = _retryCount[providerName] ?? 0;
    final first = _firstFailureAt[providerName];
    if (count < 3 || first == null) return false;
    return DateTime.now().difference(first) <
        const Duration(seconds: 60);
  }

  void _recordError(
    String providerName,
    Object error,
    StackTrace stackTrace,
    String? userId,
  ) {
    _lastError[providerName] = error;
    _lastStackTrace[providerName] = stackTrace;

    if (_activeOverlayProvider == null) {
      // First failure — show this one.
      _activeOverlayProvider = providerName;
      ErrorLogService.logClientError(
        provider: providerName,
        error: error,
        stackTrace: stackTrace,
        retryCount: _retryCount[providerName] ?? 0,
        userId: userId,
      );
    } else if (_activeOverlayProvider != providerName) {
      // Subsequent failure from a different provider — log silently only.
      ErrorLogService.logClientError(
        provider: providerName,
        error: error,
        stackTrace: stackTrace,
        retryCount: _retryCount[providerName] ?? 0,
        userId: userId,
      );
    }
  }

  void _onRetry(String providerName, void Function() invalidateFn) {
    if (_isLocked(providerName)) return;
    _retryCount[providerName] = (_retryCount[providerName] ?? 0) + 1;
    _firstFailureAt.putIfAbsent(providerName, () => DateTime.now());
    // Clear active overlay so a fresh error on re-fetch can re-set it.
    _activeOverlayProvider = null;
    // Invalidate first so the provider's new state is visible in the build
    // triggered by setState below.
    invalidateFn();
    // Force a rebuild to pick up the updated retry count even when the
    // provider re-emits an identical const state (Riverpod skips notification
    // for unchanged state — e.g. const AuthState(error: '...')).
    setState(() {});

    // Log the retry attempt.
    if (_lastError.containsKey(providerName)) {
      ErrorLogService.logClientError(
        provider: providerName,
        error: _lastError[providerName]!,
        stackTrace: _lastStackTrace[providerName]!,
        retryCount: _retryCount[providerName]!,
        userId: ref.read(authProvider).user?['id'] as String?,
      );
    }
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ── Phase A: unconditional providers ──────────────────────────────────
    final authState = ref.watch(authProvider);
    final showcaseAsync = ref.watch(showcaseSeenProvider);

    // Extract userId without await — null when auth is loading or unauthenticated.
    final userId = authState.user?['id'] as String?;

    // ── Phase B: userId-scoped providers (only when userId is known) ───────
    final hasPhoneAsync = userId != null
        ? ref.watch(hasPhoneProvider(userId))
        : null;
    final joinedAsync = userId != null
        ? ref.watch(joinedCitySlugsProvider(userId))
        : null;
    final profileAsync = userId != null
        ? ref.watch(profileGateProvider(userId))
        : null;
    final missionAsync = userId != null
        ? ref.watch(missionStatusProvider(userId))
        : null;
    final trialAsync = userId != null
        ? ref.watch(trialStatusProvider(userId))
        : null;

    // ── Aggregate loading state ───────────────────────────────────────────
    final authLoading = authState.isLoading;
    final anyLoading = authLoading ||
        showcaseAsync.isLoading ||
        (userId != null &&
            (hasPhoneAsync!.isLoading ||
                joinedAsync!.isLoading ||
                profileAsync!.isLoading ||
                missionAsync!.isLoading ||
                trialAsync!.isLoading));

    // ── Error detection — collect the first error during boot ─────────────
    if (!_bootComplete) {
      _detectErrors(
        authState: authState,
        showcaseAsync: showcaseAsync,
        userId: userId,
        hasPhoneAsync: hasPhoneAsync,
        joinedAsync: joinedAsync,
        profileAsync: profileAsync,
        missionAsync: missionAsync,
        trialAsync: trialAsync,
      );
    }

    final anyError = !_bootComplete && _activeOverlayProvider != null;

    // ── Boot-complete flag: set on first full resolution ──────────────────
    if (!anyLoading && !anyError && !_bootComplete) {
      _bootComplete = true;
    }

    // ── Splash guard ──────────────────────────────────────────────────────
    // Hold splash while booting AND any provider is still loading or errored.
    // Once _bootComplete is true, this block is never entered again.
    if (!_bootComplete && (anyLoading || anyError)) {
      const splash = SplashScreen(
          showStatus: true, statusLabel: 'SYNCING TERRITORY');

      if (anyError && _activeOverlayProvider != null) {
        return _buildSplashWithOverlay(splash, userId);
      }
      return splash;
    }

    // ── Gate routing order ────────────────────────────────────────────────

    // Gate 0: auth
    if (authState.user == null) {
      final seen = showcaseAsync.valueOrNull ?? false;
      return seen ? const LoginScreen() : const IntroScreen();
    }

    final uid = authState.user!['id'] as String;

    // Gate 1: phone linked?
    if (!(hasPhoneAsync?.value ?? true)) return const PhoneLinkScreen();

    // Gate 2: any cities joined?
    if ((joinedAsync?.value ?? []).isEmpty) return const CitiesSelectionScreen();

    // Gate 3: profile + invited_at + username
    final profile = profileAsync?.value;
    final username = (profile?['username'] as String?) ?? '';
    if (profile == null || username.isEmpty) return const SignUpFlow();
    if (profile['invited_at'] == null) {
      return const JoinWarConfirmationScreen();
    }

    // Gate 5a: first-mission onboarding
    final mission = missionAsync?.value;
    if (mission != null && mission.needsMission1) {
      final accepted = ref.watch(mission1BriefingAcceptedProvider);
      if (!accepted) return const FirstMissionBriefingScreen();
      return const MapScreen(missionStep: MissionStep.mission1Claim);
    }

    // Gate 5b: second-mission onboarding
    if (mission != null && mission.needsMission2) {
      final accepted = ref.watch(mission2BriefingAcceptedProvider);
      if (!accepted) {
        // TODO(mission2-polish): pendingBotZoneIdProvider — see design.md §5.
        //                        Empty string is acceptable per AC-7 edge case.
        return const FirstAttackBriefingScreen(botZoneId: '');
      }
      // TODO(mission2-polish): pendingBotZoneIdProvider — see design.md §5.
      //                        Empty string is acceptable per AC-7 edge case.
      return const MapScreen(
        missionStep: MissionStep.mission2Attack,
        botZoneId: '',
      );
    }

    // Gate 4: trial expired?
    final trial = trialAsync?.value;
    if (trial != null && trial.isExpired) {
      return PaywallScreen(streak: trial.streak);
    }

    return RecoveryGate(userId: uid, child: const MainShell());
  }

  // ── Error detection helper ───────────────────────────────────────────────

  void _detectErrors({
    required AuthState authState,
    required AsyncValue<bool> showcaseAsync,
    required String? userId,
    required AsyncValue<bool>? hasPhoneAsync,
    required AsyncValue<List<String>>? joinedAsync,
    required AsyncValue<Map<String, dynamic>?>? profileAsync,
    required AsyncValue<MissionStatus?>? missionAsync,
    required AsyncValue<TrialStatus>? trialAsync,
  }) {
    final currentUserId = userId;

    // authProvider error (AuthState.error is a String, not AsyncValue).
    if (authState.error != null) {
      _recordError(
        'authProvider',
        Exception(authState.error),
        StackTrace.empty,
        currentUserId,
      );
    }

    // showcaseSeenProvider error.
    if (showcaseAsync.hasError) {
      _recordError(
        'showcaseSeenProvider',
        showcaseAsync.error!,
        showcaseAsync.stackTrace ?? StackTrace.empty,
        currentUserId,
      );
    }

    if (userId == null) return;

    if (hasPhoneAsync != null && hasPhoneAsync.hasError) {
      _recordError(
        'hasPhoneProvider',
        hasPhoneAsync.error!,
        hasPhoneAsync.stackTrace ?? StackTrace.empty,
        currentUserId,
      );
    }

    if (joinedAsync != null && joinedAsync.hasError) {
      _recordError(
        'joinedCitySlugsProvider',
        joinedAsync.error!,
        joinedAsync.stackTrace ?? StackTrace.empty,
        currentUserId,
      );
    }

    if (profileAsync != null && profileAsync.hasError) {
      _recordError(
        'profileGateProvider',
        profileAsync.error!,
        profileAsync.stackTrace ?? StackTrace.empty,
        currentUserId,
      );
    }

    if (missionAsync != null && missionAsync.hasError) {
      _recordError(
        'missionStatusProvider',
        missionAsync.error!,
        missionAsync.stackTrace ?? StackTrace.empty,
        currentUserId,
      );
    }

    if (trialAsync != null && trialAsync.hasError) {
      _recordError(
        'trialStatusProvider',
        trialAsync.error!,
        trialAsync.stackTrace ?? StackTrace.empty,
        currentUserId,
      );
    }
  }

  // ── Overlay builder ──────────────────────────────────────────────────────

  Widget _buildSplashWithOverlay(Widget splash, String? userId) {
    final providerName = _activeOverlayProvider!;
    final locked = _isLocked(providerName);

    // Build display label from machine name.
    final label = _providerLabel(providerName);

    final errorObj = _lastError[providerName] ?? Exception('unknown error');
    final rawMsg = errorObj.toString();
    final message = rawMsg.length > 120 ? rawMsg.substring(0, 120) : rawMsg;

    return Stack(
      children: [
        splash,
        _ErrorOverlay(
          label: label,
          message: message,
          isLocked: locked,
          onRetry: locked
              ? null
              : () => _onRetry(
                    providerName,
                    () => _invalidateProvider(providerName, userId),
                  ),
        ),
      ],
    );
  }

  void _invalidateProvider(String providerName, String? userId) {
    switch (providerName) {
      case 'authProvider':
        ref.invalidate(authProvider);
      case 'showcaseSeenProvider':
        ref.invalidate(showcaseSeenProvider);
      case 'hasPhoneProvider':
        if (userId != null) ref.invalidate(hasPhoneProvider(userId));
      case 'joinedCitySlugsProvider':
        if (userId != null) ref.invalidate(joinedCitySlugsProvider(userId));
      case 'profileGateProvider':
        if (userId != null) ref.invalidate(profileGateProvider(userId));
      case 'missionStatusProvider':
        if (userId != null) ref.invalidate(missionStatusProvider(userId));
      case 'trialStatusProvider':
        if (userId != null) ref.invalidate(trialStatusProvider(userId));
    }
  }

  static String _providerLabel(String providerName) {
    switch (providerName) {
      case 'authProvider':
        return 'AUTH FAILED';
      case 'showcaseSeenProvider':
        return 'SHOWCASE SEEN FAILED';
      case 'hasPhoneProvider':
        return 'PHONE CHECK FAILED';
      case 'joinedCitySlugsProvider':
        return 'CITIES FAILED';
      case 'profileGateProvider':
        return 'PROFILE FAILED';
      case 'missionStatusProvider':
        return 'MISSION STATUS FAILED';
      case 'trialStatusProvider':
        return 'TRIAL STATUS FAILED';
      default:
        return '${providerName.toUpperCase()} FAILED';
    }
  }
}

// ── _ErrorOverlay ────────────────────────────────────────────────────────────

/// Inline three-line error overlay composed on top of SplashScreen.
///
/// Line 1: `<PROVIDER_LABEL> FAILED` — white, 13pt (locked: PERSISTENT ERROR)
/// Line 2: error message truncated to 120 chars — white 60% alpha, 11pt
/// Line 3: `TAP TO RETRY` — accent, 12pt (hidden when locked)
class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.label,
    required this.message,
    required this.isLocked,
    required this.onRetry,
  });

  final String label;
  final String message;
  final bool isLocked;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: GestureDetector(
          onTap: isLocked ? null : onRetry,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLocked ? 'PERSISTENT ERROR — RELAUNCH APP' : label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (!isLocked) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'TAP TO RETRY',
                    style: TextStyle(
                      color: kAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InitErrorApp extends StatelessWidget {
  const _InitErrorApp({required this.error});
  final String error;
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Database init failed:\n\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
