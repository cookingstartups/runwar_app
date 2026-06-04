import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/fcm_service.dart';

import 'theme.dart';
import 'services/database_service.dart';
import 'services/supabase_service.dart';
import 'services/territory_service.dart';
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
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/main_shell.dart';
import 'screens/paywall_screen.dart';
import 'screens/first_mission_briefing_screen.dart';
import 'screens/first_attack_briefing_screen.dart';
import 'providers/cities_provider.dart';
import 'providers/mission_provider.dart';
import 'providers/daily_missions_provider.dart';
import 'services/streak_reminder_scheduler.dart';
import 'services/trial_service.dart';
import 'services/run_recovery_service.dart';
import 'screens/recovery_gate.dart';

final showcaseSeenProvider = FutureProvider<bool>((ref) => isShowcaseSeen());

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
    await DatabaseService.instance.init();
    // Sweep stale run_scratch rows (>12h old) before auth resolves (AC-11).
    await RunRecoveryService.instance.sweepStale();
    await AuthService.instance.seedDemoDataIfNeeded();
    // Supabase init must run before runApp so isConnected is ready for providers.
    await SupabaseService.instance.init();
    // Establish Supabase anon session for DB/Realtime access.
    // Do NOT create a local SQLite user here — let the login screen handle auth.
    await SupabaseService.instance.signIn();
    // Restore in-memory session from persisted Supabase session (e.g. Google sign-in).
    await AuthService.instance.restoreSessionFromSupabase();
    debugPrint('[main] isConnected=${SupabaseService.instance.isConnected} session=${SupabaseService.instance.supabase.auth.currentSession?.user.id}');
    // Presence + CTF init deferred to MainShell (after login provides profile data).
    await TerritoryService.instance.runDailyDecayIfDue('Valencia');
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
/// Gate order:
///   user == null          → LoginScreen / IntroScreen
///   no phone linked       → PhoneLinkScreen
///   no cities joined      → CitiesSelectionScreen
///   invited_at == null    → JoinWarConfirmationScreen (waitlisted)
///   username == ''        → OnboardingFlow
///   trial expired         → PaywallScreen
///   otherwise             → MainShell
class _RouteGuard extends ConsumerStatefulWidget {
  const _RouteGuard();

  @override
  ConsumerState<_RouteGuard> createState() => _RouteGuardState();
}

class _RouteGuardState extends ConsumerState<_RouteGuard>
    with WidgetsBindingObserver {
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading) return const _GateLoading();

    if (authState.user == null) {
      final showcaseSeen = ref.watch(showcaseSeenProvider);
      return showcaseSeen.when(
        loading: () => const _GateLoading(),
        error: (_, __) => const LoginScreen(),
        data: (seen) => seen ? const LoginScreen() : const IntroScreen(),
      );
    }

    final userId = authState.user!['id'] as String;

    // Gate 1: phone linked?
    final hasPhoneAsync = ref.watch(hasPhoneProvider(userId));
    if (hasPhoneAsync.isLoading) return const _GateLoading();
    if (!(hasPhoneAsync.value ?? true)) return const PhoneLinkScreen();

    // Gate 2: any cities joined?
    final joinedAsync = ref.watch(joinedCitySlugsProvider(userId));
    if (joinedAsync.isLoading) return const _GateLoading();
    if ((joinedAsync.value ?? []).isEmpty) return const CitiesSelectionScreen();

    // Gate 3: profile + invited_at + username
    final profileAsync = ref.watch(profileGateProvider(userId));
    if (profileAsync.isLoading) {
      return const SplashScreen(
          showStatus: true, statusLabel: 'SYNCING TERRITORY');
    }
    if (profileAsync.hasError) {
      return Scaffold(
          body: Center(
              child: Text('Error loading profile: ${profileAsync.error}')));
    }
    final profile = profileAsync.value;
    if (profile == null || profile['invited_at'] == null) {
      return const JoinWarConfirmationScreen();
    }
    final username = (profile['username'] as String?) ?? '';
    if (username.isEmpty) return const OnboardingFlow();

    // Gate 5a: first-mission onboarding
    final missionAsync = ref.watch(missionStatusProvider(userId));
    if (missionAsync.isLoading) return const _GateLoading();
    final mission = missionAsync.value;
    if (mission != null && mission.needsMission1) {
      return const FirstMissionBriefingScreen();
    }
    if (mission != null && mission.needsMission2) {
      return const FirstAttackBriefingScreen(botZoneId: '');
    }

    // Gate 4: trial expired?
    final trialAsync = ref.watch(trialStatusProvider(userId));
    if (trialAsync.isLoading) return const _GateLoading();
    final trial = trialAsync.value;
    if (trial != null && trial.isExpired) {
      return PaywallScreen(streak: trial.streak);
    }

    return RecoveryGate(userId: userId, child: const MainShell());
  }
}

/// Minimal dark loading screen shown during route gate state checks.
/// Replaces the full SplashScreen to avoid jarring re-renders mid-auth.
class _GateLoading extends StatelessWidget {
  const _GateLoading();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: kAccent,
              strokeWidth: 1.5,
            ),
          ),
        ),
      );
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
