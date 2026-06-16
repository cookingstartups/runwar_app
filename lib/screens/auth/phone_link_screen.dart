import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../config/supabase_config.dart';
import '../../services/database/account_uniqueness_error.dart';
import '../../theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/database_service.dart';
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
      final userId = ref.read(authProvider).user?['id'] as String?;
      if (userId == null) return;
      // Save to Supabase first — always succeeds.
      await DatabaseService.instance.updateProfile(userId, {'phone': _e164});
      // Persist to remote — best-effort, non-fatal.
      if (SupabaseService.instance.isConnected) {
        await SupabaseService.instance.supabase.functions.invoke(
          SupabaseConfig.fnSavePhone,
          body: {'phone': _e164},
        );
      }
      ref.invalidate(hasPhoneProvider(userId));
    } catch (e) {
      if (!mounted) return;
      final dupMsg = accountUniquenessMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dupMsg ?? 'Failed to save phone: $e'),
          backgroundColor: kDanger,
        ),
      );
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
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: FadeTransition(
              opacity: fade,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MilestoneProgressBar(currentStep: 0),
                    const SizedBox(height: 32),
                    Text(
                      'Verify your\naccount.',
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
                      'You\'ll receive a one-time SMS code to confirm your number.\nNo fakes. No bots. Real runners only.',
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
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        invalidNumberMessage: 'Enter your full number — e.g. 722 456 789',
                        validator: (phone) {
                          if (phone == null || phone.number.length < 7) {
                            return 'Enter your full number — e.g. 722 456 789';
                          }
                          return null;
                        },
                        onChanged: (phone) {
                          setState(() {
                            _valid = phone.number.length >= 7;
                            _e164 = phone.completeNumber;
                          });
                        },
                        onCountryChanged: (_) {},
                      ),
                    ),
                    const SizedBox(height: 40),
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
