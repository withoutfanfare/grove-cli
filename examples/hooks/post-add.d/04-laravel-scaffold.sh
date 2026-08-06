#!/bin/bash
# Ensure Laravel runtime directories exist before composer install runs.
#
# Fresh worktrees can be missing bootstrap/cache or storage/framework/views
# if the repo's .gitignore excludes the directories outright (instead of the
# Laravel convention of ignoring contents but tracking a .gitignore sentinel).
# When those dirs are missing, `composer install` -> package:discover fails
# with "bootstrap/cache directory must be present and writable", and
# subsequent hooks (key:generate, migrate, custom artisan commands) fail
# silently via their `>/dev/null` redirects.
#
# This hook is defensive — it only creates dirs that are missing, and exits
# quietly for non-Laravel repos. Runs before 05-composer-install.sh.

if [[ ! -f "${GROVE_PATH}/artisan" ]]; then
  exit 0
fi

umask 077

ensure_dir() {
  local rel="$1"
  local full="${GROVE_PATH}/${rel}"
  if [[ ! -d "$full" ]]; then
    mkdir -p "$full"
    echo "  Created ${rel}"
  fi
}

ensure_dir "bootstrap/cache"
ensure_dir "storage/framework/cache/data"
ensure_dir "storage/framework/sessions"
ensure_dir "storage/framework/testing"
ensure_dir "storage/framework/views"
ensure_dir "storage/logs"

# Herd runs PHP as the current user, so runtime files do not need to be exposed
# to every account in the caller's default macOS group.
chmod -R u+rwX,go-rwx "${GROVE_PATH}/bootstrap/cache" "${GROVE_PATH}/storage" 2>/dev/null || true

exit 0
