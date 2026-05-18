import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../services/waitlist_service.dart';
import '../widgets/city_autocomplete_field.dart';
import 'success_screen.dart';

class RequestAccessScreen extends StatefulWidget {
  /// Pre-filled referral code from a deeplink (e.g. runwar.app/join?ref=CODE)
  final String? referralRef;
  const RequestAccessScreen({super.key, this.referralRef});

  @override
  State<RequestAccessScreen> createState() => _RequestAccessScreenState();
}

class _RequestAccessScreenState extends State<RequestAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  String _city = '';
  String _email = '';
  String _phone = '';
  String _instagram = '';
  bool _loading = false;
  String? _error;

  String _buildReferralCode(String email) {
    final local = email.split('@').first;
    return local
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .toUpperCase()
        .substring(0, local.length.clamp(0, 16));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await WaitlistService.joinWaitlist(
      email: _email,
      phone: _phone,
      city: _city,
      instagram: _instagram.isEmpty ? null : _instagram,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.ok) {
      setState(() => _error = result.message);
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      '/success',
      arguments: SuccessArgs(
        city: _city,
        referralCode: _buildReferralCode(_email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Eyebrow
                Text('EARLY ACCESS', style: monoStyle(size: 10, color: kAccent)),
                const SizedBox(height: 12),

                // Headline
                Text(
                  'Request\naccess.',
                  style: GoogleFonts.bebasNeue(
                    fontSize: 52,
                    height: 1.05,
                    color: kFg,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),

                // Invitation narrative
                Text(
                  'You were invited. Don\'t waste the spot.\nWe pick runners city by city — not by luck, but by hunger.',
                  style: bodyStyle(size: 14),
                ),

                const SizedBox(height: 32),

                // City autocomplete
                CityAutocompleteField(
                  onChanged: (v) => _city = v,
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your city'
                      : null,
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  keyboardType: TextInputType.emailAddress,
                  style: bodyStyle(size: 14, color: kFg),
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    labelText: 'EMAIL',
                  ),
                  onChanged: (v) => _email = v,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v)) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone
                TextFormField(
                  keyboardType: TextInputType.phone,
                  style: bodyStyle(size: 14, color: kFg),
                  decoration: const InputDecoration(
                    hintText: '+1 555 000 0000',
                    labelText: 'PHONE',
                  ),
                  onChanged: (v) => _phone = v,
                  validator: (v) {
                    if (v == null || v.trim().length < 5) return 'Enter your phone number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Instagram (optional)
                TextFormField(
                  style: bodyStyle(size: 14, color: kFg),
                  decoration: const InputDecoration(
                    hintText: '@yourhandle',
                    labelText: 'INSTAGRAM (OPTIONAL)',
                  ),
                  onChanged: (v) => _instagram = v,
                ),

                // Referral code (pre-filled from deeplink)
                if (widget.referralRef != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kAccent.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.link, color: kAccent, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          'Referred by ${widget.referralRef}',
                          style: monoStyle(size: 10, color: kAccent),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Error
                if (_error != null) ...[
                  Text(_error!, style: bodyStyle(size: 13, color: kDanger)),
                  const SizedBox(height: 12),
                ],

                // Submit
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kBg,
                          ),
                        )
                      : Text(
                          'REQUEST ACCESS →',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            color: kBg,
                          ),
                        ),
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'NO SPAM. LAUNCH ALERT ONLY.',
                    style: monoStyle(size: 9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
