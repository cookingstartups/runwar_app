import 'package:flutter/material.dart';

import '../providers/run_recorder_provider.dart';
import '../services/run_recorder_service.dart';
import '../services/territory_service.dart';
import '../theme.dart';

/// Durable HUD pill showing the current closure-lifecycle state: a
/// geometry-gate rejection, the session-elapsed wait, a dispatched-but-
/// unresolved claim, or a settled outcome. Always takes a non-null state -
/// the "renders nothing while idle" behavior lives one level up, in the
/// HUD's own mount/unmount wiring, not in this widget.
class ClosureIndicator extends StatelessWidget {
  const ClosureIndicator({required this.state, super.key});

  final ClosureUiState state;

  @override
  Widget build(BuildContext context) {
    switch (state.kind) {
      case ClosureUiKind.gateRejected:
        final copy = _gateRejectedCopy(state.gateReason!);
        return _pill(copy, color: kFgMuted);
      case ClosureUiKind.sessionElapsedWait:
        return _pill('UNLOCKS IN ${state.waitElapsedSec}s', color: kAccent2);
      case ClosureUiKind.claiming:
        return _pill('CLAIMING...', color: kAccent);
      case ClosureUiKind.settled:
        return _pill(_settledCopy(state.outcome!), color: _settledColor(state.outcome!));
    }
  }

  String _gateRejectedCopy(GateRejectionReason reason) => switch (reason) {
        GateRejectionReason.areaFloor => 'LOOP TOO SMALL - try again',
        GateRejectionReason.diagonalFloor => 'LOOP TOO SMALL - run a wider path',
        GateRejectionReason.compactness => 'LOOP TOO THIN - run a wider path',
        GateRejectionReason.pathLength => 'LOOP TOO SHORT - keep running',
        GateRejectionReason.sessionElapsed => 'ALMOST THERE - keep running',
      };

  String _settledCopy(TerritoryResult outcome) => switch (outcome) {
        TerritoryResult.claimed => 'CLAIMED',
        TerritoryResult.conquered => 'CONQUERED',
        TerritoryResult.disputed => 'DISPUTED',
        TerritoryResult.failed => 'COULD NOT CLAIM',
      };

  Color _settledColor(TerritoryResult outcome) => switch (outcome) {
        TerritoryResult.claimed => kAccent,
        TerritoryResult.conquered => kAccent2,
        TerritoryResult.disputed => const Color(0xFFEC4899),
        TerritoryResult.failed => kDanger,
      };

  Widget _pill(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
