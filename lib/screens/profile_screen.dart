import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../services/zones_service.dart';
import '../theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth.user?['id'] as String?;

    // Defensive: route guard normally prevents reaching here without a user.
    if (userId == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final profileAsync = ref.watch(profileGateProvider(userId));

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: profileAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load profile: $e',
              style: bodyStyle(size: 14, color: kDanger),
            ),
          ),
          data: (p) {
            if (p == null) return const Center(child: SizedBox.shrink());
            final username = (p['username'] as String?) ?? '';
            final city = (p['city'] as String?) ?? '';
            final colorHex = (p['color'] as String?) ?? '#FF7A00';

            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // AC-9: username
                  Text(username.toUpperCase(), style: displayStyle(size: 36)),
                  const SizedBox(height: 8),
                  // AC-9: city
                  Text(city, style: bodyStyle(size: 16)),
                  const SizedBox(height: 24),
                  // AC-9: color swatch — filled circle 32×32
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _hexToColor(colorHex),
                          shape: BoxShape.circle,
                          border: Border.all(color: kBorder, width: 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        colorHex,
                        style: monoStyle(size: 12, color: kFgMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // AC-10: zones-owned count — static snapshot at mount.
                  // Sourced exclusively from ZonesService (AC-10 invariant).
                  FutureBuilder<int>(
                    future: ZonesService.instance.countOwnedByUser(userId),
                    builder: (context, snap) {
                      final n = snap.data ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ZONES OWNED', style: monoStyle()),
                          const SizedBox(height: 4),
                          Text(
                            '$n',
                            style: displayStyle(size: 48, color: kAccent),
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  // AC-11: log out button
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(authProvider.notifier).signOut(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: Text(
                      'LOG OUT',
                      style: bodyStyle(size: 12, color: kFg),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Parses '#RRGGBB' or '#AARRGGBB' hex color strings.
/// Returns kAccent on any parse failure.
Color _hexToColor(String hex) {
  try {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return kAccent;
  }
}
