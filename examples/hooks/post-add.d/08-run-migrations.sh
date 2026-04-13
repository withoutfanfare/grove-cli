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

cd "$GROVE_PATH" || exit 0

echo "  Running migrations..."
if php artisan migrate --force --no-interaction --quiet 2>&1; then
  echo "  Migrations complete"
  exit 0
else
  echo "  Migrations failed - run manually: php artisan migrate"
  exit 1
fi
