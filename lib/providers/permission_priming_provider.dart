// lib/providers/permission_priming_provider.dart
//
// Gate provider for the permission priming screen - mirrors the
// hasPhoneProvider / joinedCitySlugsProvider pattern (profile_provider.dart,
// cities_provider.dart). Resolves to the list of still-missing permissions
// the priming screen must show, or an empty list if priming is done / not
// applicable (auto-heals `perm_priming_done` when a live check shows
// everything granted).
//
// Design reference: infra/meta/specs/runwar/permission-priming/design.md

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/permission_service.dart';

/// Android-only: returns [] unconditionally on iOS.
final permissionPrimingMissingProvider =
    FutureProvider<List<PermKind>>((ref) async {
  if (!Platform.isAndroid) return const [];
  if (await PermissionService.instance.isPrimingDone()) return const [];
  final missing = await PermissionService.instance.missingPermissions();
  if (missing.isEmpty) {
    await PermissionService.instance.markPrimingDone();
    return const [];
  }
  return missing;
});
