// lib/screens/permission_priming_screen.dart
//
// "SET UP YOUR GAME" - single sequential post-login screen that requests
// location, notifications, and battery-exemption permissions in a fixed
// order, one OS dialog at a time, from explicit CTA taps only.
//
// Design reference: infra/meta/specs/runwar/permission-priming/design.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/permission_priming_provider.dart';
import '../services/permission_service.dart';
import '../theme.dart';
import '../widgets/location_denied_gate.dart';

class PermissionPrimingScreen extends ConsumerStatefulWidget {
  const PermissionPrimingScreen({super.key, required this.missing});

  /// Permission types still missing when this screen was routed to. Always
  /// re-sorted into the canonical order before display, regardless of the
  /// order the caller passed.
  final List<PermKind> missing;

  @override
  ConsumerState<PermissionPrimingScreen> createState() =>
      _PermissionPrimingScreenState();
}

class _PermissionPrimingScreenState
    extends ConsumerState<PermissionPrimingScreen> {
  late final List<PermKind> _cards = orderMissing(widget.missing.toSet());
  int _cardIndex = 0;
  bool _locationDenied = false;

  bool get _isLastCard => _cardIndex >= _cards.length - 1;

  void _advanceOrComplete() {
    if (_isLastCard) {
      _complete();
      return;
    }
    setState(() => _cardIndex++);
  }

  Future<void> _complete() async {
    await PermissionService.instance.markPrimingDone();
    ref.invalidate(permissionPrimingMissingProvider);
  }

  // ── Location (hard gate) ─────────────────────────────────────────────────

  Future<void> _onEnableLocation() async {
    final result = await PermissionService.instance.requestForegroundLocation();
    if (!mounted) return;
    final granted = result == LocationPermission.whileInUse ||
        result == LocationPermission.always;
    if (granted) {
      // Background elevation is a soft upgrade - its outcome never blocks
      // progression.
      await PermissionService.instance.requestBackgroundLocationIfSupported();
      if (!mounted) return;
      setState(() => _locationDenied = false);
      _advanceOrComplete();
    } else {
      setState(() => _locationDenied = true);
    }
  }

  void _onLocationGrantedFromDeniedGate() {
    setState(() => _locationDenied = false);
    _advanceOrComplete();
  }

  // ── Notifications (soft ask) ─────────────────────────────────────────────

  Future<void> _onTurnOnAlerts() async {
    await PermissionService.instance.requestNotifications();
    if (!mounted) return;
    _advanceOrComplete();
  }

  void _onNotNowNotifications() => _advanceOrComplete();

  // ── Battery (soft ask via settings intent) ───────────────────────────────

  Future<void> _onKeepRunsAlive() async {
    await PermissionService.instance.requestBattery();
    if (!mounted) return;
    _advanceOrComplete();
  }

  void _onNotNowBattery() => _advanceOrComplete();

  @override
  Widget build(BuildContext context) {
    final kind = _cards[_cardIndex];

    late final Widget card;
    switch (kind) {
      case PermKind.location:
        card = _locationDenied
            ? LocationDeniedGate(onGranted: _onLocationGrantedFromDeniedGate)
            : _LocationCard(onEnable: _onEnableLocation);
      case PermKind.notifications:
        card = _NotificationsCard(
          onTurnOnAlerts: _onTurnOnAlerts,
          onNotNow: _onNotNowNotifications,
        );
      case PermKind.battery:
        card = _BatteryCard(
          onKeepRunsAlive: _onKeepRunsAlive,
          onNotNow: _onNotNowBattery,
        );
    }

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _PrimingHeader(current: _cardIndex + 1, total: _cards.length),
            const SizedBox(height: 16),
            _PrimingProgressDots(total: _cards.length, current: _cardIndex),
            const SizedBox(height: 8),
            Expanded(child: card),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _PrimingHeader extends StatelessWidget {
  const _PrimingHeader({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('SET UP YOUR GAME', style: displayStyle(size: 26)),
        const SizedBox(height: 4),
        Text('$current OF $total', style: monoStyle(size: 12, color: kFgMuted)),
      ],
    );
  }
}

// ── Progress dots ────────────────────────────────────────────────────────

class _PrimingProgressDots extends StatelessWidget {
  const _PrimingProgressDots({required this.total, required this.current});

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= current ? kAccent : kFgFaint,
            ),
          ),
      ],
    );
  }
}

// ── Location card (default state - hard gate, no skip affordance) ───────

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: kAccent, size: 40),
            const SizedBox(height: 16),
            Text('SHARE YOUR LOCATION', style: displayStyle(size: 22)),
            const SizedBox(height: 12),
            Text(
              'RunWar tracks your run to claim territory on the map. '
              'Location is required to play.',
              textAlign: TextAlign.center,
              style: bodyStyle(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onEnable,
              style: ElevatedButton.styleFrom(backgroundColor: kAccent),
              child: const Text('ENABLE LOCATION'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notifications card (soft ask) ────────────────────────────────────────

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({
    required this.onTurnOnAlerts,
    required this.onNotNow,
  });

  final VoidCallback onTurnOnAlerts;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_active, color: kAccent, size: 40),
            const SizedBox(height: 16),
            Text('STAY IN THE FIGHT', style: displayStyle(size: 22)),
            const SizedBox(height: 12),
            Text(
              'Get notified the moment a rival contests your territory.',
              textAlign: TextAlign.center,
              style: bodyStyle(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onTurnOnAlerts,
              style: ElevatedButton.styleFrom(backgroundColor: kAccent),
              child: const Text('TURN ON ALERTS'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onNotNow,
              child: const Text('NOT NOW'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Battery card (soft ask via settings intent) ──────────────────────────

class _BatteryCard extends StatefulWidget {
  const _BatteryCard({
    required this.onKeepRunsAlive,
    required this.onNotNow,
  });

  final VoidCallback onKeepRunsAlive;
  final VoidCallback onNotNow;

  @override
  State<_BatteryCard> createState() => _BatteryCardState();
}

class _BatteryCardState extends State<_BatteryCard> {
  // Computed once when the card's State object is created - reading the
  // manufacturer is a status check, not an OS permission dialog, so it is
  // safe to resolve eagerly rather than re-query on every rebuild.
  final Future<bool> _miuiFuture = PermissionService.instance.isMiuiManufacturer();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.battery_charging_full, color: kAccent, size: 40),
            const SizedBox(height: 16),
            Text('KEEP YOUR RUNS ALIVE', style: displayStyle(size: 22)),
            const SizedBox(height: 12),
            Text(
              'Allow RunWar to run unrestricted in the background so GPS '
              'tracking never drops mid-run.',
              textAlign: TextAlign.center,
              style: bodyStyle(),
            ),
            FutureBuilder<bool>(
              future: _miuiFuture,
              builder: (context, snapshot) {
                if (snapshot.data != true) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'On Xiaomi/Redmi/POCO: enable Autostart in the Security '
                    'app and set Battery saver to "No restrictions" for RunWar.',
                    textAlign: TextAlign.center,
                    style: bodyStyle(size: 12, color: kAccent2),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: widget.onKeepRunsAlive,
              style: ElevatedButton.styleFrom(backgroundColor: kAccent),
              child: const Text('KEEP MY RUNS ALIVE'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onNotNow,
              child: const Text('NOT NOW'),
            ),
          ],
        ),
      ),
    );
  }
}
