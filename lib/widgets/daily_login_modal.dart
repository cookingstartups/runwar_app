import 'package:flutter/material.dart';

import '../models/daily_mission.dart';
import '../services/daily_missions_service.dart';
import '../services/telemetry_service.dart';
import '../theme.dart';

/// Full-screen modal shown once per day on first app foreground.
/// Displays the current streak and today's mission slate with a "LET'S GO" CTA.
///
/// On CTA tap or dismiss, calls
/// [DailyMissionsService.instance.recordDailyLogin] (already called by the
/// trigger in main_shell) and updates the shown-date preference there.
/// This widget only handles UI — the preference guard lives in
/// [_MainShellState._maybeShowDailyLoginModal].
class DailyLoginModal extends StatefulWidget {
  const DailyLoginModal({
    required this.userId,
    required this.missions,
    required this.streak,
    super.key,
  });

  final String userId;
  final List<DailyMission> missions;
  final int streak;

  @override
  State<DailyLoginModal> createState() => _DailyLoginModalState();
}

class _DailyLoginModalState extends State<DailyLoginModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    // Telemetry — fired once on show.
    TelemetryService.instance.logEvent(
      'daily_login_modal_shown',
      props: {'streak': widget.streak},
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Container(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Streak headline
                    Text(
                      'DAY ${widget.streak}',
                      textAlign: TextAlign.center,
                      style: displayStyle(size: 64, color: kAccent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'STREAK',
                      textAlign: TextAlign.center,
                      style: monoStyle(size: 12, color: kFgMuted),
                    ),
                    const SizedBox(height: 28),
                    // Divider
                    Container(height: 1, color: kBorder),
                    const SizedBox(height: 20),
                    Text(
                      "TODAY'S MISSIONS",
                      style: monoStyle(size: 10, color: kFgMuted),
                    ),
                    const SizedBox(height: 12),
                    // Mission list
                    if (widget.missions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Loading missions…',
                          style: bodyStyle(size: 13, color: kFgMuted),
                        ),
                      )
                    else
                      for (final m in widget.missions) ...[
                        _MissionRow(mission: m),
                        const SizedBox(height: 8),
                      ],
                    const SizedBox(height: 24),
                    // CTA
                    ElevatedButton(
                      onPressed: _dismiss,
                      child: const Text("LET'S GO"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single row showing a mission title and its reward.
class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.mission});

  final DailyMission mission;

  @override
  Widget build(BuildContext context) {
    final rewardLabel = mission.rewardPower != null
        ? '+${mission.rewardCredits} cr · ${mission.rewardPower}'
        : '+${mission.rewardCredits} cr';

    return Row(
      children: [
        const Icon(Icons.radio_button_unchecked, size: 14, color: kAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            mission.slug.replaceAll('_', ' ').toUpperCase(),
            style: monoStyle(size: 10, color: kFg),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: kAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kAccent.withValues(alpha: 0.35)),
          ),
          child: Text(
            rewardLabel,
            style: monoStyle(size: 9, color: kAccent),
          ),
        ),
      ],
    );
  }
}
