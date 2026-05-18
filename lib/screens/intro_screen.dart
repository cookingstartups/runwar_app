import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

class _Card {
  final String emoji;
  final String headline;
  final String body;
  _Card(this.emoji, this.headline, this.body);
}

final _cards = [
  _Card(
    '🏃',
    'Run it.\nOwn it.',
    'Lasso any city block with your GPS route.\nThat territory is yours — until someone takes it.',
  ),
  _Card(
    '⚔️',
    'Defend\nyour ground.',
    'Rivals run through your zones to lower your influence.\nHold your territory or lose it forever.',
  ),
  _Card(
    '🔒',
    'Invitation\nonly.',
    'RunWar isn\'t open to everyone.\nYou need an invite — or you join the waitlist.',
  ),
];

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  int _page = 0;

  void _next() {
    if (_page < _cards.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.pushReplacementNamed(context, '/request-access');
    }
  }

  void _skip() => Navigator.pushReplacementNamed(context, '/request-access');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _cards.length,
            itemBuilder: (_, i) => _CardPage(card: _cards[i]),
          ),

          // Skip button (hidden on last card)
          if (_page < _cards.length - 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 24,
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  'SKIP',
                  style: monoStyle(size: 10, color: kFgFaint),
                ),
              ),
            ),

          // Dots + CTA
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 40,
            left: 24,
            right: 24,
            child: Column(
              children: [
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _cards.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _page ? kAccent : kFgFaint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _next,
                  child: Text(
                    _page < _cards.length - 1 ? 'NEXT →' : 'REQUEST ACCESS →',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      color: kBg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPage extends StatelessWidget {
  final _Card card;
  const _CardPage({required this.card});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 120, 32, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 24),
          Text(
            card.headline.toUpperCase(),
            style: GoogleFonts.bebasNeue(
              fontSize: 52,
              height: 1.1,
              color: kFg,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          Text(card.body, style: bodyStyle(size: 15, color: kFgMuted)),
        ],
      ),
    );
  }
}
