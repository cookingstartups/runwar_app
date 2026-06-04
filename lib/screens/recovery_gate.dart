import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/run_recovery_service.dart';
import '../services/run_recorder_service.dart';
import '../providers/run_recorder_provider.dart';
import '../theme.dart';

/// Route-level gate that detects orphaned run_scratch rows and presents a
/// recovery dialog before allowing [child] (typically MainShell) to mount.
///
/// AC-12: blocks normal app flow until user makes a resume/discard choice.
/// AC-13: Resume → rehydrates _track and restarts foreground service.
/// AC-14: Discard → clears run_scratch and proceeds to idle map.
class RecoveryGate extends ConsumerStatefulWidget {
  const RecoveryGate({super.key, required this.userId, required this.child});

  final String userId;
  final Widget child;

  @override
  ConsumerState<RecoveryGate> createState() => _RecoveryGateState();
}

class _RecoveryGateState extends ConsumerState<RecoveryGate> {
  OrphanedRun? _orphan;
  bool _checking = true;
  bool _decisionMade = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final orphan =
        await RunRecoveryService.instance.detectOrphan(widget.userId);
    if (mounted) {
      setState(() {
        _orphan = orphan;
        _checking = false;
      });
    }
  }

  Future<void> _onResume() async {
    await ref.read(runRecorderProvider.notifier).resume(widget.userId);
    if (mounted) {
      setState(() => _decisionMade = true);
    }
  }

  Future<void> _onDiscard() async {
    await RunRecorderService.instance.clearScratch(widget.userId);
    if (mounted) {
      setState(() => _decisionMade = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Still querying the DB — show a minimal loader.
    if (_checking) {
      return const Scaffold(
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

    // No orphan found, or user already made a choice — proceed normally.
    if (_orphan == null || _decisionMade) {
      return widget.child;
    }

    // Orphan detected — show the recovery dialog over a dark backdrop.
    // MainShell is NOT mounted yet (AC-12 invariant).
    return _RecoveryDialogScreen(
      orphan: _orphan!,
      onResume: _onResume,
      onDiscard: _onDiscard,
    );
  }
}

class _RecoveryDialogScreen extends StatelessWidget {
  const _RecoveryDialogScreen({
    required this.orphan,
    required this.onResume,
    required this.onDiscard,
  });

  final OrphanedRun orphan;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Material(
            color: kSurface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UNFINISHED RUN',
                    style: displayStyle(size: 22, color: kAccent),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You have an unfinished run with '
                    '${orphan.pointCount} recorded point${orphan.pointCount == 1 ? '' : 's'}. '
                    'Resume and keep recording, or discard it?',
                    style: bodyStyle(size: 14, color: kFgMuted),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onDiscard,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kFgMuted,
                            side: BorderSide(
                              color: kBorder.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text('DISCARD'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onResume,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('RESUME'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
