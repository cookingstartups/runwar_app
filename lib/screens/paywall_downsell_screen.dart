import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/telemetry_service.dart';
import '../theme.dart';
import '../utils/runwar_constants.dart';

/// Standalone downsell screen shown when a player dismisses the day-21
/// milestone paywall section. Presents the €1/30-day trial offer.
/// UI only — no payment SDK wired.
class PaywallDownsellScreen extends StatelessWidget {
  const PaywallDownsellScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const PaywallDownsellScreen(),
    );
  }

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
                'UNLOCK\nTHE WAR',
                style: GoogleFonts.bebasNeue(
                  fontSize: 56,
                  height: 0.95,
                  color: kFg,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Reach a $kDownsellExtensionDays-day streak and earn a full '
                '$kDownsellExtensionDays-day extended trial for just '
                '€$kDownsellPriceAmount.\n\n'
                'Keep claiming territory every day — '
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
                    color: kAccent2,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '€$kDownsellPriceAmount · $kDownsellExtensionDays days',
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
              ElevatedButton(
                onPressed: () => _onSubscribe(context),
                style: ElevatedButton.styleFrom(backgroundColor: kAccent),
                child: const Text(
                  'SUBSCRIBE — €$kDownsellPriceAmount / $kDownsellExtensionDays DAYS',
                  style: TextStyle(color: kBg),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'NO THANKS',
                  style: TextStyle(
                    color: kFgMuted,
                    fontSize: 13,
                    letterSpacing: 1.5,
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

  void _onSubscribe(BuildContext context) {
    TelemetryService.instance.logEvent('paywall_downsell_subscribed').catchError((_) {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment flow not yet implemented'),
        duration: Duration(seconds: 3),
      ),
    );
    Navigator.of(context).pop();
  }
}
