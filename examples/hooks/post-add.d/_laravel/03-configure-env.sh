#!/bin/bash
# Configure .env with worktree-specific values
#
# This runs AFTER 02-copy-env.sh, so it configures the worktree's own .env copy.
#
# Sets:
#   - APP_URL (always)
#   - VITE_APP_URL (if present, to match APP_URL)
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

# Extract protocol from GROVE_URL (https or http)
if [[ "$GROVE_URL" == https://* ]]; then
  URL_PROTOCOL="https"
else
  URL_PROTOCOL="http"
fi

# Extract domain from GROVE_URL (e.g., https://pruning001.test -> pruning001.test)
SESSION_DOMAIN="${GROVE_URL#https://}"
SESSION_DOMAIN="${SESSION_DOMAIN#http://}"

# Helper function for sed (handles macOS vs Linux)
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Set APP_URL
if grep -q "^APP_URL=" .env 2>/dev/null; then
  sed_inplace "s|^APP_URL=.*|APP_URL=${GROVE_URL}|" .env
  echo "  Set APP_URL=${GROVE_URL}"
fi

# Set VITE_APP_URL to match APP_URL (for Vite dev server)
if grep -q "^VITE_APP_URL=" .env 2>/dev/null; then
  sed_inplace "s|^VITE_APP_URL=.*|VITE_APP_URL=${GROVE_URL}|" .env
  echo "  Set VITE_APP_URL=${GROVE_URL}"
fi

# Set SESSION_DOMAIN to match worktree URL (prevents CSRF token issues)
if grep -q "^SESSION_DOMAIN=" .env 2>/dev/null; then
  sed_inplace "s|^SESSION_DOMAIN=.*|SESSION_DOMAIN=${SESSION_DOMAIN}|" .env
  echo "  Set SESSION_DOMAIN=${SESSION_DOMAIN}"
fi

# Set DB_DATABASE only if database management is enabled
if [[ "$DB_CREATE" == "true" ]]; then
  if grep -q "^DB_DATABASE=" .env 2>/dev/null; then
    sed_inplace "s|^DB_DATABASE=.*|DB_DATABASE=${GROVE_DB_NAME}|" .env
    echo "  Set DB_DATABASE=${GROVE_DB_NAME}"
  fi
fi

exit 0
