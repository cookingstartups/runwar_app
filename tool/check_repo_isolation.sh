#!/usr/bin/env bash
# tool/check_repo_isolation.sh
# Phase 1: forbid direct supabase_flutter imports outside services layer.
set -e
if grep -RlE "package:supabase_flutter/" lib/screens lib/widgets lib/providers 2>/dev/null; then
  echo "ERROR: supabase_flutter imported outside services layer (Phase 1 rule)." >&2
  exit 1
fi
echo "OK: no supabase_flutter imports in screens/widgets/providers."
