// tool/lint/no_storefront.dart
//
// CI lint guard: ensures that spend_credits_on_power is only referenced from
// the contextual offer screen.
//
// Phase 2 design.md §8 (architect-hardened version).
//
// Usage:
//   dart run tool/lint/no_storefront.dart
//   Exit 0 — no violations.
//   Exit 1 — one or more violations found; offending paths printed to stderr.
//   Exit 2 — script misconfiguration (wrong cwd, lib/ not found).
//
// Hardening against false negatives:
//   - Block comments (/* ... */) are stripped before the search.
//   - Line comments (// ...) are stripped before the search.
//   - Paths normalised to forward-slash POSIX form so the allowList works
//     on both Linux and Windows (WSL).

import 'dart:io';

/// Files that ARE allowed to reference [needle].
///
/// Allowed set:
///   - contextual_offer_screen.dart — the ONLY spend UI (design.md §7).
///   - offers_repository.dart — the repository implementation that calls the
///     edge function via `_client.functions.invoke('spend_credits_on_power')`.
///     The guard exists to prevent *UI / screen* layers from calling the fn
///     directly; the repository layer is the intended choke-point.
const allowList = {
  'lib/screens/contextual_offer_screen.dart',
  'lib/services/database/offers_repository.dart',
};

/// The call site that no file except [allowList] members may contain.
const needle = 'spend_credits_on_power';

Future<void> main() async {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[no_storefront] lib/ not found — run from repo root.');
    exitCode = 2;
    return;
  }

  final offenders = <String>[];

  await for (final entity
      in libDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;

    // Normalise path separators to POSIX so the allowList matches on Windows.
    final rel = entity.path.replaceAll('\\', '/');
    if (allowList.contains(rel)) continue;

    final body = await entity.readAsString();

    // Strip block comments first, then line comments, to avoid matching
    // a needle inside a TODO comment or a commented-out code block.
    final stripped = body
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '') // block comments
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    if (stripped.contains(needle)) {
      offenders.add(rel);
    }
  }

  if (offenders.isNotEmpty) {
    stderr.writeln(
        '[no_storefront] forbidden references to "$needle" found in:');
    for (final o in offenders) {
      stderr.writeln('  - $o');
    }
    exitCode = 1;
  } else {
    stdout.writeln(
        '[no_storefront] OK — "$needle" restricted to ${allowList.length} '
        'allowed file(s).');
  }
}
