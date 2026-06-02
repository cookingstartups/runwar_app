// lib/providers/trust/invitation_providers.dart
// Phase 3 trust layer — invitation repository + service providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/database/invitations_repository.dart';
import '../../services/trust/invitation_service.dart';
import '../repositories.dart';

final invitationsRepoProvider = Provider<InvitationsRepository>(
  (ref) => SupabaseInvitationsRepository(ref.read(supabaseClientProvider)),
);

final invitationServiceProvider = Provider<InvitationService>(
  (ref) => InvitationService(ref.read(invitationsRepoProvider)),
);

/// Stream of the current user's invitation codes (raw rows, newest first).
final myInvitationCodesProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(invitationServiceProvider).myInvites(),
);
