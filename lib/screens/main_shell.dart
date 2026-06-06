import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../providers/trust/challenge_providers.dart';
import '../providers/daily_missions_provider.dart';
import '../services/database/challenges_repository.dart';
import '../services/database_service.dart';
import '../services/supabase_service.dart';
import '../services/realtime_presence_service.dart';
import '../services/ctf_service.dart';
import '../services/fcm_service.dart';
import '../models/daily_mission.dart';
import '../services/daily_missions_service.dart';
import '../services/streak_reminder_scheduler.dart';
import '../services/telemetry_service.dart';
import '../widgets/daily_login_modal.dart';
import '../widgets/milestone_reward_modal.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'verification_challenge_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initServices();
      // Show daily login modal on first frame (cold launch resume).
      _maybeShowDailyLoginModal();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    _maybeShowDailyLoginModal();
  }

  Future<void> _maybeShowDailyLoginModal() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final shown = prefs.getString('daily_login_modal_shown_date') ?? '';
    if (!DailyMissionsService.instance.shouldShowDailyLoginModal(shown)) return;

    // Write pref BEFORE the async edge-function call (FR-10 / design.md §4).
    await prefs.setString('daily_login_modal_shown_date', today);

    final userId = ref.read(authProvider).user?['id'] as String?;
    if (userId == null) return;

    RecordDailyLoginResult result;
    try {
      result = await DailyMissionsService.instance.recordDailyLogin(userId);
    } catch (_) {
      return;
    }

    TelemetryService.instance.logEvent(
      'daily_login_modal_shown',
      props: {'streak': result.streak},
    );

    widgetRefInvalidateDailyState(ref, userId);

    if (!mounted) return;

    // Fetch today's slate to display in the modal (best-effort).
    final missions = await DailyMissionsService.instance
        .getTodaysMissions(userId)
        .catchError((_) => <DailyMission>[]);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => DailyLoginModal(
        userId: userId,
        missions: missions,
        streak: result.streak,
      ),
    );

    if (!mounted) return;

    if (result.milestoneUnlocked != null) {
      final milestone = result.milestoneUnlocked!;
      TelemetryService.instance.logEvent(
        'milestone_reward_shown',
        props: {'day': milestone.day},
      );

      // Fetch subscription tier for paywall gating in the modal.
      final streak = ref.read(dailyStreakProvider(userId)).valueOrNull;
      final subscriptionTier = streak?.subscriptionTier ?? 'free';

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => MilestoneRewardModal(
          day: milestone.day,
          creditsAwarded: milestone.credits,
          powerGranted: milestone.power,
          subscriptionTier: subscriptionTier,
        ),
      );
    }

    await StreakReminderScheduler.scheduleOrCancel(
      currentStreak: result.streak,
      lastLoginAt: result.longestStreak > 0 ? DateTime.now() : null,
    );
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _initServices() async {
    if (!SupabaseService.instance.isConnected) return;
    final userId = ref.read(authProvider).user?['id'] as String?;
    if (userId == null) return;
    final profile = await DatabaseService.instance.getProfile(userId);
    if (profile == null) return;
    RealtimePresenceService.instance.init(
      playerId: userId,
      displayName: (profile['username'] as String?) ?? 'RUNNER',
      color: (profile['color'] as String?) ?? '#FF7A00',
    );
    await CtfService.instance.init(playerId: userId);
    await FcmService.instance.init(playerId: userId);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authProvider).user?['id'] as String?;

    // P3: Challenge listener — show dialog when a new open challenge arrives.
    if (userId != null && SupabaseService.instance.isConnected) {
      ref.listen<AsyncValue<Challenge?>>(
        openChallengeProvider(userId),
        (prev, next) {
          next.whenData((challenge) {
            final hadChallenge = prev?.value != null;
            if (challenge != null && !hadChallenge) {
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Verification Required'),
                  content: const Text(
                    'A motion challenge has been issued. Complete it to resume claiming territory.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Later'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VerificationChallengeScreen(
                              challengeId: challenge.id,
                              playerId: userId,
                            ),
                          ),
                        );
                      },
                      child: const Text('Verify Now'),
                    ),
                  ],
                ),
              );
            }
          });
        },
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      // AC-14: IndexedStack keeps both children mounted across tab switches
      // so MapScreen state and zonesProvider subscription survive switching.
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          MapScreen(),
          ProfileScreen(),
        ],
      ),
      // AC-12, AC-15: exactly two tabs; active = kAccent, inactive = kFgMuted.
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: kBg,
        selectedItemColor: kAccent,
        unselectedItemColor: kFgMuted,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
