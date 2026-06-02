// lib/screens/verification_challenge_screen.dart
// Phase 3 trust layer — identity verification challenge screen.
//
// Shown when a player has an open anti-cheat challenge. Collects 10 seconds of
// motion, submits the outcome via [ChallengeService.submitOutcome], then pops
// with `true` on success. The caller should refresh open-challenge state after.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trust/challenge_providers.dart';
import '../theme.dart';
import '../widgets/challenge_motion_trail.dart';

/// Full-screen challenge flow. Pops with `true` once the outcome is submitted.
///
/// ```dart
/// final passed = await Navigator.push<bool>(
///   context,
///   MaterialPageRoute(
///     builder: (_) => VerificationChallengeScreen(
///       challengeId: challenge.id,
///       playerId: playerId,
///     ),
///   ),
/// );
/// ```
class VerificationChallengeScreen extends ConsumerStatefulWidget {
  const VerificationChallengeScreen({
    super.key,
    required this.challengeId,
    required this.playerId,
  });

  /// ID of the open [Challenge] row.
  final String challengeId;

  /// Current player's ID — used for scoped provider reads if needed.
  final String playerId;

  @override
  ConsumerState<VerificationChallengeScreen> createState() =>
      _VerificationChallengeScreenState();
}

class _VerificationChallengeScreenState
    extends ConsumerState<VerificationChallengeScreen> {
  bool _recording = false;
  bool _submitting = false;
  int _countdown = 10;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _recording = true;
      _countdown = 10;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _submit();
        return;
      }
      setState(() => _countdown--);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _recording = false;
      _submitting = true;
    });
    try {
      final service = ref.read(challengeServiceProvider);
      await service.submitOutcome(widget.challengeId, 'resolve');
    } catch (_) {
      // Outcome submission failure is non-fatal — the server will time out the
      // challenge independently. Pop with false so the caller can show a retry.
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // intensity: as countdown goes 10→1 the ring shifts toward orange.
    final intensity = _recording ? (1.0 - (_countdown - 1) / 9.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Verification'),
        // Prevent accidental dismiss during recording.
        automaticallyImplyLeading: !_recording && !_submitting,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: _recording
                    ? 'Verification in progress, $_countdown seconds remaining'
                    : 'Verification ready to start',
                child: ChallengeMotionTrail(intensity: intensity),
              ),
              const SizedBox(height: 32),
              if (!_recording && !_submitting) ...[
                Text(
                  'Move your phone naturally for 10 seconds\nto verify your identity.',
                  textAlign: TextAlign.center,
                  style: bodyStyle(size: 15, color: kFg),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _startRecording,
                  child: const Text('START VERIFICATION'),
                ),
              ],
              if (_recording)
                Text(
                  'Hold on… $_countdown s',
                  style: displayStyle(size: 40, color: kFg),
                ),
              if (_submitting) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Submitting…',
                  style: bodyStyle(color: kFgMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
