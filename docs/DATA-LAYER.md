# RunWar — Data Layer

## Service Contracts

| Service | Responsibility | May import `supabase_flutter`? |
|---|---|---|
| `SupabaseService` | Client init, session lifecycle, auth token exchange | ✅ yes |
| `DatabaseService` | All DB reads / writes / realtime | ✅ yes |
| `AuthService` | In-memory session (`_currentUser`), profile upsert | ❌ no (delegates to above) |
| `GoogleAuthService` | Google picker + `signInWithIdToken` | ❌ no (uses SupabaseService) |

**Rule:** Screens, providers, and all services except the two above must never
import `supabase_flutter` directly. Call a `DatabaseService` method instead.

## Provider Map

```
authProvider                    StateNotifierProvider<AuthNotifier, AuthState>
showcaseSeenProvider            FutureProvider<bool>              (SharedPreferences)

-- route guard gates (family, keyed by userId) --
hasPhoneProvider(userId)        FutureProvider.family<bool, String>
joinedCitySlugsProvider(userId) FutureProvider.family<List, String>
profileGateProvider(userId)     FutureProvider.family<Map?, String>

-- game state --
zonesProvider                   StreamProvider / FutureProvider
runRecorderProvider             StateNotifierProvider
missionsProvider                FutureProvider.family
economyProvider (credits)       FutureProvider.family
superpowerProvider              FutureProvider.family
trustProvider                   FutureProvider.family
```

## Supabase Tables (key ones)

| Table | Notes |
|---|---|
| `players` | One row per auth user. FK → `auth.users`. |
| `bots` | NPC game entities. No auth FK. |
| `players_and_bots` | Read-only SQL UNION view. |
| `zones` | Territory polygons with owner, status, influence. |
| `invitation_codes` | Waitlist access codes. |
| `code_redemptions` | Usage log for invitation codes. |

## Data Flow Example: Sign-in → MainShell

```
GoogleSignIn.signIn()
  → SupabaseService.signInWithIdToken()
  → DatabaseService.upsertProfileIgnore()   // INSERT OR IGNORE players row
  → AuthNotifier.state = { user }
  → _RouteGuard rebuilds
  → hasPhoneProvider(userId) fetches
  → joinedCitySlugsProvider(userId) fetches
  → profileGateProvider(userId) fetches
  → (all gates pass) → MainShell
```
