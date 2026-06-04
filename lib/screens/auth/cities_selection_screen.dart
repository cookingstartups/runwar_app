import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart';
import '../../theme.dart';
import '../../data/cities_catalog.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cities_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/database/waitlist_repository.dart';
import '../../services/database_service.dart';
import '../../widgets/city_card.dart';
import '../../widgets/milestone_progress_bar.dart';
import '../../widgets/grain_overlay.dart';
import '../../widgets/valencia_button.dart';

class CitiesSelectionScreen extends ConsumerStatefulWidget {
  const CitiesSelectionScreen({super.key});

  @override
  ConsumerState<CitiesSelectionScreen> createState() =>
      _CitiesSelectionScreenState();
}

class _CitiesSelectionScreenState
    extends ConsumerState<CitiesSelectionScreen>
    with SingleTickerProviderStateMixin {
  final Set<String> _selected = {};
  String _search = '';
  String _filter = 'ALL';
  bool _submitting = false;
  String? _otherCity;
  late final AnimationController _fadeCtrl;

  static const _filters = ['ALL', 'UNLOCKED', 'EUROPE', 'AMERICAS', 'ASIA', 'SOON'];

  static const _continentMap = {
    'EUROPE': ['valencia', 'london', 'barcelona'],
    'AMERICAS': ['new-york'],
    'ASIA': ['bali', 'seoul'],
  };

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  List<CityEntry> _applyFilters(List<CityEntry> all) {
    var list = all.where((c) {
      if (_search.isEmpty) return true;
      return c.name.toLowerCase().contains(_search.toLowerCase()) ||
          c.country.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    if (_filter == 'UNLOCKED') {
      list = list.where((c) => c.isUnlocked).toList();
    } else if (_filter == 'SOON') {
      list = list.where((c) => !c.isUnlocked).toList();
    } else if (_continentMap.containsKey(_filter)) {
      final slugs = _continentMap[_filter]!;
      list = list.where((c) => slugs.contains(c.slug)).toList();
    }
    return list;
  }

  Future<void> _showOtherCityDialog() async {
    final ctrl = TextEditingController(text: _otherCity);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Your city',
          style: GoogleFonts.spaceGrotesk(color: kFg, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(color: kFg),
          decoration: InputDecoration(
            hintText: 'e.g. Madrid, Berlin, Tokyo…',
            hintStyle: TextStyle(color: kFgFaint),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: kBorder),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: kAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _otherCity = null);
              Navigator.pop(ctx);
            },
            child: Text('CLEAR', style: TextStyle(color: kFgMuted, fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              setState(() => _otherCity = v.isEmpty ? null : v);
              Navigator.pop(ctx);
            },
            child: Text('SAVE', style: TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _joinWar(String userId) async {
    if (_selected.isEmpty) return;
    setState(() => _submitting = true);
    try {
      // Save "other city" interest to local prefs so the team can review it.
      final other = _otherCity;
      if (other != null && other.isNotEmpty) {
        await DatabaseService.instance.db.insert(
          'prefs',
          {'key': 'city_interest', 'value': other},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await WaitlistRepository.instance.joinCities(userId, _selected.toList());
      ref.invalidate(joinedCitySlugsProvider(userId));
      ref.invalidate(citiesProvider);
      ref.invalidate(profileGateProvider(userId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authProvider).user?['id'] as String? ?? '';
    final citiesAsync = ref.watch(citiesProvider);
    final fade = CurvedAnimation(
        parent: _fadeCtrl, curve: const Cubic(0.22, 1, 0.36, 1));

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: FadeTransition(
              opacity: fade,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: MilestoneProgressBar(currentStep: 1, labels: ['PHONE', 'TERRITORY', 'WAITLIST']),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Text(
                          '${_selected.length} / 3',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            letterSpacing: 2,
                            color: _selected.isEmpty ? kFgMuted : kAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RUNNERS · CHOOSE YOUR GROUND',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            letterSpacing: 3,
                            color: kAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Unlock your city.',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: kFg,
                            height: 0.98,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Search box
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: kBorder),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            style: GoogleFonts.inter(color: kFg, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search cities…',
                              hintStyle: const TextStyle(color: kFgFaint, fontSize: 14),
                              prefixIcon: const Icon(Icons.search, color: kFgMuted, size: 20),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              filled: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Filter chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _filters.map((f) {
                              final active = _filter == f;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => setState(() => _filter = f),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: active ? kAccent : Colors.transparent,
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(
                                        color: active ? kAccent : kBorder,
                                      ),
                                    ),
                                    child: Text(
                                      f,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                        color: active ? kBg : kFgMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // City grid
                  Expanded(
                    child: citiesAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator(color: kAccent)),
                      error: (_, __) => _buildGrid(kCitiesCatalog),
                      data: (cities) => _buildGrid(cities),
                    ),
                  ),
                  // Sticky bottom bar
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    decoration: BoxDecoration(
                      color: kBg,
                      border: Border(top: BorderSide(color: kBorder)),
                    ),
                    child: ValenciaButton(
                      label: _selected.isEmpty
                          ? 'SELECT A CITY'
                          : 'JOIN THE WAR · ${_selected.length} ${_selected.length == 1 ? "CITY" : "CITIES"}',
                      onPressed:
                          _selected.isEmpty ? null : () => _joinWar(userId),
                      enabled: _selected.isNotEmpty,
                      loading: _submitting,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const GrainOverlay(),
        ],
      ),
    );
  }

  Widget _buildGrid(List<CityEntry> all) {
    final filtered = _applyFilters(all);
    if (filtered.isEmpty) {
      return Center(
        child: Text('No cities match.',
            style: GoogleFonts.inter(color: kFgMuted)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3 / 4,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: filtered.length + 1,
      itemBuilder: (_, i) {
        // Last slot — "other city" card
        if (i == filtered.length) {
          final hasOther = _otherCity != null && _otherCity!.isNotEmpty;
          return GestureDetector(
            onTap: _showOtherCityDialog,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasOther ? kAccent : kBorder,
                  width: hasOther ? 1.5 : 1,
                  style: hasOther ? BorderStyle.solid : BorderStyle.solid,
                ),
                color: hasOther
                    ? kAccent.withValues(alpha: 0.08)
                    : kSurface.withValues(alpha: 0.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasOther ? Icons.location_city : Icons.add,
                    color: hasOther ? kAccent : kFgMuted,
                    size: 28,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasOther ? _otherCity! : 'OTHER CITY',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: hasOther ? 12 : 10,
                      letterSpacing: 1.5,
                      color: hasOther ? kFg : kFgMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!hasOther) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Not on the list?',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: kFgFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        final city = filtered[i];
        return CityCard(
          city: city,
          selected: _selected.contains(city.slug),
          onTap: () {
            if (_selected.contains(city.slug)) {
              setState(() => _selected.remove(city.slug));
            } else if (_selected.length >= 3) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Run & conquer to unlock more cities.',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1,
                      color: kFg,
                    ),
                  ),
                  backgroundColor: kSurface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  duration: const Duration(seconds: 3),
                ),
              );
            } else {
              setState(() => _selected.add(city.slug));
            }
          },
        );
      },
    );
  }
}
