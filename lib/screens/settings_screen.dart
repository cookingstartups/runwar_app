// SettingsScreen renders its four sections in this fixed order:
// PREFERENCES, ACCOUNT, SUPPORT, ABOUT.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/cities_provider.dart';
import '../services/database_service.dart';
import '../theme.dart';
import '../utils/string_utils.dart';
import 'auth/cities_selection_screen.dart';
import 'support_ticket_screen.dart';
import '../models/support_ticket.dart';

/// Pref keys persisted through DatabaseService.getPref/setPref (Supabase's
/// `prefs` table) - no new tables introduced for settings state.
const _kUnitsPrefKey = 'units';
const _kPushPrefKey = 'notif_push_enabled';
const _kStreakPrefKey = 'notif_streak_reminder_enabled';
const _kRunTrackingPrefKey = 'notif_run_tracking_enabled';

/// Settings shell: Preferences, Account, Support, About - in that fixed
/// order (design.md section 3.1 / R1-AC2). Logout stays exclusively on
/// ProfileScreen and is never duplicated here.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth.user?['id'] as String?;
    if (userId == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text('SETTINGS', style: displayStyle(size: 20))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            _SettingsSection(
              title: 'PREFERENCES',
              children: [
                _UnitsRow(userId: userId),
                const SizedBox(height: 16),
                _NotificationTogglesSection(userId: userId),
              ],
            ),
            _SettingsSection(
              title: 'ACCOUNT',
              children: [
                _CityRow(userId: userId),
              ],
            ),
            _SettingsSection(
              title: 'SUPPORT',
              children: [
                _SupportRow(
                  label: 'Open a support ticket',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SupportTicketScreen(
                        kind: SupportTicketKind.support,
                      ),
                    ),
                  ),
                ),
                _SupportRow(
                  label: 'Delete my account',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SupportTicketScreen(
                        kind: SupportTicketKind.accountDeletion,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const _SettingsSection(
              title: 'ABOUT',
              children: [_AboutRow()],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section / row shells ───────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: monoStyle(size: 11, color: kFgMuted)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: bodyStyle(size: 14, color: kFg))),
            const Icon(Icons.chevron_right, color: kFgMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Preferences: units ──────────────────────────────────────────────────────

/// Units segmented control (KM / MI), persisted via DatabaseService's
/// existing getPref/setPref primitives - no new table for this.
class _UnitsRow extends StatefulWidget {
  const _UnitsRow({required this.userId});
  final String userId;

  @override
  State<_UnitsRow> createState() => _UnitsRowState();
}

class _UnitsRowState extends State<_UnitsRow> {
  String _units = 'km';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved =
        await DatabaseService.instance.getPref(widget.userId, _kUnitsPrefKey);
    if (mounted) {
      setState(() {
        _units = saved ?? 'km';
        _loaded = true;
      });
    }
  }

  Future<void> _set(String value) async {
    setState(() => _units = value);
    await DatabaseService.instance.setPref(widget.userId, _kUnitsPrefKey, value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Units', style: bodyStyle(size: 14, color: kFg))),
          _UnitChip(label: 'KM', selected: _units == 'km', onTap: () => _set('km')),
          const SizedBox(width: 8),
          _UnitChip(label: 'MI', selected: _units == 'mi', onTap: () => _set('mi')),
        ],
      ),
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? kAccent : kBorder),
        ),
        child: Text(
          label,
          style: monoStyle(size: 11, color: selected ? kBg : kFgMuted),
        ),
      ),
    );
  }
}

// ── Preferences: notification toggles ──────────────────────────────────────

/// Three real, specifically-labeled notification channels: push
/// notifications, the daily streak reminder, and run tracking / foreground
/// service notices - persisted individually via getPref/setPref.
class _NotificationTogglesSection extends StatefulWidget {
  const _NotificationTogglesSection({required this.userId});
  final String userId;

  @override
  State<_NotificationTogglesSection> createState() =>
      _NotificationTogglesSectionState();
}

class _NotificationTogglesSectionState
    extends State<_NotificationTogglesSection> {
  bool _loaded = false;
  bool _push = true;
  bool _streak = true;
  bool _runTracking = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = DatabaseService.instance;
    final push = await ds.getPref(widget.userId, _kPushPrefKey);
    final streak = await ds.getPref(widget.userId, _kStreakPrefKey);
    final runTracking = await ds.getPref(widget.userId, _kRunTrackingPrefKey);
    if (!mounted) return;
    setState(() {
      _push = (push ?? 'true') == 'true';
      _streak = (streak ?? 'true') == 'true';
      _runTracking = (runTracking ?? 'true') == 'true';
      _loaded = true;
    });
  }

  Future<void> _setPush(bool value) async {
    setState(() => _push = value);
    await DatabaseService.instance
        .setPref(widget.userId, _kPushPrefKey, value.toString());
  }

  Future<void> _setStreak(bool value) async {
    setState(() => _streak = value);
    await DatabaseService.instance
        .setPref(widget.userId, _kStreakPrefKey, value.toString());
  }

  Future<void> _setRunTracking(bool value) async {
    setState(() => _runTracking = value);
    await DatabaseService.instance
        .setPref(widget.userId, _kRunTrackingPrefKey, value.toString());
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      children: [
        _ToggleRow(
          label: 'Push notifications',
          value: _push,
          onChanged: _setPush,
        ),
        _ToggleRow(
          label: 'Daily streak reminder',
          value: _streak,
          onChanged: _setStreak,
        ),
        _ToggleRow(
          label: 'Run tracking notifications',
          value: _runTracking,
          onChanged: _setRunTracking,
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: bodyStyle(size: 14, color: kFg))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: kAccent,
          ),
        ],
      ),
    );
  }
}

// ── Account: city change ────────────────────────────────────────────────────

class _CityRow extends ConsumerWidget {
  const _CityRow({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = ref.watch(joinedCitySlugsProvider(userId)).valueOrNull ?? [];
    final currentSlug = joined.isNotEmpty ? joined.first : null;
    final currentCity = currentSlug != null ? capitalize(currentSlug) : 'Not set';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CitiesSelectionScreen(
            mode: CitiesSelectionMode.change,
            currentCitySlug: currentSlug,
          ),
        ),
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('City', style: bodyStyle(size: 14, color: kFg)),
                  const SizedBox(height: 4),
                  Text(currentCity, style: monoStyle(size: 11, color: kFgMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kFgMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── About ────────────────────────────────────────────────────────────────

class _AboutRow extends StatelessWidget {
  const _AboutRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final version = snap.data?.version ?? '';
          final build = snap.data?.buildNumber ?? '';
          final label = version.isEmpty ? 'RunWar' : 'RunWar v$version ($build)';
          return Text(label, style: bodyStyle(size: 13, color: kFgMuted));
        },
      ),
    );
  }
}
