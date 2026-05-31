// THIS FILE IS THE ONLY SANCTIONED CALLER OF spend_credits_on_power.
// No other lib/ file may reference that edge function.
// Enforced by tool/lint/no_storefront.dart (design.md §8).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

// Repository + model — written by @Backend-Developer (design.md §3.2).
import '../services/database/offers_repository.dart';
// Providers — written by @Backend-Developer (design.md §5.1).
import '../providers/economy/credits_provider.dart';
import '../providers/repositories.dart';
import '../widgets/offer_countdown.dart';
import '../widgets/credits_chip.dart';
import '../theme.dart';

/// Full-screen dark modal for accepting or declining a superpower offer.
/// This is the ONLY surface that calls [spend_credits_on_power].
/// Pushed as a route (not a bottom sheet) — dismiss via pop only.
class ContextualOfferScreen extends ConsumerStatefulWidget {
  final SuperpowerOffer offer;

  /// The player id — required so the screen can read the credit balance.
  final String playerId;

  /// If the offer requires BLITZ/FORTIFY, these must be provided by MapScreen.
  final LatLng? currentPosition;
  final String? standingZoneId;

  const ContextualOfferScreen({
    required this.offer,
    required this.playerId,
    this.currentPosition,
    this.standingZoneId,
    super.key,
  });

  @override
  ConsumerState<ContextualOfferScreen> createState() =>
      _ContextualOfferScreenState();
}

class _ContextualOfferScreenState
    extends ConsumerState<ContextualOfferScreen> {
  bool _isLoading = false;
  bool _isExpiredOnOpen = false;

  @override
  void initState() {
    super.initState();
    // If the offer was already expired when the screen opened, show static expired state.
    _isExpiredOnOpen = widget.offer.expiresAt.isBefore(DateTime.now());
  }

  /// Derive human-readable body copy from offer type.
  String _offerBody() {
    final powerName = widget.offer.offeredPowerType;
    final cost = widget.offer.costCredits;
    final tierLabel = widget.offer.tier == 'rare' ? 'Rare' : 'Common';
    return switch (widget.offer.offerType) {
      'extra_charge' =>
        'Get an extra charge of $powerName — $cost credits',
      'random_same_tier' =>
        'Get a random $tierLabel power — $cost credits',
      'complementary_tier' =>
        'Get ${widget.offer.offeredPowerType} — $cost credits',
      _ => 'Special offer — $cost credits',
    };
  }

  /// Derive tier badge label.
  String _tierLabel() =>
      widget.offer.tier == 'rare' ? 'RARE' : 'COMMON';

  Color _tierColor() =>
      widget.offer.tier == 'rare'
          ? const Color(0xFF9C27B0)
          : kAccent;

  bool get _requiresStandingZone =>
      widget.offer.offeredPowerType == 'BLITZ' ||
      widget.offer.offeredPowerType == 'FORTIFY';

  Future<void> _onAccept() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final result = await ref.read(offersRepoProvider).accept(
            widget.offer.id,
            targetZoneId: widget.standingZoneId,
            lat: widget.currentPosition?.latitude,
            lng: widget.currentPosition?.longitude,
          );

      if (!mounted) return;

      switch (result) {
        case SpendOk():
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Power unlocked!')),
          );
          Navigator.of(context).pop();
        case SpendFailure(:final reason):
          final msg = switch (reason) {
            'offer_expired' => 'Offer has expired.',
            'insufficient_credits' => 'Not enough credits.',
            'no_target_zone' => 'You must be standing on one of your zones.',
            'not_on_zone' => 'You are not close enough to a zone.',
            'already_resolved' => 'Offer already accepted or declined.',
            _ => 'Could not accept offer: $reason',
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: kDanger),
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: kDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onDecline() async {
    try {
      await ref.read(offersRepoProvider).decline(widget.offer.id);
    } catch (_) {
      // Best-effort decline; don't block the user.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(creditsBalanceProvider(widget.playerId));
    final balance = balanceAsync.valueOrNull ?? 0;
    final cost = widget.offer.costCredits;
    final canAfford = balance >= cost;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        automaticallyImplyLeading: false,
        title: Text(
          'YOU EARNED A POWER',
          style: monoStyle(size: 11, color: kAccent),
        ),
        actions: [
          TextButton(
            onPressed: _isExpiredOnOpen ? () => Navigator.of(context).pop() : _onDecline,
            child: Text(
              'DECLINE',
              style: monoStyle(size: 11, color: kFgMuted),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isExpiredOnOpen
            ? _buildExpiredBody(context)
            : _buildActiveBody(context, balance, cost, canAfford),
      ),
    );
  }

  Widget _buildExpiredBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'OFFER EXPIRED',
            style: displayStyle(size: 28, color: kDanger),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kSurface),
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CLOSE', style: monoStyle(size: 12, color: kFg)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBody(
    BuildContext context,
    int balance,
    int cost,
    bool canAfford,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Power type name + tier badge.
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.offer.offeredPowerType,
                  style: displayStyle(size: 32),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _tierColor().withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _tierColor()),
                ),
                child: Text(
                  _tierLabel(),
                  style: monoStyle(size: 10, color: _tierColor()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Offer description.
          Text(
            _offerBody(),
            style: bodyStyle(size: 16, color: kFg),
          ),

          // BLITZ/FORTIFY positional note.
          if (_requiresStandingZone) ...[
            const SizedBox(height: 12),
            Text(
              'You must be standing on one of your zones to activate this.',
              style: bodyStyle(size: 13, color: kFgMuted),
            ),
          ],

          const SizedBox(height: 32),

          // Countdown.
          Row(
            children: [
              Text('EXPIRES IN ', style: monoStyle(size: 10, color: kFgMuted)),
              OfferCountdown(
                expiresAt: widget.offer.expiresAt,
                onExpired: () {
                  if (mounted) Navigator.of(context).maybePop();
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Current credit balance.
          Text('YOUR CREDITS', style: monoStyle(size: 10, color: kFgMuted)),
          const SizedBox(height: 4),
          Row(
            children: [
              CreditsChip(playerId: widget.playerId),
              if (!canAfford) ...[
                const SizedBox(width: 8),
                Text('Insufficient credits', style: bodyStyle(size: 12, color: kDanger)),
              ],
            ],
          ),

          const SizedBox(height: 40),

          // Accept CTA.
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: canAfford ? kAccent : kSurface,
              foregroundColor: canAfford ? kBg : kFgMuted,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: (canAfford && !_isLoading) ? _onAccept : null,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'ACCEPT — $cost CREDITS',
                    style: monoStyle(
                      size: 12,
                      color: canAfford ? kBg : kFgMuted,
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          // Decline CTA.
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            onPressed: _isLoading ? null : _onDecline,
            child:
                Text('Decline', style: bodyStyle(size: 14, color: kFgMuted)),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
