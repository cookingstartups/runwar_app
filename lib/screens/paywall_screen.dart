import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/valencia_button.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key, required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final currency = _localCurrencySymbol(context);
    final isDownsellEligible = streak >= 7;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Header
              Text(
                'YOUR TRIAL\nHAS ENDED.',
                style: GoogleFonts.bebasNeue(
                  fontSize: 56,
                  height: 0.95,
                  color: kFg,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your 14 activity credits are used up.\nUnlock RunWar to keep your territory.',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.55,
                  color: kFgMuted,
                ),
              ),
              const SizedBox(height: 40),
              // Stats strip
              if (streak > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$streak',
                        style: GoogleFonts.bebasNeue(
                          fontSize: 32,
                          color: kAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'day streak\nDon\'t lose it.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.4,
                          color: kFgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              // Primary CTA — placeholder full price
              ValenciaButton(
                label: 'UNLOCK RUNWAR',
                onPressed: () => _showComingSoon(context),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Annual plan · pricing coming soon',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: kFgFaint,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // Downsell — only if streak >= 7
              if (isDownsellEligible) ...[
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: kAccent.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt_rounded,
                              color: kAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'YOU EARNED THIS',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              letterSpacing: 3,
                              color: kAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$streak days straight. Here\'s your runner\'s deal.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: kFg,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValenciaButton(
                        label: 'EXTEND 30 DAYS FOR ${currency}1',
                        variant: ValenciaButtonVariant.ghost,
                        onPressed: () =>
                            _navigateToDownsell(context, currency),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Valid as long as you claim territory every day.',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1.5,
                          color: kFgFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full unlock coming soon — stay tuned.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _navigateToDownsell(BuildContext context, String currency) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DownsellScreen(currency: currency, streak: streak),
      ),
    );
  }
}

class _DownsellScreen extends StatelessWidget {
  const _DownsellScreen({required this.currency, required this.streak});

  final String currency;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kFgMuted, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'RUNNER\'S\nEXTENSION',
                style: GoogleFonts.bebasNeue(
                  fontSize: 52,
                  height: 0.95,
                  color: kFg,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${streak} consecutive days earned you a 30-day '
                'extension for just ${currency}1.\n\n'
                'Keep claiming territory every day to stay in — '
                'the offer stays active as long as your streak holds.',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.6,
                  color: kFgMuted,
                ),
              ),
              const SizedBox(height: 40),
              // Price pill
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: kAccent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${currency}1 · 30 days',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kBg,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ValenciaButton(
                label: 'CLAIM ${currency}1 OFFER',
                onPressed: () => _onPay(context),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'One-time · no subscription · payment integration coming soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: kFgFaint,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  void _onPay(BuildContext context) {
    // Payment stub — extend trial locally until payment SDK is wired.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment coming soon — we\'ll notify you when ready.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

String _localCurrencySymbol(BuildContext context) {
  final locale = Localizations.localeOf(context);
  final country = locale.countryCode?.toUpperCase() ?? '';
  if (country == 'GB') return '£';
  if ({'US', 'CA', 'AU', 'NZ'}.contains(country)) return '\$';
  return '€';
}
