# RunWar — Auth Flow & Route Guard

## Sign-In Flow

```
LoginScreen
  └─ "CONTINUE WITH GOOGLE" button
       └─ AuthNotifier.signInWithGoogle()
            ├─ state.isLoading = true
            ├─ GoogleAuthService.signIn()
            │    └─ GoogleSignIn.signIn()        ← interactive picker (never silent)
            ├─ SupabaseService.signInWithIdToken()
            ├─ DatabaseService.upsertProfileIgnore()
            ├─ state.user = { id, email }
            └─ state.isLoading = false
```

`signInSilently()` is explicitly removed — it returns stale system-cached tokens that
Supabase rejects with `400 Bad ID token`.

## Route Guard (`_RouteGuard` in `main.dart`)

`_RouteGuard` is the `home:` widget of `MaterialApp`. It must never be replaced via
`Navigator.pushReplacement` — doing so disposes it and breaks post-login navigation.

When `showcaseSeen = false` (fresh install), the route guard renders `IntroScreen`.
When the intro is complete, `IntroScreen` calls `ref.invalidate(showcaseSeenProvider)` —
the route guard re-evaluates and renders `LoginScreen` without any Navigator navigation.

### Gate Sequence

| # | Condition | Screen shown |
|---|---|---|
| — | `user == null && !showcaseSeen` | `IntroScreen` |
| — | `user == null && showcaseSeen` | `LoginScreen` |
| 1 | `phone == null` | `PhoneLinkScreen` |
| 2 | `joinedCitySlugs.isEmpty` | `CitiesSelectionScreen` |
| 3 | `invited_at == null` | `JoinWarConfirmationScreen` |
| 4 | `username == ''` | `OnboardingFlow` |
| 5a | `needsMission1` | `FirstMissionBriefingScreen` |
| 5b | `needsMission2` | `FirstAttackBriefingScreen` |
| — | all pass | `MainShell` |

## Error Snackbars (Riverpod pattern)

`LoginScreen` uses `ref.listen<AuthState>(authProvider, ...)` in `build()` to display
error snackbars. Never use `if(mounted)` in async callbacks — when `isLoading = true`
the route guard replaces `LoginScreen` with `_GateLoading()`, unmounting the old instance.
`ref.listen` fires on the **new** instance after the guard re-renders.

## Session Restore

On cold boot, `main()` calls `AuthService.restoreSessionFromSupabase()`. If a valid
Supabase session exists, `_currentUser` is populated from it — the route guard skips
`LoginScreen` entirely and evaluates the profile gates.
