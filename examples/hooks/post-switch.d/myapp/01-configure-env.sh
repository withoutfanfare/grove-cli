#!/bin/bash
# Configure .env with worktree-specific values on switch
#
# Each worktree has its own .env copy, so this hook ensures the
# values are correct for the switched-to worktree. This is useful
# if the template .env was updated or values were manually changed.
#
# Sets:
#   - APP_URL (always)
#   - SESSION_DOMAIN (always, to match worktree URL for proper CSRF)
#   - DB_DATABASE (only if DB_CREATE=true)
#
# Respects configuration hierarchy for DB_CREATE setting.

if [[ ! -f "${GROVE_PATH}/.env" ]]; then
  exit 0
fi

# Load configuration (global -> project -> repo-specific)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../../_lib/load-config.sh"
else
  DB_CREATE="${DB_CREATE:-true}"
fi

cd "$GROVE_PATH" || exit 0

# Extract domain from GROVE_URL (e.g., https://pruning001.test -> pruning001.test)
SESSION_DOMAIN="${GROVE_URL#https://}"
SESSION_DOMAIN="${SESSION_DOMAIN#http://}"

# Set APP_URL
if grep -q "^APP_URL=" .env 2>/dev/null; then
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "s|^APP_URL=.*|APP_URL=${GROVE_URL}|" .env
  else
    sed -i "s|^APP_URL=.*|APP_URL=${GROVE_URL}|" .env
  fi
  echo "  Set APP_URL=${GROVE_URL}"
fi

# Set SESSION_DOMAIN to match worktree URL (prevents CSRF token issues)
if grep -q "^SESSION_DOMAIN=" .env 2>/dev/null; then
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "s|^SESSION_DOMAIN=.*|SESSION_DOMAIN=${SESSION_DOMAIN}|" .env
  else
    sed -i "s|^SESSION_DOMAIN=.*|SESSION_DOMAIN=${SESSION_DOMAIN}|" .env
  fi
  echo "  Set SESSION_DOMAIN=${SESSION_DOMAIN}"
fi

# Set DB_DATABASE only if database management is enabled
if [[ "$DB_CREATE" == "true" ]]; then
  if grep -q "^DB_DATABASE=" .env 2>/dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^DB_DATABASE=.*|DB_DATABASE=${GROVE_DB_NAME}|" .env
    else
      sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${GROVE_DB_NAME}|" .env
    fi
    echo "  Set DB_DATABASE=${GROVE_DB_NAME}"
  fi
fi

exit 0
