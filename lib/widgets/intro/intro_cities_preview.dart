// lib/widgets/intro/intro_cities_preview.dart
//
// IntroCitiesPreview — slide 10 ("Choose your ground."). A non-interactive,
// display-only preview of the real city-selection UI, visually mirroring
// CitiesSelectionScreen / CityCard / kCitiesCatalog (R-28). Renders the
// REAL CityCard widget against the REAL kCitiesCatalog (reuse, not a
// duplicate widget) plus a static (non-wired) replica of the search box +
// filter-chip row for layout fidelity only — no TextField/onChanged, no
// filtering state, since R-28 only requires those elements to be visible.
//
// The whole grid is wrapped in IgnorePointer so no tap can change selection
// state before signup (R-28's "honest preview" constraint) — the shipped
// CitiesSelectionScreen remains the only place real selection happens.

import 'package:flutter/material.dart';

import '../../data/cities_catalog.dart';
import '../../theme.dart';
import '../city_card.dart';

class IntroCitiesPreview extends StatelessWidget {
  const IntroCitiesPreview({super.key});

  // Decorative-only filter labels (static, non-wired — R-28 only requires
  // filter chips to be visible, not to be functionally identical to
  // CitiesSelectionScreen's real filters). "LOCKED" is used instead of the
  // real screen's "SOON" filter label so this purely cosmetic chip never
  // collides with a CityCard's own "SOON" status badge text in this preview.
  static const _filters = [
    'ALL',
    'UNLOCKED',
    'EUROPE',
    'AMERICAS',
    'ASIA',
    'LOCKED'
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview label — honest labeling that real selection happens after
          // signup (R-30).
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: kAccent2.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(100),
              color: kAccent2.withValues(alpha: 0.08),
            ),
            child: Text(
              'ONBOARDING PREVIEW · YOU PICK FOR REAL AFTER SIGNUP',
              textAlign: TextAlign.center,
              style: monoStyle(size: 8, color: kAccent2),
            ),
          ),
          const SizedBox(height: 14),
          // Static decorative search box — visual fidelity only, not wired.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: kFgMuted, size: 18),
                  const SizedBox(width: 8),
                  Text('Search cities…',
                      style: bodyStyle(size: 13, color: kFgFaint)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Static decorative filter chips.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 26,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _filters.map((f) {
                  final active = f == 'ALL';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: active ? kAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: active ? kAccent : kBorder),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1.2,
                          color: active ? kBg : kFgMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Non-interactive city-card grid — Valencia OPEN, 5 others SOON with
          // an invite-to-unlock affordance (R-29). IgnorePointer makes taps
          // inert before signup (R-28). shrinkWrap + NeverScrollableScrollPhysics
          // so the grid sizes to its content (all 6 cards always built, not
          // virtualized against an outer viewport) inside the scrollable column
          // above.
          IgnorePointer(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 3 / 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: kCitiesCatalog.length,
              itemBuilder: (_, i) {
                final city = kCitiesCatalog[i];
                return CityCard(
                  city: city,
                  selected: false,
                  inviteHint: true,
                  onTap: () {},
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
