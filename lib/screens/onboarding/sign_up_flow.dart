import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/onboarding_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../utils/username_validator.dart';

/// Converts a Flutter [Color] to a `#RRGGBB` hex string.
String _colorToHex(Color c) {
  final hex = (c.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
  return '#$hex'.toUpperCase();
}

/// Converts a `#RRGGBB` hex string to a Flutter [Color].
Color _hexToColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

/// Single-screen sign-up flow that collects username, bio, account colour, and
/// profile photo in one scrollable view.
///
/// Route re-evaluation after submit() is owned by _RouteGuard (main.dart):
/// once players.username is non-empty the guard navigates to MapScreen.
class SignUpFlow extends ConsumerStatefulWidget {
  const SignUpFlow({super.key});

  @override
  ConsumerState<SignUpFlow> createState() => _SignUpFlowState();
}

class _SignUpFlowState extends ConsumerState<SignUpFlow> {
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _usernameError;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // ── Avatar helpers ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (file != null) {
      ref.read(onboardingProvider.notifier).setAvatarPath(file.path);
    }
  }

  void _showAvatarSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kFgFaint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: kFg),
              title: Text('Take photo', style: bodyStyle(size: 15, color: kFg)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: kFg),
              title: Text('Choose from gallery', style: bodyStyle(size: 15, color: kFg)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final username = _usernameCtrl.text;
    final usernameErr = validateUsername(username);
    if (usernameErr != null) {
      setState(() => _usernameError = usernameErr);
      return;
    }
    setState(() => _usernameError = null);

    ref.read(onboardingProvider.notifier).setUsername(username.trim());

    final user = AuthService.instance.getCurrentUser();
    if (user == null) return;
    final userId = user['id'] as String;
    await ref.read(onboardingProvider.notifier).submit(userId);
    ref.invalidate(profileGateProvider(userId));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Error snackbar — fires on the live instance after guard re-render.
    ref.listen<OnboardingState>(onboardingProvider, (prev, next) {
      if (next.error != null && prev?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!, style: bodyStyle(size: 14, color: kFg)),
            backgroundColor: kDanger,
          ),
        );
      }
    });

    final state = ref.watch(onboardingProvider);
    final pickedColor = _hexToColor(state.color);
    final isLoading = state.isLoading;
    final usernameValid = validateUsername(_usernameCtrl.text) == null &&
        _usernameCtrl.text.isNotEmpty;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // ── Header ────────────────────────────────────────────────────
              Text(
                'CREATE YOUR\nIDENTITY',
                style: displayStyle(size: 40),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'This is how other runners see you on the map.',
                style: bodyStyle(size: 14, color: kFgMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Profile photo ─────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _showAvatarSheet,
                      child: _AvatarCircle(path: state.avatarPath),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _showAvatarSheet,
                      style: TextButton.styleFrom(
                        foregroundColor: kAccent,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        state.avatarPath != null ? 'CHANGE PHOTO' : 'ADD PHOTO',
                        style: monoStyle(size: 10, color: kAccent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Username ──────────────────────────────────────────────────
              Text('USERNAME', style: monoStyle(size: 10, color: kFgMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameCtrl,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  if (_usernameError != null) setState(() => _usernameError = null);
                  ref.read(onboardingProvider.notifier).clearError();
                  // Rebuild to update button enabled state.
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: 'e.g. runner42',
                  errorText: _usernameError,
                ),
              ),
              const SizedBox(height: 24),

              // ── Bio ───────────────────────────────────────────────────────
              Text('BIO', style: monoStyle(size: 10, color: kFgMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _bioCtrl,
                maxLines: 3,
                maxLength: 160,
                textInputAction: TextInputAction.done,
                onChanged: (v) =>
                    ref.read(onboardingProvider.notifier).setBio(v),
                decoration: const InputDecoration(
                  hintText: 'Tell the city who you are...',
                  counterStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: kFgFaint,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Account colour ────────────────────────────────────────────
              Text('YOUR COLOUR', style: monoStyle(size: 10, color: kFgMuted)),
              const SizedBox(height: 12),

              // Live preview swatch.
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: pickedColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: pickedColor.withValues(alpha: 0.55),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // HSV colour wheel.
              ColorPicker(
                pickerColor: pickedColor,
                onColorChanged: (c) {
                  ref.read(onboardingProvider.notifier).setColor(_colorToHex(c));
                },
                pickerAreaHeightPercent: 0.7,
                enableAlpha: false,
                labelTypes: const [],
                displayThumbColor: true,
                hexInputBar: false,
              ),
              const SizedBox(height: 32),

              // ── CTA ───────────────────────────────────────────────────────
              ElevatedButton(
                onPressed: (isLoading || !usernameValid) ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kBg,
                        ),
                      )
                    : const Text('JOIN THE WAR'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar circle widget ────────────────────────────────────────────────────

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kSurface,
        border: Border.all(color: kBorder, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: path != null
          ? Image.file(
              File(path!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    return const Center(
      child: Icon(Icons.person_outline, size: 40, color: kFgFaint),
    );
  }
}
