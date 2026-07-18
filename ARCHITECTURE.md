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

## Deployment

### Backend

| Item | Value |
|---|---|
| Supabase project ref | `glwsmxjptgmxaiyvdqzp` |
| Region | `eu-central-1` (Frankfurt) |
| Migration history | `runwar_app/supabase/` (canonical; `runwar_database` is reference only) |

Core tables: `players`, `runs`, `gps_samples`, `hex_ownership`, `zones`,
`player_economy`, `client_errors`, `ctf_events`, `drops`.

### Mobile app

There is no automated app release pipeline. Builds are produced and side-loaded
manually from the primary checkout on `main` after a branch is merged:

```
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The device connects over wireless ADB, whose port changes each session. A full
build takes roughly 5 minutes. Artifacts land in
`build/app/outputs/flutter-apk/`.

### Landing site

The landing page lives in the separate `runwar_landing` repo (Next.js). It is
linked to a Vercel project (`runwar_landing`, org `cookingstartupscoms-projects`)
which builds from GitHub `main`.

Note that the public domain `runwar.app` does not currently resolve to that
Vercel project. It is a Netlify site: `www.runwar.app` is a CNAME to
`runwar-territory-game.netlify.app`, and the apex resolves to Netlify
(`75.2.60.5`). The Vercel production deployments sit behind deployment
protection and are not publicly reachable. As a result the content served at
`runwar.app` is not built from the current `runwar_landing` source.
