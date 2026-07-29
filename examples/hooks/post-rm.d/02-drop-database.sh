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
  echo "  Config loader not found - cannot safely drop database"
  exit 1
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

grove_validate_database_name "${GROVE_DB_NAME:-}" || exit 1

# Check for MySQL client
if ! command -v mysql >/dev/null 2>&1; then
  echo "  MySQL client not found - cannot drop database"
  exit 1
fi

# Build mysql command
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER" -N -B)

if ! MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "  Cannot reach MySQL - database was not dropped"
  exit 1
fi

# Check if database exists
if ! database_exists=$(MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" \
    -e "SELECT 1 FROM information_schema.SCHEMATA WHERE schema_name='${GROVE_DB_NAME}';" 2>/dev/null); then
  echo "  Could not check database - database was not dropped"
  exit 1
fi
if [[ "$database_exists" != "1" ]]; then
  echo "  Database ${GROVE_DB_NAME} does not exist"
  exit 0
fi

echo "  Dropping database ${GROVE_DB_NAME}..."
if MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" \
    -e "DROP DATABASE \`${GROVE_DB_NAME}\`;" 2>/dev/null; then
  echo "  Database dropped: ${GROVE_DB_NAME}"
  exit 0
else
  echo "  Could not drop database"
  exit 1
fi
