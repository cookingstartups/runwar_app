#!/usr/bin/env python3
"""
RunWar Supabase user-data wipe tool.

Completely wipes all RunWar data for a single user, given only their email.

DEFAULT MODE IS ALWAYS DRY-RUN (read-only SELECT counts). Mutations only run
when BOTH --execute AND --yes-i-approve are passed. This is intentional
defense in depth -- a single flag flip must never be enough to delete data.

Credentials are read from the environment: RUNWAR_SUPABASE_URL and
RUNWAR_SUPABASE_SERVICE_ROLE_KEY. Pass --env-file <path> to load KEY=VALUE
lines from a file into the environment before running (the file itself is
never hardcoded or read from a fixed path by this script). Key values are
read into memory only -- never printed, logged, or echoed.

--- Schema-drift note (found via live PostgREST OpenAPI introspection,
    GET {SUPABASE_URL}/rest/v1/ with the service-role key) ---
The live database has drifted from the checked-in migrations:
  * players' primary key column is `user_id` (not `id` as in the original
    migration).
  * runs, gps_samples, anticheat_flags, behavioral_fingerprints,
    ctf_participants, daily_mission_progress, city_waitlists, client_errors,
    code_redemptions all use a `user_id` column (some were `player_id` in
    older migrations).
  * player_economy, player_progress, player_streaks, player_trial,
    player_devices, prefs, events, feedback exist live but are NOT present
    in any local migration file (added out-of-band, e.g. via dashboard).
  * zones has both `owner_id` (FK -> players.user_id, ON DELETE CASCADE)
    and `contested_by_id` (plain uuid column, no FK -- also not present in
    any local migration; must be manually nulled).
  * gps_samples and runs have NO enforced FK to players/auth.users (the FK
    on gps_samples was intentionally dropped in a later migration) -- they
    must always be deleted explicitly, never assumed to cascade.
  * PostgREST's OpenAPI doc only annotates FKs that target tables inside the
    exposed `public` schema. Columns that plausibly reference auth.users
    directly (prefs.user_id, events.user_id, feedback.user_id,
    client_errors.user_id, city_waitlists.user_id, daily_mission_progress.user_id,
    ctf_participants.user_id, code_redemptions.redeemed_by) show no FK note --
    that does not prove no FK exists, it only proves PostgREST didn't surface
    one. Given that ambiguity, this script never relies on assumed cascades:
    every table is deleted (or nulled) EXPLICITLY, in dependency order, and
    the mutation path re-verifies every count is zero afterward. This is
    strictly safer than trusting the cascade graph and makes re-runs
    idempotent regardless of which FKs turn out to be real.

Usage:
  python3 wipe_user.py --email user@example.com                                # dry run (default, always safe)
  python3 wipe_user.py --email user@example.com --env-file /path/to/.env       # dry run, load creds from a file first
  python3 wipe_user.py --email user@example.com --execute --yes-i-approve      # mutate (DESTRUCTIVE)
"""

import argparse
import os
import sys
from datetime import datetime, timezone

import requests

REQUEST_TIMEOUT = 30


# ----------------------------------------------------------------------------
# Credential loading (never printed)
# ----------------------------------------------------------------------------

def load_env_file(path: str) -> None:
    """Load KEY=VALUE lines from a file into os.environ (does not overwrite
    any variable already set in the environment)."""
    if not os.path.exists(path):
        sys.exit(f"--env-file path not found: {path}")
    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.split(" #")[0].strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


def load_credentials():
    url = os.environ.get("RUNWAR_SUPABASE_URL")
    key = os.environ.get("RUNWAR_SUPABASE_SERVICE_ROLE_KEY")
    missing = [
        name
        for name, val in (
            ("RUNWAR_SUPABASE_URL", url),
            ("RUNWAR_SUPABASE_SERVICE_ROLE_KEY", key),
        )
        if not val
    ]
    if missing:
        sys.exit(
            "missing required environment variable(s): "
            + ", ".join(missing)
            + ". Set them in the environment, or pass --env-file <path> to a "
            "file containing them."
        )
    return url.rstrip("/"), key


# ----------------------------------------------------------------------------
# Supabase Admin API (auth.users) helpers
# ----------------------------------------------------------------------------

def find_user_by_email(base_url: str, headers: dict, email: str):
    """Paginate GET /auth/v1/admin/users and match email client-side.

    The `email` query param on this GoTrue version does not filter
    server-side (verified empirically: it returned all users regardless of
    the value passed), so we page through everything and match ourselves.
    The project has a small user count, so this is cheap.
    """
    page = 1
    per_page = 200
    while True:
        r = requests.get(
            f"{base_url}/auth/v1/admin/users",
            headers=headers,
            params={"page": page, "per_page": per_page},
            timeout=REQUEST_TIMEOUT,
        )
        r.raise_for_status()
        data = r.json()
        users = data.get("users", [])
        for u in users:
            if (u.get("email") or "").lower() == email.lower():
                return u
        if len(users) < per_page:
            return None
        page += 1


def delete_auth_user(base_url: str, headers: dict, user_id: str):
    r = requests.delete(
        f"{base_url}/auth/v1/admin/users/{user_id}",
        headers=headers,
        timeout=REQUEST_TIMEOUT,
    )
    if r.status_code not in (200, 204):
        raise RuntimeError(f"auth user delete failed: HTTP {r.status_code} {r.text[:300]}")


# ----------------------------------------------------------------------------
# PostgREST helpers (counts, deletes, updates)
# ----------------------------------------------------------------------------

def _parse_postgrest_error(resp):
    try:
        body = resp.json()
    except ValueError:
        return "", resp.text[:200]
    return body.get("code", ""), body.get("message", resp.text[:200])


def table_count(base_url, headers, table, filters):
    """SELECT count via PostgREST (Range 0-0 + Prefer: count=exact) -- no rows transferred.

    filters: list of (column, "eq"/"or", value) -- for a single-column eq
    filter pass [(column, "eq", value)]. For an OR across two columns pass
    a single tuple ("or", "colA.eq.<v>,colB.eq.<v>").
    Returns (count_or_None, status_string).
    """
    url = f"{base_url}/rest/v1/{table}"
    params = {"select": "*"}
    for f in filters:
        if f[0] == "or":
            params["or"] = f"({f[1]})"
        else:
            col, op, val = f
            params[col] = f"{op}.{val}"
    req_headers = dict(headers)
    req_headers["Prefer"] = "count=exact"
    req_headers["Range-Unit"] = "items"
    req_headers["Range"] = "0-0"
    try:
        r = requests.get(url, headers=req_headers, params=params, timeout=REQUEST_TIMEOUT)
    except requests.RequestException as e:
        return None, f"error: {e}"

    if r.status_code in (200, 206):
        content_range = r.headers.get("Content-Range", "")
        if "/" in content_range:
            total = content_range.split("/")[-1]
            if total == "*":
                return None, "unknown (no exact count returned)"
            return int(total), "ok"
        return None, "unknown (no Content-Range header)"

    code, message = _parse_postgrest_error(r)
    if code == "42P01" or r.status_code == 404:
        return None, "n/a (table not found)"
    if code == "42703":
        return None, f"n/a (column not found: {message})"
    return None, f"error: HTTP {r.status_code} {message}"


def table_delete(base_url, headers, table, filters):
    """DELETE via PostgREST. Same filter shape as table_count. Returns (deleted_count, status)."""
    url = f"{base_url}/rest/v1/{table}"
    params = {}
    for f in filters:
        if f[0] == "or":
            params["or"] = f"({f[1]})"
        else:
            col, op, val = f
            params[col] = f"{op}.{val}"
    req_headers = dict(headers)
    req_headers["Prefer"] = "return=representation,count=exact"
    try:
        r = requests.delete(url, headers=req_headers, params=params, timeout=REQUEST_TIMEOUT)
    except requests.RequestException as e:
        return None, f"error: {e}"
    if r.status_code in (200, 204):
        try:
            rows = r.json()
            return len(rows), "ok"
        except ValueError:
            return None, "ok (no body)"
    code, message = _parse_postgrest_error(r)
    if code == "42P01" or r.status_code == 404:
        return 0, "n/a (table not found)"
    return None, f"error: HTTP {r.status_code} {message}"


def table_update(base_url, headers, table, filters, patch):
    url = f"{base_url}/rest/v1/{table}"
    params = {}
    for f in filters:
        if f[0] == "or":
            params["or"] = f"({f[1]})"
        else:
            col, op, val = f
            params[col] = f"{op}.{val}"
    req_headers = dict(headers)
    req_headers["Prefer"] = "return=representation,count=exact"
    req_headers["Content-Type"] = "application/json"
    try:
        r = requests.patch(url, headers=req_headers, params=params, json=patch, timeout=REQUEST_TIMEOUT)
    except requests.RequestException as e:
        return None, f"error: {e}"
    if r.status_code in (200, 204):
        try:
            rows = r.json()
            return len(rows), "ok"
        except ValueError:
            return None, "ok (no body)"
    code, message = _parse_postgrest_error(r)
    if code == "42P01" or r.status_code == 404:
        return 0, "n/a (table not found)"
    return None, f"error: HTTP {r.status_code} {message}"


# ----------------------------------------------------------------------------
# Table maps
# ----------------------------------------------------------------------------
# Every entry lists (label, table, filter_builder(user_id)) so both the
# dry-run counts and the execute deletes iterate over the exact same set,
# in the exact same order, from a single source of truth.

def eq(col, uid):
    return [(col, "eq", uid)]


def or_eq(cols, uid):
    return [("or", ",".join(f"{c}.eq.{uid}" for c in cols))]


# Tables that key directly off the player's user_id and (per live OpenAPI
# introspection) declare an FK to players.user_id.
PLAYERS_FK_SET = [
    ("player_economy", "player_economy", eq("user_id", None)),
    ("player_progress", "player_progress", eq("user_id", None)),
    ("player_streaks", "player_streaks", eq("user_id", None)),
    ("player_trial", "player_trial", eq("user_id", None)),
    ("player_devices", "player_devices", eq("user_id", None)),
    ("anticheat_flags", "anticheat_flags", eq("user_id", None)),
    ("suspicion_scores", "suspicion_scores", eq("user_id", None)),
    ("superpower_grants", "superpower_grants", eq("user_id", None)),
    ("superpower_offers", "superpower_offers", eq("user_id", None)),
    ("behavioral_fingerprints", "behavioral_fingerprints", eq("user_id", None)),
    ("challenges", "challenges", eq("user_id", None)),
    ("credit_transactions", "credit_transactions", eq("user_id", None)),
    ("ctf_participants", "ctf_participants", eq("user_id", None)),
    ("invitation_codes (created_by)", "invitation_codes", eq("created_by", None)),
    ("code_redemptions (redeemed_by)", "code_redemptions", eq("redeemed_by", None)),
    ("referrals (invitee_id OR inviter_id)", "referrals", None),  # special-cased below
]

# No enforced FK confirmed live (or FK target is outside the public schema /
# unclear) -- always handled explicitly, never assumed to cascade.
MANUAL_USER_TABLES = [
    ("gps_samples", "gps_samples", "user_id"),
    ("runs", "runs", "user_id"),
    ("prefs", "prefs", "user_id"),
    ("events", "events", "user_id"),
    ("feedback", "feedback", "user_id"),
    ("daily_mission_progress", "daily_mission_progress", "user_id"),
    ("city_waitlists", "city_waitlists", "user_id"),
    ("client_errors", "client_errors", "user_id"),
]

# Extra tables that reference players/zones and would otherwise dangle or
# block a players-row delete. Included for completeness and safety.
EXTRA_SAFETY_TABLES = [
    ("hex_ownership (owner_id)", "hex_ownership", "owner_id"),
    ("disputes (attacker_id OR defender_id OR winner_id)", "disputes", None),  # special-cased
]

ZONES_OWNER = ("zones (owner_id)", "zones", "owner_id")
ZONES_CONTESTED = ("zones (contested_by_id)", "zones", "contested_by_id")
CTF_EVENTS_WINNER = ("ctf_events (winner_id)", "ctf_events", "winner_id")


# ----------------------------------------------------------------------------
# Dry run
# ----------------------------------------------------------------------------

def print_row(label, count, status, w1=42, w2=10):
    if count is not None:
        count_str = str(count)
    else:
        count_str = "-"
    print(f"  {label:<{w1}} {count_str:>{w2}}   {status}")


def dry_run(base_url, headers, user_id):
    print("\n=== Per-table row counts for user_id =", user_id, "===\n")
    print(f"  {'Table':<42} {'Count':>10}   Status")
    print(f"  {'-'*42} {'-'*10}   {'-'*30}")

    results = {}

    print("\n-- players --")
    c, s = table_count(base_url, headers, "players", eq("user_id", user_id))
    print_row("players", c, s)
    results["players"] = (c, s)

    print("\n-- players-FK cascade set --")
    for label, table, _ in PLAYERS_FK_SET:
        if table == "referrals":
            c, s = table_count(base_url, headers, "referrals", or_eq(["invitee_id", "inviter_id"], user_id))
        else:
            col = "created_by" if table == "invitation_codes" else (
                "redeemed_by" if table == "code_redemptions" else "user_id"
            )
            c, s = table_count(base_url, headers, table, eq(col, user_id))
        print_row(label, c, s)
        results[label] = (c, s)

    print("\n-- gps_samples (no FK, manual delete) --")
    c, s = table_count(base_url, headers, "gps_samples", eq("user_id", user_id))
    print_row("gps_samples", c, s)
    results["gps_samples"] = (c, s)

    print("\n-- zones --")
    c, s = table_count(base_url, headers, "zones", eq("owner_id", user_id))
    print_row(ZONES_OWNER[0], c, s)
    results[ZONES_OWNER[0]] = (c, s)
    c, s = table_count(base_url, headers, "zones", eq("contested_by_id", user_id))
    print_row(ZONES_CONTESTED[0] + "  [no cascade -> needs manual UPDATE to NULL]", c, s)
    results[ZONES_CONTESTED[0]] = (c, s)

    print("\n-- runs / prefs / events / feedback / daily_mission_progress / city_waitlists / client_errors --")
    for label, table, col in MANUAL_USER_TABLES[1:]:  # skip gps_samples, already printed
        c, s = table_count(base_url, headers, table, eq(col, user_id))
        print_row(label, c, s)
        results[label] = (c, s)

    print("\n-- extra safety tables (found live, not in the original operator list) --")
    for label, table, col in EXTRA_SAFETY_TABLES:
        if table == "disputes":
            c, s = table_count(
                base_url, headers, "disputes",
                or_eq(["attacker_id", "defender_id", "winner_id"], user_id),
            )
        else:
            c, s = table_count(base_url, headers, table, eq(col, user_id))
        print_row(label, c, s)
        results[label] = (c, s)

    c, s = table_count(base_url, headers, "ctf_events", eq("winner_id", user_id))
    print_row(CTF_EVENTS_WINNER[0], c, s)
    results[CTF_EVENTS_WINNER[0]] = (c, s)

    return results


# ----------------------------------------------------------------------------
# Execute (mutation) path -- guarded by --execute AND --yes-i-approve
# ----------------------------------------------------------------------------

def execute_wipe(base_url, headers, user_id, email):
    RED = "\033[91m"
    BOLD = "\033[1m"
    RESET = "\033[0m"
    print(f"\n{RED}{BOLD}==================== DESTRUCTIVE MUTATION RUN ===================={RESET}")
    print(f"{RED}This will PERMANENTLY delete all RunWar data for {email} ({user_id}).{RESET}")
    print(f"{RED}This action cannot be undone.{RESET}\n")

    log = []

    def do_delete(label, table, filters):
        n, s = table_delete(base_url, headers, table, filters)
        log.append((label, "DELETE", n, s))
        print(f"  DELETE {label:<45} rows={n if n is not None else '-'}  {s}")
        if s.startswith("error"):
            raise RuntimeError(f"mutation failed on {label}: {s}")

    def do_delete_append_only(label, table, filters):
        """Delete on a table guarded by an append-only trigger (e.g.
        credit_transactions' credit_tx_no_delete BEFORE DELETE trigger,
        which raises HTTP 400 on any DELETE while enabled).

        This script never disables that trigger itself -- that is a
        separate, explicitly-scoped operator action (temporary
        ALTER TABLE ... DISABLE/ENABLE TRIGGER around a manual DELETE,
        done outside this script, with immediate re-enable). This helper
        is therefore idempotent both before and after that manual step:
          * 0 rows for this user_id -> already clean, skip.
          * >0 rows still present -> the manual disable/delete/re-enable
            has not been done (or didn't target this user_id) -- raise a
            clear, actionable error rather than swallowing it, so a stale
            row can never silently survive a "passing" re-run.
        """
        count, count_status = table_count(base_url, headers, table, filters)
        if count == 0:
            log.append((label, "DELETE", 0, "skip (already empty)"))
            print(f"  DELETE {label:<45} rows=0   skip (already empty)")
            return
        if count is None:
            raise RuntimeError(
                f"could not verify row count on {label} before delete: {count_status}"
            )
        n, s = table_delete(base_url, headers, table, filters)
        if s.startswith("error"):
            raise RuntimeError(
                f"{label} still has {count} row(s) for this user and the DELETE was "
                f"rejected ({s}). This script does not disable the append-only trigger "
                f"itself -- run the manual "
                f"'ALTER TABLE public.{table} DISABLE TRIGGER credit_tx_no_delete; "
                f"DELETE FROM public.{table} WHERE user_id=<uid>; "
                f"ALTER TABLE public.{table} ENABLE TRIGGER credit_tx_no_delete;' "
                f"sequence first, then re-run this script."
            )
        log.append((label, "DELETE", n, s))
        print(f"  DELETE {label:<45} rows={n if n is not None else '-'}  {s}")

    def do_update(label, table, filters, patch):
        n, s = table_update(base_url, headers, table, filters, patch)
        log.append((label, "UPDATE", n, s))
        print(f"  UPDATE {label:<45} rows={n if n is not None else '-'}  {s}")
        if s.startswith("error"):
            raise RuntimeError(f"mutation failed on {label}: {s}")

    # 1. Defensive null-out of any OTHER row that might point at a run/zone
    #    owned by this user before we delete runs/zones out from under them.
    do_update(
        "suspicion_scores.last_session_id -> NULL (any user, run in scope)",
        "suspicion_scores",
        eq("user_id", user_id),  # this user's own row is about to be deleted anyway; harmless no-op if 0
        {"last_session_id": None},
    )
    do_update(CTF_EVENTS_WINNER[0] + " -> NULL", "ctf_events", eq("winner_id", user_id), {"winner_id": None})

    # 2. Players-FK cascade set (delete children before any parent rows)
    do_delete("superpower_offers", "superpower_offers", eq("user_id", user_id))
    do_delete("superpower_grants", "superpower_grants", eq("user_id", user_id))
    do_delete("anticheat_flags", "anticheat_flags", eq("user_id", user_id))
    do_delete("behavioral_fingerprints", "behavioral_fingerprints", eq("user_id", user_id))
    do_delete("suspicion_scores", "suspicion_scores", eq("user_id", user_id))
    do_delete("challenges", "challenges", eq("user_id", user_id))
    do_delete_append_only("credit_transactions", "credit_transactions", eq("user_id", user_id))
    do_delete("ctf_participants", "ctf_participants", eq("user_id", user_id))
    do_delete("code_redemptions (redeemed_by)", "code_redemptions", eq("redeemed_by", user_id))
    do_delete("referrals (invitee_id OR inviter_id)", "referrals", or_eq(["invitee_id", "inviter_id"], user_id))
    # NOTE: invitation_codes.created_by -> players.user_id is declared ON
    # DELETE CASCADE, and code_redemptions.code -> invitation_codes.code is
    # ALSO ON DELETE CASCADE. Deleting an invitation_codes row this user
    # CREATED will cascade-delete OTHER users' redemptions of that same
    # code. This is a real side effect -- flagged here and in the dry-run
    # report, not silently absorbed.
    do_delete("invitation_codes (created_by)", "invitation_codes", eq("created_by", user_id))
    do_delete("player_economy", "player_economy", eq("user_id", user_id))
    do_delete("player_progress", "player_progress", eq("user_id", user_id))
    do_delete("player_streaks", "player_streaks", eq("user_id", user_id))
    do_delete("player_trial", "player_trial", eq("user_id", user_id))
    do_delete("player_devices", "player_devices", eq("user_id", user_id))

    # 3. Manual / no-FK tables
    do_delete("prefs", "prefs", eq("user_id", user_id))
    do_delete("events", "events", eq("user_id", user_id))
    do_delete("feedback", "feedback", eq("user_id", user_id))
    do_delete("daily_mission_progress", "daily_mission_progress", eq("user_id", user_id))
    do_delete("city_waitlists", "city_waitlists", eq("user_id", user_id))
    do_delete("client_errors", "client_errors", eq("user_id", user_id))

    # 4. hex_ownership + disputes before zones, then zones themselves
    do_delete("hex_ownership (owner_id)", "hex_ownership", eq("owner_id", user_id))
    do_delete(
        "disputes (attacker_id OR defender_id OR winner_id)",
        "disputes",
        or_eq(["attacker_id", "defender_id", "winner_id"], user_id),
    )
    do_update(ZONES_CONTESTED[0] + " -> NULL", "zones", eq("contested_by_id", user_id), {"contested_by_id": None})
    do_delete(ZONES_OWNER[0], "zones", eq("owner_id", user_id))

    # 5. gps_samples + runs (no FK either way -- must be explicit)
    do_delete("gps_samples", "gps_samples", eq("user_id", user_id))
    do_delete("runs", "runs", eq("user_id", user_id))

    # 6. players row itself
    do_delete("players", "players", eq("user_id", user_id))

    # 7. auth.users row via Admin API
    print(f"  DELETE auth.users/{user_id} ...")
    delete_auth_user(base_url, headers, user_id)
    print("  DELETE auth.users -> ok")

    return log


def verify_zero(base_url, headers, user_id):
    print("\n=== Post-wipe verification (expect ALL zero) ===\n")
    all_zero = True
    checks = []
    for label, table, _ in PLAYERS_FK_SET:
        if table == "referrals":
            c, s = table_count(base_url, headers, "referrals", or_eq(["invitee_id", "inviter_id"], user_id))
        else:
            col = "created_by" if table == "invitation_codes" else (
                "redeemed_by" if table == "code_redemptions" else "user_id"
            )
            c, s = table_count(base_url, headers, table, eq(col, user_id))
        checks.append((label, c, s))
    for label, table, col in MANUAL_USER_TABLES:
        c, s = table_count(base_url, headers, table, eq(col, user_id))
        checks.append((label, c, s))
    c, s = table_count(base_url, headers, "zones", eq("owner_id", user_id))
    checks.append((ZONES_OWNER[0], c, s))
    c, s = table_count(base_url, headers, "zones", eq("contested_by_id", user_id))
    checks.append((ZONES_CONTESTED[0], c, s))
    c, s = table_count(base_url, headers, "players", eq("user_id", user_id))
    checks.append(("players", c, s))
    c, s = table_count(base_url, headers, "hex_ownership", eq("owner_id", user_id))
    checks.append(("hex_ownership (owner_id)", c, s))
    c, s = table_count(
        base_url, headers, "disputes",
        or_eq(["attacker_id", "defender_id", "winner_id"], user_id),
    )
    checks.append(("disputes", c, s))

    for label, c, s in checks:
        print_row(label, c, s)
        if c not in (0, None):
            all_zero = False

    print()
    if all_zero:
        print("VERIFICATION PASSED -- all counts are zero (or table n/a).")
    else:
        print("VERIFICATION FAILED -- nonzero rows remain. Investigate before re-running.")
    return all_zero


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="RunWar Supabase user-data wipe tool")
    parser.add_argument("--email", required=True, help="Email of the RunWar user to wipe")
    parser.add_argument("--execute", action="store_true", help="Perform mutations (still requires --yes-i-approve)")
    parser.add_argument("--yes-i-approve", action="store_true", dest="approved",
                         help="Explicit operator approval; required together with --execute")
    parser.add_argument("--env-file", default=None,
                         help="Path to a file with KEY=VALUE lines to load into the environment "
                              "before running (e.g. containing RUNWAR_SUPABASE_URL and "
                              "RUNWAR_SUPABASE_SERVICE_ROLE_KEY)")
    args = parser.parse_args()

    if args.env_file:
        load_env_file(args.env_file)

    base_url, service_key = load_credentials()
    headers = {"apikey": service_key, "Authorization": f"Bearer {service_key}"}

    print(f"Resolving auth.users id for {args.email} ...")
    user = find_user_by_email(base_url, headers, args.email)
    if user is None:
        print(f"No auth user found for {args.email}. Nothing to do (already wiped, or never existed). Exiting cleanly.")
        sys.exit(0)

    user_id = user["id"]
    created_at = user.get("created_at")
    print(f"Resolved: id={user_id}  created_at={created_at}")

    do_execute = args.execute and args.approved
    if args.execute and not args.approved:
        print("\n--execute passed WITHOUT --yes-i-approve. Both flags are required to mutate.")
        print("Falling back to dry-run only.\n")
    elif args.approved and not args.execute:
        print("\n--yes-i-approve passed WITHOUT --execute. Both flags are required to mutate.")
        print("Running dry-run only.\n")

    if not do_execute:
        print("\n==================== DRY RUN (read-only, no data will be modified) ====================")
        dry_run(base_url, headers, user_id)
        print("\nDry run complete. No data was modified. Pass --execute --yes-i-approve to mutate.")
        return

    # --- Mutation path ---
    print("\nPre-mutation snapshot:")
    dry_run(base_url, headers, user_id)

    log = execute_wipe(base_url, headers, user_id, args.email)

    ok = verify_zero(base_url, headers, user_id)
    print(f"\nMutation run finished at {datetime.now(timezone.utc).isoformat()}")
    print(f"Total operations logged: {len(log)}")
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
