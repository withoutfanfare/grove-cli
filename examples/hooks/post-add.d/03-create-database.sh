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
  echo "  Warning: Config loader not found, using defaults"
  DB_CREATE="${DB_CREATE:-true}"
  DB_HOST="${DB_HOST:-127.0.0.1}"
  DB_USER="${DB_USER:-root}"
  DB_PASSWORD="${DB_PASSWORD:-}"
fi

# Check if database creation is enabled
if [[ "$DB_CREATE" != "true" ]]; then
  echo "  Skipping database creation (DB_CREATE=$DB_CREATE)"
  exit 0
fi

# Check for MySQL client
if ! command -v mysql >/dev/null 2>&1; then
  echo "  MySQL client not found - skipping database creation"
  echo "  Run manually: CREATE DATABASE \`${GROVE_DB_NAME}\`;"
  exit 0
fi

# Build mysql command
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")
[[ -n "$DB_PASSWORD" ]] && mysql_cmd+=(-p"$DB_PASSWORD")

# Check if database already exists
if "${mysql_cmd[@]}" -e "USE \`${GROVE_DB_NAME}\`;" 2>/dev/null; then
  echo "  Database already exists: ${GROVE_DB_NAME}"
  exit 0
fi

# Create database
if "${mysql_cmd[@]}" -e "CREATE DATABASE IF NOT EXISTS \`${GROVE_DB_NAME}\`;" 2>/dev/null; then
  echo "  Created database: ${GROVE_DB_NAME}"
  exit 0
else
  echo "  Could not create database - check MySQL connection"
  echo "  Run manually: CREATE DATABASE \`${GROVE_DB_NAME}\`;"
  exit 1
fi
