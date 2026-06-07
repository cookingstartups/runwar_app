import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/daily_missions_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/territory_provider.dart';
import '../services/profile_service.dart';
import '../theme.dart';

/// Edit screen for avatar, color, bio, and (gated) username.
///
/// Username editing is unlocked only when:
///   - playerTerritoryKm2Provider(userId) >= kUsernameUnlockKm2 (1.0 km²)
///   - dailyStreakProvider(userId).current >= kUsernameUnlockStreakDays (7 days)
///
/// All other fields (bio, color) are always editable.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  String? _selectedColor;
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _initFromProfile(Map<String, dynamic> profile) {
    if (_initialized) return;
    _initialized = true;
    _usernameCtrl = TextEditingController(
      text: (profile['username'] as String?) ?? '',
    );
    _bioCtrl = TextEditingController(
      text: (profile['bio'] as String?) ?? '',
    );
    _selectedColor = (profile['color'] as String?) ?? kPlayerColors.first;
  }

  Color _hexToColor(String hex) {
    try {
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return kAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final userId = auth.user?['id'] as String?;

    if (userId == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final profileAsync = ref.watch(profileGateProvider(userId));

    // Resolve territory and streak for the username unlock gate.
    final km2Async = ref.watch(playerTerritoryKm2Provider(userId));
    final streakAsync = ref.watch(dailyStreakProvider(userId));

    final usernameUnlocked = km2Async.maybeWhen(
      data: (km2) => streakAsync.maybeWhen(
        data: (s) =>
            km2 >= kUsernameUnlockKm2 && s.current >= kUsernameUnlockStreakDays,
        orElse: () => false,
      ),
      orElse: () => false,
    );

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            'Could not load profile: $e',
            style: bodyStyle(size: 14, color: kDanger),
          ),
        ),
      ),
      data: (profile) {
        if (profile == null) return const Scaffold(body: SizedBox.shrink());

        // Lazy-init controllers once profile data is available.
        _initFromProfile(profile);

        return Scaffold(
          backgroundColor: kBg,
          appBar: AppBar(
            title: Text('EDIT PROFILE', style: displayStyle(size: 20)),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Color picker ────────────────────────────────────────
                  Text(
                    'PLAYER COLOR',
                    style: monoStyle(size: 10, color: kFgMuted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kPlayerColors.map((hex) {
                      final isSelected = hex == _selectedColor;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = hex),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _hexToColor(hex),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: kFg, width: 2.5)
                                : Border.all(
                                    color: kBorder,
                                    width: 1,
                                  ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: _hexToColor(hex)
                                          .withValues(alpha: 0.5),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  // ── Bio field ───────────────────────────────────────────
                  Text(
                    'BIO',
                    style: monoStyle(size: 10, color: kFgMuted),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bioCtrl,
                    maxLength: 160,
                    maxLines: 3,
                    style: bodyStyle(size: 14, color: kFg),
                    decoration: const InputDecoration(
                      hintText: 'Tell the city about yourself...',
                      counterStyle: TextStyle(
                        color: kFgFaint,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Username field (gated) ──────────────────────────────
                  Text(
                    'USERNAME',
                    style: monoStyle(size: 10, color: kFgMuted),
                  ),
                  const SizedBox(height: 8),
                  if (usernameUnlocked)
                    TextField(
                      controller: _usernameCtrl,
                      style: bodyStyle(size: 14, color: kFg),
                      decoration: const InputDecoration(
                        hintText: 'Enter username',
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: kFgFaint,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Unlock at 1.0 km² owned + 7-day streak',
                              style: bodyStyle(size: 13, color: kFgMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 40),

                  // ── Save button ─────────────────────────────────────────
                  ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () => _onSave(
                              context,
                              userId: userId,
                              usernameUnlocked: usernameUnlocked,
                            ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: kBg,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'SAVE',
                            style: bodyStyle(size: 12, color: kBg),
                          ),
                  ),

                  // Avatar TODO: image-picker avatar upload is out of scope for
                  // this iteration. avatar_url column exists in the DB (migration
                  // 0034). A future task will wire ImagePicker + Supabase Storage.
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onSave(
    BuildContext context, {
    required String userId,
    required bool usernameUnlocked,
  }) async {
    // Capture messenger and navigator before the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _saving = true);
    try {
      await ProfileService.instance.updateProfile(
        userId,
        username: usernameUnlocked ? _usernameCtrl.text.trim() : null,
        color: _selectedColor,
        bio: _bioCtrl.text.trim(),
      );
      ref.invalidate(profileGateProvider(userId));
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            duration: Duration(seconds: 2),
          ),
        );
        navigator.pop();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
