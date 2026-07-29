#!/bin/bash
# Import database from pre-configured SQL dump for this repo
#
# Expected path: ~/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-db/${GROVE_REPO}.sql.gz
#
# This runs AFTER the database is created (global 03-create-database.sh).
# Respects DB_CREATE setting - if database management is disabled, skip import.

set -o pipefail

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
  echo "  Config loader not found - cannot safely import database"
  exit 1
fi

# If database creation is disabled, skip import
if [[ "$DB_CREATE" != "true" || "${GROVE_SKIP_DB:-}" == "true" ]]; then
  echo "  Skipping database import (DB_CREATE=$DB_CREATE)"
  exit 0
fi

grove_validate_database_name "${GROVE_DB_NAME:-}" || exit 1

if ! command -v mysql >/dev/null 2>&1; then
  echo "  MySQL client not found - cannot import database"
  exit 0
fi

# A retained database may contain work that is not in the seed dump. Import
# only into an empty database unless the caller explicitly opts in.
if [[ "${GROVE_FORCE_DB_IMPORT:-}" != "true" ]]; then
  if ! table_count=$(MYSQL_PWD="${DB_PASSWORD:-}" mysql -h "$DB_HOST" -u "$DB_USER" -N -B \
      -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='${GROVE_DB_NAME}';" 2>/dev/null); then
    echo "  Could not inspect database - refusing seed import"
    exit 1
  fi
  if [[ ! "$table_count" =~ ^[0-9]+$ ]]; then
    echo "  Unexpected database inspection result - refusing seed import"
    exit 1
  fi
  if (( table_count > 0 )); then
    echo "  Database already contains tables - skipping seed import"
    exit 0
  fi
fi

# Build mysql command
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")

echo "  Importing ${GROVE_REPO} database from $DB_DUMP..."

# Decompress and import
if gunzip -c "$DB_DUMP" | MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" "$GROVE_DB_NAME" 2>/dev/null; then
  echo "  Database imported successfully"
  exit 0
else
  echo "  Database import failed"
  echo "  Try manually: gunzip -c $DB_DUMP | mysql $GROVE_DB_NAME"
  exit 1
fi
