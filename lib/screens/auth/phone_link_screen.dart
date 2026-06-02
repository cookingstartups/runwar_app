import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/grain_overlay.dart';
import '../../widgets/milestone_progress_bar.dart';
import '../../widgets/valencia_button.dart';

class PhoneLinkScreen extends ConsumerStatefulWidget {
  const PhoneLinkScreen({super.key});

  @override
  ConsumerState<PhoneLinkScreen> createState() => _PhoneLinkScreenState();
}

class _PhoneLinkScreenState extends ConsumerState<PhoneLinkScreen>
    with SingleTickerProviderStateMixin {
  String? _e164;
  bool _valid = false;
  bool _loading = false;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_valid || _e164 == null) return;
    setState(() => _loading = true);
    try {
      final userId =
          ref.read(authProvider).user?['id'] as String?;
      if (userId == null) return;
      await SupabaseService.instance.supabase
          .from('profiles')
          .update({'phone': _e164})
          .eq('id', userId);
      ref.invalidate(hasPhoneProvider(userId));
      ref.invalidate(profileGateProvider(userId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save phone: $e'),
              backgroundColor: kDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
        parent: _fadeCtrl, curve: const Cubic(0.22, 1, 0.36, 1));

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: FadeTransition(
              opacity: fade,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MilestoneProgressBar(currentStep: 0, labels: ['PHONE', 'TERRITORY', 'WAITLIST']),
                    const SizedBox(height: 32),
                    Text(
                      'Link your\nnumber.',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        color: kFg,
                        height: 0.98,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We alert you when your city goes live for runners.\nNever spam.',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: kFgMuted, height: 1.5),
                    ),
                    const SizedBox(height: 40),
                    Theme(
                      data: Theme.of(context).copyWith(
                        inputDecorationTheme: InputDecorationTheme(
                          filled: true,
                          fillColor: kSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: kBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: kBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: kAccent.withValues(alpha: 0.6)),
                          ),
                          hintStyle: const TextStyle(color: kFgFaint),
                          counterStyle:
                              const TextStyle(color: kFgMuted, fontSize: 10),
                        ),
                      ),
                      child: IntlPhoneField(
                        initialCountryCode: 'ES',
                        style: GoogleFonts.inter(color: kFg, fontSize: 16),
                        dropdownTextStyle:
                            GoogleFonts.inter(color: kFg, fontSize: 14),
                        dropdownIcon:
                            const Icon(Icons.arrow_drop_down, color: kFgMuted),
                        onChanged: (phone) {
                          setState(() {
                            _valid = phone.number.length >= 6;
                            _e164 = phone.completeNumber;
                          });
                        },
                        onCountryChanged: (_) {},
                      ),
                    ),
                    const Spacer(),
                    ValenciaButton(
                      label: 'CONTINUE',
                      onPressed: _valid ? _continue : null,
                      enabled: _valid,
                      loading: _loading,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          const GrainOverlay(),
        ],
      ),
    );
  }
}
