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
import 'screens/waitlist_gate_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
  try {
    await initLocalNotifications();
    await DatabaseService.instance.init();
    await AuthService.instance.seedDemoDataIfNeeded();
    // Supabase init must run before runApp so isConnected is ready for providers.
    await SupabaseService.instance.init();
    // Establish Supabase anon session for DB/Realtime access.
    // Do NOT create a local SQLite user here — let the login screen handle auth.
    await SupabaseService.instance.signIn();
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

/// Route guard — watches [authProvider] and [profileGateProvider] reactively.
/// Re-evaluates on every auth state change without requiring an app restart.
/// Logic mirrors the Spec 1 FutureBuilder-based _resolve():
///   user == null          → LoginScreen
///   invited_at == null    → WaitlistGateScreen
///   username == ''        → OnboardingFlow
///   otherwise             → MainShell
class _RouteGuard extends ConsumerWidget {
  const _RouteGuard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authState.user == null) {
      return const LoginScreen();
    }

    final userId = authState.user!['id'] as String;
    final profileAsync = ref.watch(profileGateProvider(userId));

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error loading profile: $e'))),
      data: (profile) {
        // invited_at == null → waiting for invite
        if (profile == null || profile['invited_at'] == null) {
          return const WaitlistGateScreen();
        }
        // username empty → onboarding incomplete
        final username = (profile['username'] as String?) ?? '';
        if (username.isEmpty) {
          return const OnboardingFlow();
        }
        return const MainShell();
      },
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
