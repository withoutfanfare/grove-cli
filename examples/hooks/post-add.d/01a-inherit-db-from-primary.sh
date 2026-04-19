#!/bin/bash
# When DB_CREATE=false, inherit DB_DATABASE from the primary worktree's .env.
#
# Rationale: with DB_CREATE=false, grove does not create a per-worktree DB,
# so the new worktree must share the primary's DB. But .env is copied from
# .env.example (via 01-copy-env.sh), which often contains stale or placeholder
# values (e.g. an install-default DB name). Those defaults cause session and
# migration errors on first page load.
#
# This hook reads DB_DATABASE from ${HERD_ROOT}/${GROVE_REPO}-worktrees/${GROVE_REPO}/.env
# (the canonical primary worktree) and writes it into the new worktree's .env.
# No-op when DB_CREATE=true (the next hook sets DB_DATABASE to a per-worktree name).

if [[ ! -f "${GROVE_PATH}/.env" ]]; then
  exit 0
fi

# Load configuration hierarchy so DB_CREATE reflects user's actual setting.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../_lib/load-config.sh"
else
  DB_CREATE="${DB_CREATE:-true}"
  HERD_ROOT="${HERD_ROOT:-$HOME/Herd}"
fi

if [[ "$DB_CREATE" == "true" ]]; then
  exit 0
fi

primary_env="${HERD_ROOT}/${GROVE_REPO}-worktrees/${GROVE_REPO}/.env"

# Skip self-reference (when this IS the primary worktree being created).
if [[ "$primary_env" == "${GROVE_PATH}/.env" ]]; then
  exit 0
fi

if [[ ! -f "$primary_env" ]]; then
  exit 0
fi

primary_db=$(grep -E '^DB_DATABASE=' "$primary_env" | head -1 | cut -d= -f2-)

if [[ -z "$primary_db" ]]; then
  exit 0
fi

if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s|^DB_DATABASE=.*|DB_DATABASE=${primary_db}|" "${GROVE_PATH}/.env"
else
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${primary_db}|" "${GROVE_PATH}/.env"
fi
echo "  Inherited DB_DATABASE=${primary_db} from primary worktree"

exit 0
