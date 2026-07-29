#!/bin/bash
# Run Laravel database migrations
#
# Only runs for Laravel projects (artisan file exists).
# Skip by setting: GROVE_SKIP_MIGRATE=true

if [[ "${GROVE_SKIP_MIGRATE:-}" == "true" ]]; then
  echo "  Skipping migrations (GROVE_SKIP_MIGRATE=true)"
  exit 0
fi

if [[ ! -f "${GROVE_PATH}/artisan" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/../_lib/php-runtime.sh" ]]; then
  echo "  PHP runtime helper not found - cannot run migrations safely"
  exit 1
fi
source "$SCRIPT_DIR/../_lib/php-runtime.sh"
PHP_BIN="$(grove_php_bin)" || { echo "  PHP not found - cannot run migrations"; exit 1; }

cd "$GROVE_PATH" || exit 0

echo "  Running migrations..."
if "$PHP_BIN" artisan migrate --force --no-interaction --quiet 2>&1; then
  echo "  Migrations complete"
  exit 0
else
  echo "  Migrations failed - run manually: $PHP_BIN artisan migrate"
  exit 1
fi
