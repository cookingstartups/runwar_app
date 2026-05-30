import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/onboarding_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

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
            _Step2City(),
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
    final value = _ctrl.text.trim();
    if (value.isEmpty) {
      setState(() => _localError = 'Username cannot be empty');
      return;
    }
    if (value.contains(' ')) {
      setState(() => _localError = 'Username cannot contain spaces');
      return;
    }
    setState(() => _localError = null);
    ref.read(onboardingProvider.notifier).setUsername(value);
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
// Step 2 — City
// ─────────────────────────────────────────────────────────────────────────────

class _Step2City extends ConsumerStatefulWidget {
  const _Step2City();

  @override
  ConsumerState<_Step2City> createState() => _Step2CityState();
}

class _Step2CityState extends ConsumerState<_Step2City> {
  // The initial value mirrors OnboardingState.city default ('Valencia').
  String? _selectedCity;
  String? _localError;

  void _onContinue() {
    if (_selectedCity == null) {
      setState(() => _localError = 'Please select a city');
      return;
    }
    setState(() => _localError = null);
    ref.read(onboardingProvider.notifier).setCity(_selectedCity!);
  }

  @override
  Widget build(BuildContext context) {
    final providerError =
        ref.watch(onboardingProvider.select((s) => s.error));
    final errorText = _localError ?? providerError;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          Text('PICK A CITY', style: displayStyle(size: 36)),
          const SizedBox(height: 8),
          Text(
            'Choose the city where you want to run.',
            style: bodyStyle(size: 14, color: kFgMuted),
          ),
          const SizedBox(height: 32),
          for (final city in const ['Valencia', 'Madrid', 'La Coma'])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedCity = city;
                    _localError = null;
                  });
                  ref.read(onboardingProvider.notifier).clearError();
                },
                style: OutlinedButton.styleFrom(
                  backgroundColor: _selectedCity == city
                      ? kAccent
                      : Colors.transparent,
                  side: BorderSide(
                    color: _selectedCity == city ? kAccent : kBorder,
                  ),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  city.toUpperCase(),
                  style: bodyStyle(
                    size: 14,
                    color: _selectedCity == city ? kBg : kFg,
                  ),
                ),
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
            onPressed: _onContinue,
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 — Color
// ─────────────────────────────────────────────────────────────────────────────

class _Step3Color extends ConsumerWidget {
  const _Step3Color();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedColor = _hexToColor(state.color);

    Future<void> startPlaying() async {
      final user = AuthService.instance.getCurrentUser();
      if (user == null) return; // guard will handle unauthenticated state
      final userId = user['id'] as String;
      await ref.read(onboardingProvider.notifier).submit(userId);
      // Invalidate the cached profile so _RouteGuard re-fetches and
      // transitions to MapScreen now that profiles.username is non-empty.
      ref.invalidate(profileGateProvider(userId));
    }

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
                final isSelected = color == selectedColor;
                return GestureDetector(
                  onTap: () => ref
                      .read(onboardingProvider.notifier)
                      .setColor(_colorToHex(color)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ]
                          : [],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: bodyStyle(size: 13, color: kDanger),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: state.isLoading ? null : startPlaying,
            child: state.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kBg,
                    ),
                  )
                : const Text('START PLAYING'),
          ),
        ],
      ),
    );
  }
}
