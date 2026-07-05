// lib/widgets/location_denied_gate.dart
//
// Blocking denied-state card for foreground location. Reused by both
// _LocationCard's denied variant (PermissionPrimingScreen) and MapScreen's
// revoked-after-priming late guard, so there is a single source of truth
// for this copy/UI instead of two implementations.
//
// Design reference: infra/meta/specs/runwar/permission-priming/design.md

import 'package:flutter/material.dart';

import '../services/permission_service.dart';
import '../theme.dart';

/// Standalone, stateless-from-the-outside hard-gate widget. Never offers a
/// "Not Now" / skip affordance - location remains mandatory for gameplay.
class LocationDeniedGate extends StatefulWidget {
  const LocationDeniedGate({super.key, this.onGranted});

  /// Called once foreground location becomes granted after a Try Again tap.
  final VoidCallback? onGranted;

  @override
  State<LocationDeniedGate> createState() => _LocationDeniedGateState();
}

class _LocationDeniedGateState extends State<LocationDeniedGate> {
  bool _requesting = false;

  Future<void> _onTryAgain() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await PermissionService.instance.requestForegroundLocation();
      final granted = await PermissionService.instance.isLocationGranted();
      if (granted) {
        widget.onGranted?.call();
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _onOpenSettings() async {
    await PermissionService.instance.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, color: kDanger, size: 40),
              const SizedBox(height: 16),
              Text('LOCATION DENIED', style: displayStyle(size: 24)),
              const SizedBox(height: 12),
              Text(
                'You cannot play without location. RunWar tracks your runs '
                'to claim territory on the map.',
                textAlign: TextAlign.center,
                style: bodyStyle(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _requesting ? null : _onTryAgain,
                style: ElevatedButton.styleFrom(backgroundColor: kAccent),
                child: const Text('TRY AGAIN'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _onOpenSettings,
                child: const Text('OPEN SETTINGS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
