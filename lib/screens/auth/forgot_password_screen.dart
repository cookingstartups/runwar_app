import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // AC-12 — call regardless of email value; no validation.
    // sendPasswordReset is a PoC no-op (foundation AC-10).
    await AuthService.instance.sendPasswordReset(_emailController.text);
    if (!mounted) return;
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kFg),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text('FORGOT PASSWORD', style: displayStyle(size: 36)),
              const SizedBox(height: 8),
              Text(
                'Enter your email and we will send a reset link.',
                style: bodyStyle(size: 14, color: kFgMuted),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _sent ? null : _submit(),
                decoration: const InputDecoration(
                  labelText: 'EMAIL',
                  hintText: 'you@example.com',
                ),
              ),
              const SizedBox(height: 24),
              if (_sent) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBorder),
                  ),
                  child: Text(
                    'Check your email for a reset link.',
                    style: bodyStyle(size: 14, color: kFgMuted),
                    textAlign: TextAlign.center,
                  ),
                ),
              ] else ...[
                ElevatedButton(
                  onPressed: _submit,
                  child: const Text('SEND RESET LINK'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
