import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Displays a ticking countdown in mm:ss until [expiresAt].
/// Shows "EXPIRED" in [kDanger] once past expiry.
/// Calls [onExpired] once when the timer first reaches zero.
class OfferCountdown extends StatefulWidget {
  const OfferCountdown({
    required this.expiresAt,
    this.onExpired,
    super.key,
  });

  final DateTime expiresAt;
  final VoidCallback? onExpired;

  @override
  State<OfferCountdown> createState() => _OfferCountdownState();
}

class _OfferCountdownState extends State<OfferCountdown> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final now = DateTime.now();
    final diff = widget.expiresAt.difference(now);
    if (!mounted) return;
    if (diff.isNegative) {
      if (!_expired) {
        _expired = true;
        widget.onExpired?.call();
      }
      setState(() => _remaining = Duration.zero);
    } else {
      setState(() {
        _remaining = diff;
        _expired = false;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_expired || _remaining == Duration.zero) {
      return Text(
        'EXPIRED',
        style: monoStyle(size: 13, color: kDanger),
      );
    }
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Text(
      '$minutes:$seconds',
      style: monoStyle(size: 16, color: kFg),
    );
  }
}
