import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import 'login_screen.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Pre-network client-side validation error (AC-9 — password mismatch).
  // Kept separate from authProvider.error because it never reaches the service.
  String? _localError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _localError = null);
    ref.read(authProvider.notifier).clearError();

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) return;

    // AC-9 — validate before calling service.
    if (password != confirm) {
      setState(() => _localError = 'Passwords do not match');
      return;
    }

    await ref.read(authProvider.notifier).signUp(email, password);
    // On success the root _RouteGuard (POC-013) rebuilds to WaitlistGateScreen
    // (invited_at = null on fresh signUp). No Navigator call here.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final loading = state.isLoading;
    final errorText = _localError ?? state.error;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text('CREATE ACCOUNT', style: displayStyle(size: 36)),
              const SizedBox(height: 8),
              Text(
                'Join the war.',
                style: bodyStyle(size: 14, color: kFgMuted),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  setState(() => _localError = null);
                  ref.read(authProvider.notifier).clearError();
                },
                decoration: const InputDecoration(
                  labelText: 'EMAIL',
                  hintText: 'you@example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  setState(() => _localError = null);
                  ref.read(authProvider.notifier).clearError();
                },
                decoration: const InputDecoration(
                  labelText: 'PASSWORD',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => loading ? null : _submit(),
                onChanged: (_) {
                  setState(() => _localError = null);
                  ref.read(authProvider.notifier).clearError();
                },
                decoration: const InputDecoration(
                  labelText: 'CONFIRM PASSWORD',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText,
                  style: bodyStyle(size: 13, color: kDanger),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: loading ? null : _submit,
                child: loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kBg,
                        ),
                      )
                    : const Text('CREATE ACCOUNT'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                ),
                child: Text(
                  'Already have an account?',
                  style: bodyStyle(size: 14, color: kFgMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
