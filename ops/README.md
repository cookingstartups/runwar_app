# ops/

Operational scripts for RunWar. These are not part of the Flutter app; they
are run manually by an operator against the Supabase project.

## wipe_user.py

Completely wipes all RunWar data for a single user, given only their email
(auth.users row, players row, runs, gps_samples, zones, credits, and every
other table that references the user).

Requires the `requests` package (`pip install requests`).

### Credentials

Reads two environment variables:

- `RUNWAR_SUPABASE_URL`
- `RUNWAR_SUPABASE_SERVICE_ROLE_KEY`

Either export them in your shell first, or pass `--env-file <path>` to a
file with `KEY=VALUE` lines to load them from (the path is never hardcoded
in the script).

### Usage

Always dry-run first. Dry-run is the default and only reads data (row
counts per table, no mutation):

```bash
python3 ops/wipe_user.py --email user@example.com --env-file /path/to/credentials.env
```

Review the counts, then run the destructive wipe. Both `--execute` and
`--yes-i-approve` are required together; either flag alone falls back to a
dry run:

```bash
python3 ops/wipe_user.py --email user@example.com --env-file /path/to/credentials.env --execute --yes-i-approve
```

After a mutation run the script re-counts every table and prints
PASS/FAIL. The script is idempotent: running it again against an
already-wiped user reports "No auth user found" and exits cleanly.

### credit_transactions trigger

`credit_transactions` has an append-only trigger (`credit_tx_no_delete`)
that blocks any DELETE while it is enabled. This script never disables
it. If the user has credit_transactions rows, the run stops with an
actionable error describing the manual
`ALTER TABLE ... DISABLE/ENABLE TRIGGER` sequence to run first, then
re-run this script. Users with zero credit_transactions rows are
unaffected and the step is skipped silently.

## verify_deploy.ts

Per-deploy DB end-state verification. A migration or edge-function deploy
succeeding only proves the deploy step ran - it proves nothing about
whether the database's observable end state actually looks the way the
feature intends. Run this after any deploy that touches zones, runs,
gps_samples, or anticheat_flags.

Six read-only checks: a subject's zones have a non-null geometry and the
right owner, no same-owner zones are left adjacent-but-unmerged, the
subject's runs are all finalized, every finalized run has gps_samples rows,
and no unresolved anticheat flag exists for the subject.

### Catalog mode (default, credential-free)

The no-flags invocation prints every check's id, target table, columns, and
documented SELECT, reads no credential, and makes no network call:

```bash
deno run --allow-read ops/verify_deploy.ts
```

### Execute mode

Requires both `--execute` and `--env-file <path>` together; `--execute`
alone silently falls back to catalog mode rather than attempting anything.
Credentials (`RUNWAR_SUPABASE_URL`, `RUNWAR_SUPABASE_SERVICE_ROLE_KEY`) are
loaded from the given env file, never hardcoded, never printed:

```bash
deno run --allow-read --allow-net --allow-env ops/verify_deploy.ts \
  --execute --env-file /path/to/credentials.env --subject <player-id>
```

Prints a PASS/FAIL line per check and exits non-zero if any check failed.
Every check is a plain HTTP GET against the PostgREST REST endpoints - there
is no write path anywhere in this tool, and every documented SELECT is
re-validated as read-only before use.
