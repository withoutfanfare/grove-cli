#!/bin/bash
# Import database from pre-configured SQL dump for this repo
#
# Expected path: ~/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-db/${GROVE_REPO}.sql.gz
#
# This runs AFTER the database is created (global 03-create-database.sh).
# Respects DB_CREATE setting - if database management is disabled, skip import.

DB_DUMP="$HOME/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-db/${GROVE_REPO}.sql.gz"

if [[ ! -f "$DB_DUMP" ]]; then
  echo "  No database dump at $DB_DUMP - skipping import"
  exit 0
fi

# Load configuration (global -> project -> repo-specific)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../../_lib/load-config.sh"
else
  # Fallback: load from ~/.groverc directly
  if [[ -f "$HOME/.groverc" ]]; then
    DB_HOST="${DB_HOST:-$(grep '^DB_HOST=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_USER="${DB_USER:-$(grep '^DB_USER=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_PASSWORD="${DB_PASSWORD:-$(grep '^DB_PASSWORD=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_CREATE="${DB_CREATE:-$(grep '^DB_CREATE=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
  fi
  DB_HOST="${DB_HOST:-127.0.0.1}"
  DB_USER="${DB_USER:-root}"
  DB_PASSWORD="${DB_PASSWORD:-}"
  DB_CREATE="${DB_CREATE:-true}"
fi

# If database creation is disabled, skip import
if [[ "$DB_CREATE" != "true" ]]; then
  echo "  Skipping database import (DB_CREATE=$DB_CREATE)"
  exit 0
fi

if ! command -v mysql >/dev/null 2>&1; then
  echo "  MySQL client not found - cannot import database"
  exit 0
fi

# Build mysql command
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")
[[ -n "$DB_PASSWORD" ]] && mysql_cmd+=(-p"$DB_PASSWORD")

echo "  Importing ${GROVE_REPO} database from $DB_DUMP..."

# Decompress and import
if gunzip -c "$DB_DUMP" | "${mysql_cmd[@]}" "$GROVE_DB_NAME" 2>/dev/null; then
  echo "  Database imported successfully"
  exit 0
else
  echo "  Database import failed"
  echo "  Try manually: gunzip -c $DB_DUMP | mysql $GROVE_DB_NAME"
  exit 1
fi
