import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/profile_service.dart';

/// Fetches the profile for a signed-in user so the route guard can decide
/// which screen to show. Returns null if the profile row doesn't exist.
/// Extracted from main.dart to allow invalidation from onboarding screens
/// without creating a circular import.
final profileGateProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
        (ref, userId) => ProfileService.instance.fetchProfile(userId));
