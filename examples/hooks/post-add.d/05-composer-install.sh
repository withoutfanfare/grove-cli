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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/../_lib/php-runtime.sh" ]]; then
  echo "  PHP runtime helper not found - cannot run composer safely"
  exit 1
fi
source "$SCRIPT_DIR/../_lib/php-runtime.sh"
PHP_BIN="$(grove_php_bin)" || { echo "  PHP not found - cannot run composer"; exit 1; }
COMPOSER_BIN="$(command -v composer)"

cd "$GROVE_PATH" || exit 0

echo "  Running composer install..."
if "$PHP_BIN" "$COMPOSER_BIN" install --no-interaction --quiet --ignore-platform-req=ext-imagick 2>&1; then
  echo "  Composer install complete"
else
  echo "  Composer install failed - run manually: $PHP_BIN $COMPOSER_BIN install"
  exit 1
fi

# Generate an app key only when it is missing or empty. Replacing an existing
# key would make already-encrypted local data unreadable.
APP_KEY_VALUE=""
if [[ -f ".env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == APP_KEY=* ]] || continue
    APP_KEY_VALUE="${line#APP_KEY=}"
    break
  done < .env
fi
# A closing quote ends the value before any trailing comment; unquoted values
# lose a " # comment" suffix — same rules as the _lib/load-config.sh parser.
APP_KEY_VALUE="${APP_KEY_VALUE#"${APP_KEY_VALUE%%[![:space:]]*}"}"
case "$APP_KEY_VALUE" in
  \#*)
    APP_KEY_VALUE=""
    ;;
  \"*)
    APP_KEY_VALUE="${APP_KEY_VALUE#\"}"
    APP_KEY_VALUE="${APP_KEY_VALUE%%\"*}"
    ;;
  \'*)
    APP_KEY_VALUE="${APP_KEY_VALUE#\'}"
    APP_KEY_VALUE="${APP_KEY_VALUE%%\'*}"
    ;;
  *)
    [[ "$APP_KEY_VALUE" == *[[:space:]]#* ]] && APP_KEY_VALUE="${APP_KEY_VALUE%%[[:space:]]#*}"
    ;;
esac
APP_KEY_VALUE="${APP_KEY_VALUE%"${APP_KEY_VALUE##*[![:space:]]}"}"

if [[ -f "artisan" && -z "$APP_KEY_VALUE" ]]; then
  if "$PHP_BIN" artisan key:generate --force >/dev/null 2>&1; then
    echo "  Generated Laravel app key"
  fi
fi

exit 0
