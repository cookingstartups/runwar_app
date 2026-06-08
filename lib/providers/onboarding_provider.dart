import 'dart:io';
import 'dart:math' as math;

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/database_service.dart';
import '../services/database/account_uniqueness_error.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';

class OnboardingState {
  const OnboardingState({
    this.username = '',
    this.city = 'Valencia',
    this.color = '',
    this.step = 0,
    this.avatarPath,
    this.bio = '',
    this.isLoading = false,
    this.error,
  });

  final String username;
  final String city;
  final String color;
  final int step;

  /// Local file path of the selected profile photo. Null if none chosen.
  final String? avatarPath;

  /// "About you" bio text, max 160 chars.
  final String bio;

  final bool isLoading;
  final String? error;

  OnboardingState copyWith({
    String? username,
    String? city,
    String? color,
    int? step,
    Object? avatarPath = _sentinel,
    String? bio,
    bool? isLoading,
    Object? error = _sentinel,
  }) =>
      OnboardingState(
        username: username ?? this.username,
        city: city ?? this.city,
        color: color ?? this.color,
        step: step ?? this.step,
        avatarPath:
            identical(avatarPath, _sentinel) ? this.avatarPath : avatarPath as String?,
        bio: bio ?? this.bio,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(OnboardingState(color: _randomHexColor()));

  static String _randomHexColor() {
    final r = math.Random();
    return '#${r.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  /// Updates username in-memory. Does NOT advance step (single-screen flow).
  void setUsername(String v) {
    state = state.copyWith(username: v.trim(), error: null);
  }

  /// Updates city in-memory.
  void setCity(String v) {
    state = state.copyWith(city: v, error: null);
  }

  /// Updates color in-memory; does NOT advance step.
  void setColor(String v) {
    state = state.copyWith(color: v, error: null);
  }

  /// Stores the local file path of the selected avatar photo.
  void setAvatarPath(String path) {
    state = state.copyWith(avatarPath: path, error: null);
  }

  /// Updates the bio text in-memory.
  void setBio(String v) {
    state = state.copyWith(bio: v, error: null);
  }

  /// Persists username, city, color, avatar, and bio in a single call.
  ///
  /// Steps:
  /// 1. If `avatarPath != null`: upload bytes to Supabase Storage, get public URL.
  /// 2. Read EXIF metadata from the file bytes (GPS, datetime, device, dimensions).
  /// 3. Call `ProfileService.updateProfile` with all fields.
  ///
  /// POC-013 (_RouteGuard) owns route re-evaluation after this succeeds.
  Future<void> submit(String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      String? avatarUrl;
      Map<String, dynamic>? avatarMetadata;

      if (state.avatarPath != null) {
        final file = File(state.avatarPath!);
        final bytes = await file.readAsBytes();

        // ── EXIF extraction ─────────────────────────────────────────────────
        double? gpsLat;
        double? gpsLng;
        String? capturedAt;
        String? deviceMake;
        String? deviceModel;
        int? imgWidth;
        int? imgHeight;

        try {
          final tags = await readExifFromBytes(bytes);

          final dto = tags['EXIF DateTimeOriginal']?.printable;
          if (dto != null && dto.isNotEmpty) capturedAt = dto;

          final latRef = tags['GPS GPSLatitudeRef']?.printable;
          final latTag = tags['GPS GPSLatitude'];
          final lngRef = tags['GPS GPSLongitudeRef']?.printable;
          final lngTag = tags['GPS GPSLongitude'];
          if (latTag != null && latRef != null) {
            gpsLat = _parseGpsDms(latTag.printable, latRef);
          }
          if (lngTag != null && lngRef != null) {
            gpsLng = _parseGpsDms(lngTag.printable, lngRef);
          }

          deviceMake = tags['Image Make']?.printable;
          deviceModel = tags['Image Model']?.printable;

          final wStr = tags['EXIF ExifImageWidth']?.printable ??
              tags['Image ImageWidth']?.printable;
          final hStr = tags['EXIF ExifImageLength']?.printable ??
              tags['Image ImageLength']?.printable;
          if (wStr != null) imgWidth = int.tryParse(wStr);
          if (hStr != null) imgHeight = int.tryParse(hStr);
        } catch (e) {
          debugPrint('[OnboardingNotifier] EXIF read error (non-fatal): $e');
        }

        avatarMetadata = {
          'captured_at': capturedAt ?? DateTime.now().toIso8601String(),
          'gps_lat': gpsLat,
          'gps_lng': gpsLng,
          'device_make': deviceMake,
          'device_model': deviceModel,
          'width': imgWidth,
          'height': imgHeight,
          'file_size_bytes': bytes.length,
        };

        // ── Upload to Supabase Storage ───────────────────────────────────────
        final supabase = SupabaseService.instance.supabase;
        await supabase.storage.from('avatars').uploadBinary(
          '$userId/avatar.jpg',
          bytes,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
        avatarUrl =
            supabase.storage.from('avatars').getPublicUrl('$userId/avatar.jpg');
      }

      await DatabaseService.instance.joinCityWaitlist(userId, state.city.toLowerCase());

      await ProfileService.instance.updateProfile(
        userId,
        username: state.username,
        color: state.color,
        avatarUrl: avatarUrl,
        bio: state.bio.isEmpty ? null : state.bio,
        avatarMetadata: avatarMetadata,
      );

      state = state.copyWith(isLoading: false);
    } catch (e) {
      final dupMsg = accountUniquenessMessage(e);
      state = state.copyWith(
        isLoading: false,
        error: dupMsg ?? 'Could not save profile: $e',
      );
    }
  }

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }

  /// Parses a DMS string like `[40, 26, 46.123]` and a ref (`N`/`S`/`E`/`W`)
  /// into a signed decimal degree. Returns null on any parse failure.
  static double? _parseGpsDms(String dms, String ref) {
    try {
      final clean = dms.replaceAll(RegExp(r'[\[\]]'), '');
      final parts = clean.split(',').map((s) => s.trim()).toList();
      if (parts.length != 3) return null;

      double frac(String s) {
        if (s.contains('/')) {
          final n = s.split('/');
          return double.parse(n[0].trim()) / double.parse(n[1].trim());
        }
        return double.parse(s);
      }

      final deg = frac(parts[0]);
      final min = frac(parts[1]);
      final sec = frac(parts[2]);
      double decimal = deg + min / 60.0 + sec / 3600.0;
      if (ref == 'S' || ref == 'W') decimal = -decimal;
      return decimal;
    } catch (_) {
      return null;
    }
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
        (ref) => OnboardingNotifier());
