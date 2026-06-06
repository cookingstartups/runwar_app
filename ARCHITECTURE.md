# RunWar App — Architecture

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter (Dart) |
| State | Riverpod (`StateNotifierProvider`, `FutureProvider`, `FutureProvider.family`) |
| Auth | Google Sign-In → Supabase `signInWithIdToken` |
| Database | Supabase (PostgreSQL + RLS) |
| Maps | `flutter_map` + OpenStreetMap tiles |
| Notifications | Firebase Cloud Messaging |

## Directory Layout

```
lib/
  main.dart              # Entry point, ProviderScope, MaterialApp, _RouteGuard
  theme.dart             # App colour palette and text styles
  config/                # Static config (Supabase URL, game constants)
  data/                  # Static data (cities catalog)
  geo/                   # Geo utilities (lasso selection)
  models/                # Plain Dart data classes (DailyMission, etc.)
  providers/             # Riverpod providers — one file per domain
  screens/               # One file per screen, grouped by flow
    auth/                # Login, PhoneLink, CitiesSelection, JoinWarConfirmation
    onboarding/          # OnboardingFlow (username + avatar setup)
  services/              # Business logic — no UI
  widgets/               # Reusable leaf widgets
  beta/                  # Experimental / unreleased features
docs/
  ADMIN.md               # Supabase admin operations
  AUTH.md                # Auth flow and route guard detail
  DATA-LAYER.md          # Services, providers, and Supabase boundary rules
```

## Navigation Model

`_RouteGuard` (in `main.dart`) is the `home:` widget of `MaterialApp`. It watches
auth + profile state and returns the correct screen directly — no `Navigator.push`.
Gate sequence: **unauthenticated → phone → cities → invitation → username → onboarding → main**.

See [docs/AUTH.md](docs/AUTH.md) for the full gate decision tree.

## Data Layer

All Supabase calls go through `DatabaseService` or `SupabaseService`. Screens and
providers never import `supabase_flutter` directly.

See [docs/DATA-LAYER.md](docs/DATA-LAYER.md) for service contracts and provider patterns.
