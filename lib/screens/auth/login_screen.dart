import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import 'invitation_code_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;
    await ref.read(authProvider.notifier).signIn(email, password);
    // On success authProvider state is updated with the new user.
    // The root _RouteGuard (POC-013) watches authProvider and rebuilds to
    // the destination screen. No Navigator call here.
  }

  Future<void> _signInWithGoogle() async {
    await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    final state = ref.read(authProvider);
    final user = state.user;
    if (user != null && user['invited_at'] == null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvitationCodeScreen(userId: user['id'] as String),
        ),
      );
    }
    // If invited_at is set (returning user), the route guard handles navigation.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final loading = state.isLoading;
    final errorText = state.error;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text('LOG IN', style: displayStyle(size: 40)),
              const SizedBox(height: 8),
              Text(
                'Welcome back, soldier.',
                style: bodyStyle(size: 14, color: kFgMuted),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: (_) =>
                    ref.read(authProvider.notifier).clearError(),
                decoration: const InputDecoration(
                  labelText: 'EMAIL',
                  hintText: 'you@example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => loading ? null : _submit(),
                onChanged: (_) =>
                    ref.read(authProvider.notifier).clearError(),
                decoration: const InputDecoration(
                  labelText: 'PASSWORD',
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
                    : const Text('LOG IN'),
              ),
              const SizedBox(height: 16),
              // ── OR divider ──────────────────────────────────────────────────
              Row(
                children: [
                  const Expanded(child: Divider(color: kBorder, thickness: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR', style: bodyStyle(size: 11, color: kFgFaint)),
                  ),
                  const Expanded(child: Divider(color: kBorder, thickness: 1)),
                ],
              ),
              const SizedBox(height: 16),
              // ── Google Sign-In button ───────────────────────────────────────
              OutlinedButton.icon(
                onPressed: loading ? null : _signInWithGoogle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kFg,
                  side: const BorderSide(color: kBorder),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: bodyStyle(size: 13, color: kFg).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.g_mobiledata, size: 24, color: kFg),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SignUpScreen(),
                  ),
                ),
                child: Text(
                  'Create account',
                  style: bodyStyle(size: 14, color: kAccent),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                ),
                child: Text(
                  'Forgot password?',
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
