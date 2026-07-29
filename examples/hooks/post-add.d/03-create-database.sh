#!/bin/bash
# Create MySQL database for the worktree
#
# Respects configuration hierarchy:
#   1. Global config (~/.groverc)
#   2. Project config ($HERD_ROOT/.groveconfig)
#   3. Repo-specific config ($HERD_ROOT/$GROVE_REPO.git/.groveconfig)
#
# Set DB_CREATE=false in any config to disable database creation.
# Repo configs can override global settings (e.g., enable for specific repos).
#
# Skip for a single invocation by setting: GROVE_SKIP_DB=true

# Manual skip via environment
if [[ "${GROVE_SKIP_DB:-}" == "true" ]]; then
  echo "  Skipping database creation (GROVE_SKIP_DB=true)"
  exit 0
fi

# Load configuration (global -> project -> repo-specific)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../_lib/load-config.sh"
else
  echo "  Config loader not found - cannot safely create database"
  exit 1
fi

# Check if database creation is enabled
if [[ "$DB_CREATE" != "true" ]]; then
  echo "  Skipping database creation (DB_CREATE=$DB_CREATE)"
  exit 0
fi

grove_validate_database_name "${GROVE_DB_NAME:-}" || exit 1

# Check for MySQL client
if ! command -v mysql >/dev/null 2>&1; then
  echo "  MySQL client not found - skipping database creation"
  echo "  Run manually: CREATE DATABASE \`${GROVE_DB_NAME}\`;"
  exit 0
fi

# Build mysql command
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER" -N -B)

# Check if database already exists
if ! database_exists=$(MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" \
    -e "SELECT 1 FROM information_schema.SCHEMATA WHERE schema_name='${GROVE_DB_NAME}';" 2>/dev/null); then
  echo "  Could not check database - check MySQL connection"
  exit 1
fi
if [[ "$database_exists" == "1" ]]; then
  echo "  Database already exists: ${GROVE_DB_NAME}"
  exit 0
fi

# Create database
if MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" \
    -e "CREATE DATABASE IF NOT EXISTS \`${GROVE_DB_NAME}\`;" 2>/dev/null; then
  echo "  Created database: ${GROVE_DB_NAME}"
  exit 0
else
  echo "  Could not create database - check MySQL connection"
  echo "  Run manually: CREATE DATABASE \`${GROVE_DB_NAME}\`;"
  exit 1
fi
