# RunWar PoC — Admin Operations

**PoC scope:** SQLite on-device database (`runwar.db`). All admin ops require ADB.

---

## Prerequisites

```bash
# Verify ADB sees the device
adb devices

# One device connected → no need for -s flag
# Multiple devices → prefix every command with: adb -s <serial>
```

---

## Install / update APK

```bash
adb install -r runwar-poc.apk          # first install
adb install -r -d runwar-poc.apk       # downgrade debug build
```

---

## Invite a tester (grant access past the waitlist gate)

Testers sign up in the app, then are stuck on the waitlist screen until `invited_at` is set.

### Step 1 — find the user ID

```bash
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "SELECT id, email, username, invited_at FROM profiles;"
```

### Step 2 — grant invite

```bash
# Replace <USER_ID> with the id from step 1
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "UPDATE profiles SET invited_at = datetime('now') WHERE id = '<USER_ID>';"
```

### Step 3 — verify

```bash
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "SELECT id, email, invited_at FROM profiles;"
```

The tester must force-close and relaunch the app (or tap logout → login) for the route guard to re-evaluate.

---

## Inspect zones and runs

```bash
# All claimed zones
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "SELECT id, owner_id, city, status, influence FROM zones;"

# All recorded runs
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "SELECT id, user_id, city, started_at, ended_at FROM runs ORDER BY started_at DESC LIMIT 20;"
```

---

## Reset a tester's data (nuke + re-onboard)

```bash
# Remove all zones owned by a user
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "DELETE FROM zones WHERE owner_id = '<USER_ID>';"

# Remove all runs for a user
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "DELETE FROM runs WHERE user_id = '<USER_ID>';"

# Reset onboarding (clears username + city + color → sends back to OnboardingFlow)
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "UPDATE profiles SET username = '', city = NULL, color = NULL WHERE id = '<USER_ID>';"
```

---

## Full wipe (factory reset for a test device)

```bash
adb shell run-as com.example.runwar_app sqlite3 databases/runwar.db \
  "DELETE FROM zones; DELETE FROM runs; DELETE FROM profiles; DELETE FROM users;"
```

Or uninstall and reinstall the APK.

---

## Notes

- `run-as com.example.runwar_app` works on debug APKs on non-rooted devices.
- `adb shell` on Windows can be run directly from the Desktop folder.
- The database path is relative inside `run-as` — no absolute path needed.
- Disputes (`status = 'disputed'`) auto-resolve on the next valid run covering the zone.
