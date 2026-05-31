// test/widgets/credits_chip_test.dart
//
// RED phase: imports resolve to files that do not yet exist.
// Each test maps to one GIVEN/WHEN/THEN from design.md §6.1 + spec §6.5.
//
// Design contract (design.md §6.1):
//   CreditsChip — ConsumerWidget — watches creditsBalanceProvider(playerId)
//   Renders current credit balance as a chip in the top bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runwar_app/widgets/credits_chip.dart';
import 'package:runwar_app/providers/economy/credits_provider.dart';
import 'package:runwar_app/services/database/credits_repository.dart';

import '../_helpers/test_container.dart';

// ── Fake ─────────────────────────────────────────────────────────────────────

class _FakeCreditsRepo implements CreditsRepository {
  final int _balance;
  _FakeCreditsRepo(this._balance);

  @override
  Stream<int> watchBalance(String playerId) => Stream.value(_balance);

  @override
  Future<int> fetchBalance(String playerId) async => _balance;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {required ProviderContainer container}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('CreditsChip', () {
    // GIVEN a creditsBalanceProvider resolved to 350
    // WHEN CreditsChip(playerId: 'player-1') is rendered
    // THEN displays '350' in the widget tree
    testWidgets('displays the current credit balance from creditsBalanceProvider',
        (tester) async {
      final container = makeTestContainer(
        creditsRepo: _FakeCreditsRepo(350),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const CreditsChip(playerId: 'player-1'), container: container),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('350'), findsAtLeastNWidgets(1),
          reason: 'CreditsChip must display the current balance');
    });

    // GIVEN a creditsBalanceProvider in loading state (not yet resolved)
    // WHEN CreditsChip is rendered before the stream emits
    // THEN shows a loading indicator (not a crash)
    testWidgets('shows loading indicator while balance is loading', (tester) async {
      // Override with a provider that never emits (simulates loading).
      final container = makeTestContainer(overrides: [
        creditsBalanceProvider('player-1').overrideWith(
          (_) => const Stream<int>.empty(),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const CreditsChip(playerId: 'player-1'), container: container),
      );
      // Don't pumpAndSettle — stream never emits.
      await tester.pump();

      // Widget must not throw or show error text while loading.
      expect(find.byType(CircularProgressIndicator), findsWidgets,
          reason: 'CreditsChip must show a loading indicator when balance is pending');
    });

    // GIVEN creditsBalanceProvider resolves to 0
    // WHEN CreditsChip is rendered
    // THEN displays '0' (zero-balance case)
    testWidgets('displays 0 when balance is zero', (tester) async {
      final container = makeTestContainer(creditsRepo: _FakeCreditsRepo(0));
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(const CreditsChip(playerId: 'player-1'), container: container),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('0'), findsAtLeastNWidgets(1));
    });
  });
}
