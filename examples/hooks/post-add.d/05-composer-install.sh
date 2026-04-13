#!/bin/bash
# Run composer install for PHP/Laravel projects
#
# Only runs if composer.json exists.
# Skip by setting: GROVE_SKIP_COMPOSER=true

if [[ "${GROVE_SKIP_COMPOSER:-}" == "true" ]]; then
  echo "  Skipping composer install (GROVE_SKIP_COMPOSER=true)"
  exit 0
fi

if [[ ! -f "${GROVE_PATH}/composer.json" ]]; then
  exit 0
fi

if ! command -v composer >/dev/null 2>&1; then
  echo "  Composer not found - run manually: composer install"
  exit 0
fi

cd "$GROVE_PATH" || exit 0

echo "  Running composer install..."
if composer install --no-interaction --quiet --ignore-platform-req=ext-imagick 2>&1; then
  echo "  Composer install complete"
else
  echo "  Composer install failed - run manually: composer install"
  exit 1
fi

# Generate app key for Laravel
if [[ -f "artisan" ]]; then
  if php artisan key:generate --force >/dev/null 2>&1; then
    echo "  Generated Laravel app key"
  fi
fi

exit 0
