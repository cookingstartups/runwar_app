import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/onboarding_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../utils/username_validator.dart';

// 12 predefined vivid palette colors for the BlockPicker (step 3).
// Order matches the brief: orange, pink, teal, yellow, red, purple,
// green, blue, orange2, magenta, cyan, lime.
const List<Color> _kPaletteColors = [
  Color(0xFFFF7A00),
  Color(0xFFFF2D7A),
  Color(0xFF00F5E1),
  Color(0xFFFFD700),
  Color(0xFFFF4500),
  Color(0xFF7B2FBE),
  Color(0xFF00C853),
  Color(0xFF2979FF),
  Color(0xFFFF6D00),
  Color(0xFFE91E63),
  Color(0xFF00BCD4),
  Color(0xFF8BC34A),
];

/// Converts a Flutter [Color] to a `#RRGGBB` hex string.
String _colorToHex(Color c) {
  // Use the ARGB int value; mask off the alpha channel (top byte).
  final hex = (c.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
  return '#$hex'.toUpperCase();
}

/// Converts a `#RRGGBB` hex string to a Flutter [Color].
Color _hexToColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

/// 3-step onboarding flow: username → city → color.
///
/// Controlled by [onboardingProvider]. The [PageView] advances on each
/// "Continue" / "Start playing" action. Route re-evaluation after submit()
/// is owned by POC-013 (_RouteGuard in main.dart): once profiles.username
/// is non-empty, the guard will route to MapScreen on its next watch cycle.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: ref.read(onboardingProvider).step,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Drive the PageView whenever the provider's step changes.
    ref.listen<int>(
      onboardingProvider.select((s) => s.step),
      (_, next) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(next);
        }
      },
    );

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          // Disable swipe — navigation is controlled by buttons only.
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            _Step1Username(),
            _Step3Color(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — Username
// ─────────────────────────────────────────────────────────────────────────────

class _Step1Username extends ConsumerStatefulWidget {
  const _Step1Username();

  @override
  ConsumerState<_Step1Username> createState() => _Step1UsernameState();
}

class _Step1UsernameState extends ConsumerState<_Step1Username> {
  final _ctrl = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onContinue() {
    final value = _ctrl.text;
    final error = validateUsername(value);
    if (error != null) {
      setState(() => _localError = error);
      return;
    }
    setState(() => _localError = null);
    ref.read(onboardingProvider.notifier).setUsername(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final isLoading =
        ref.watch(onboardingProvider.select((s) => s.isLoading));
    final providerError =
        ref.watch(onboardingProvider.select((s) => s.error));
    final errorText = _localError ?? providerError;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          Text(
            'STEP 3 / 3 · IDENTITY',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              letterSpacing: 3.0,
              color: kAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text('PICK A USERNAME', style: displayStyle(size: 36)),
          const SizedBox(height: 8),
          Text(
            'This is how other runners will see you on the map.',
            style: bodyStyle(size: 14, color: kFgMuted),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _ctrl,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => isLoading ? null : _onContinue(),
            onChanged: (_) {
              if (_localError != null) setState(() => _localError = null);
              ref.read(onboardingProvider.notifier).clearError();
            },
            decoration: const InputDecoration(
              labelText: 'USERNAME',
              hintText: 'e.g. runner42',
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
            onPressed: isLoading ? null : _onContinue,
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — Color (palette swatches + custom hex input)
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true if [hex] is a valid #RRGGBB string.
bool _isValidHex(String hex) =>
    RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex);

class _Step3Color extends ConsumerStatefulWidget {
  const _Step3Color();

  @override
  ConsumerState<_Step3Color> createState() => _Step3ColorState();
}

class _Step3ColorState extends ConsumerState<_Step3Color> {
  late final TextEditingController _hexCtrl;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(
      text: ref.read(onboardingProvider).color,
    );
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _onSwatchTap(Color color) {
    final hex = _colorToHex(color);
    ref.read(onboardingProvider.notifier).setColor(hex);
    _hexCtrl.text = hex;
    setState(() => _hexError = null);
  }

  void _onHexChanged(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.length == 6 && !trimmed.startsWith('#')) {
      // auto-prefix if user omitted #
      final prefixed = '#$trimmed';
      if (_isValidHex(prefixed)) {
        _hexCtrl.value = _hexCtrl.value.copyWith(
          text: prefixed,
          selection: TextSelection.collapsed(offset: prefixed.length),
        );
        ref.read(onboardingProvider.notifier).setColor(prefixed);
        setState(() => _hexError = null);
        return;
      }
    }
    if (_isValidHex(trimmed)) {
      ref.read(onboardingProvider.notifier).setColor(trimmed);
      setState(() => _hexError = null);
    } else {
      setState(() => _hexError = trimmed.isEmpty ? null : 'Enter a valid hex e.g. #FF7A00');
    }
  }

  Future<void> _startPlaying() async {
    final user = AuthService.instance.getCurrentUser();
    if (user == null) return;
    final userId = user['id'] as String;
    await ref.read(onboardingProvider.notifier).submit(userId);
    ref.invalidate(profileGateProvider(userId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final selectedColor = _hexToColor(state.color);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Text('PICK A COLOR', style: displayStyle(size: 36)),
          const SizedBox(height: 8),
          Text(
            'Your color is how you appear on the territory map.',
            style: bodyStyle(size: 14, color: kFgMuted),
          ),
          const SizedBox(height: 24),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: _kPaletteColors.map((color) {
                final isSelected = color.toARGB32() == selectedColor.toARGB32();
                return GestureDetector(
                  onTap: () => _onSwatchTap(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
                          : [],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 28),
          // Custom hex input row with live preview swatch.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Live preview dot.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _hexError == null ? selectedColor : kFgMuted,
                  shape: BoxShape.circle,
                  boxShadow: _hexError == null
                      ? [BoxShadow(color: selectedColor.withValues(alpha: 0.5), blurRadius: 8)]
                      : [],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: _onHexChanged,
                  decoration: InputDecoration(
                    labelText: 'CUSTOM HEX',
                    hintText: '#FF7A00',
                    errorText: _hexError,
                  ),
                ),
              ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(state.error!, style: bodyStyle(size: 13, color: kDanger)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: state.isLoading || _hexError != null ? null : _startPlaying,
            child: state.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kBg),
                  )
                : const Text('START PLAYING'),
          ),
        ],
      ),
    );
  }
}
