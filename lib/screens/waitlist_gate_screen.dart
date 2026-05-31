import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../services/auth_service.dart';
import '../theme.dart';

/// Shown when the signed-in user has no invite (profiles.invited_at IS NULL).
class WaitlistGateScreen extends ConsumerStatefulWidget {
  const WaitlistGateScreen({super.key});

  @override
  ConsumerState<WaitlistGateScreen> createState() =>
      _WaitlistGateScreenState();
}

class _WaitlistGateScreenState extends ConsumerState<WaitlistGateScreen> {
  final _codeCtrl = TextEditingController();
  bool _isRedeeming = false;
  String? _codeError;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeem(String userId) async {
    setState(() {
      _isRedeeming = true;
      _codeError = null;
    });
    final ok =
        await AuthService.instance.redeemInvitationCode(_codeCtrl.text, userId);
    if (ok) {
      ref.invalidate(profileGateProvider(userId));
    } else {
      setState(() {
        _codeError = 'Invalid or already used code';
        _isRedeeming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final userId = authState.user?['id'] as String? ?? '';

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "YOU'RE ON THE WAITLIST",
                textAlign: TextAlign.center,
                style: displayStyle(size: 36, color: kAccent),
              ),
              const SizedBox(height: 16),
              Text(
                "We'll notify you when your invite is ready.",
                textAlign: TextAlign.center,
                style: bodyStyle(size: 16),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\-]')),
                ],
                decoration: InputDecoration(
                  hintText: 'FOUNDING-VLCR-001',
                  filled: true,
                  fillColor: kBg,
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
                    borderSide:
                        BorderSide(color: kAccent.withValues(alpha: 0.6)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                style: bodyStyle(size: 14, color: kFg),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isRedeeming || userId.isEmpty)
                      ? null
                      : () => _redeem(userId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: kBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    disabledBackgroundColor: kAccent.withValues(alpha: 0.4),
                  ),
                  child: _isRedeeming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kBg,
                          ),
                        )
                      : Text(
                          'REDEEM INVITE CODE',
                          style: displayStyle(size: 18, color: kBg),
                        ),
                ),
              ),
              if (_codeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _codeError!,
                  style: bodyStyle(size: 13, color: kDanger),
                ),
              ],
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => ref.read(authProvider.notifier).signOut(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kBorder),
                  minimumSize: const Size(220, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'LOG OUT',
                  style: bodyStyle(size: 12, color: kFg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
