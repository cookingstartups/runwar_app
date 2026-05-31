// READ-ONLY by Phase 2 contract. No tap-to-buy. Spec §10 forbids storefront UI.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provider + model written by @Backend-Developer.
// design.md §5.1 — provider key: activeGrantsProvider
import '../providers/superpowers/active_grants_provider.dart';
// design.md §3.2
import '../services/database/superpowers_repository.dart';
import '../theme.dart';

/// Power types classified as Rare.
const _kRarePowers = {'GHOST_RUN', 'BLITZ', 'FORTIFY', 'OVERCLOCK'};

/// Background color by tier.
Color _tileColor(String powerType) =>
    _kRarePowers.contains(powerType) ? const Color(0xFF9C27B0) : kAccent;

/// Horizontal scrollable strip of active superpower tiles.
/// Renders nothing when the player has no charges.
class SuperpowerInventoryStrip extends ConsumerWidget {
  const SuperpowerInventoryStrip({
    required this.playerId,
    super.key,
  });

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grantsAsync = ref.watch(activeGrantsProvider(playerId));

    return grantsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (grants) {
        // Only show grants with remaining charges.
        final active = grants
            .where((g) => g.chargesRemaining > 0)
            .toList(growable: false);

        if (active.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: active.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _PowerTile(grant: active[i]),
          ),
        );
      },
    );
  }
}

/// Individual power tile with abbreviation label + charge-count badge.
class _PowerTile extends StatelessWidget {
  const _PowerTile({required this.grant});

  final SuperpowerGrant grant;

  @override
  Widget build(BuildContext context) {
    final bg = _tileColor(grant.powerType);
    final label = grant.powerType.length <= 6
        ? grant.powerType
        : grant.powerType.substring(0, 6);

    return Tooltip(
      message: 'Earned via ${grant.source}. Charges left: ${grant.chargesRemaining}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Tile body.
          Container(
            width: 52,
            height: 54,
            decoration: BoxDecoration(
              color: bg.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: bg, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
                height: 1.2,
              ),
            ),
          ),
          // Charge-count badge — top-right.
          if (grant.chargesRemaining > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: kSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: bg, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${grant.chargesRemaining}',
                  style: TextStyle(
                    color: bg,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
