#!/bin/bash
# Drop database after worktree removal
#
# Respects configuration hierarchy:
#   1. Global config (~/.groverc)
#   2. Project config ($HERD_ROOT/.groveconfig)
#   3. Repo-specific config ($HERD_ROOT/$GROVE_REPO.git/.groveconfig)
#
# Logic:
#   - If DB_CREATE=false: Skip entirely (databases aren't managed by grove)
#   - If DB_CREATE=true and GROVE_DROP_DB=true: Drop the database
#   - If DB_CREATE=true and GROVE_DROP_DB unset/false: Keep the database (default)
#
# The --drop-db flag sets GROVE_DROP_DB=true

# Load configuration (global -> project -> repo-specific)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../_lib/load-config.sh"
else
  echo "  Warning: Config loader not found, using defaults"
  DB_CREATE="${DB_CREATE:-true}"
  DB_HOST="${DB_HOST:-127.0.0.1}"
  DB_USER="${DB_USER:-root}"
  DB_PASSWORD="${DB_PASSWORD:-}"
fi

# If DB_CREATE is disabled, we don't manage databases at all
if [[ "$DB_CREATE" != "true" ]]; then
  # Silently skip - databases aren't managed by grove for this repo
  exit 0
fi

# DB_CREATE is enabled, so we manage databases
# Only drop if explicitly requested via --drop-db flag
if [[ "${GROVE_DROP_DB:-}" != "true" ]]; then
  # Keeping database is the default behaviour
  exit 0
fi

# Check for MySQL client
if ! command -v mysql >/dev/null 2>&1; then
  echo "  MySQL client not found - cannot drop database"
  exit 0
fi

# Build mysql command
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")
[[ -n "$DB_PASSWORD" ]] && mysql_cmd+=(-p"$DB_PASSWORD")

# Check if database exists
if ! "${mysql_cmd[@]}" -e "USE \`${GROVE_DB_NAME}\`;" 2>/dev/null; then
  echo "  Database ${GROVE_DB_NAME} does not exist"
  exit 0
fi

echo "  Dropping database ${GROVE_DB_NAME}..."
if "${mysql_cmd[@]}" -e "DROP DATABASE \`${GROVE_DB_NAME}\`;" 2>/dev/null; then
  echo "  Database dropped: ${GROVE_DB_NAME}"
  exit 0
else
  echo "  Could not drop database"
  exit 1
fi
