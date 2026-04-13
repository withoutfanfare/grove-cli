#!/bin/bash
# Configure .env with worktree-specific values (early pass)
#
# This runs BEFORE repo-specific hooks. If a repo symlinks its .env,
# changes made here will be lost. Use a repo-specific hook (e.g.,
# post-add.d/myapp/03-configure-env.sh) for final configuration.
#
# Sets (if present in .env):
#   - APP_URL (always)
#   - VITE_APP_URL (to match APP_URL, for Vite dev server)
#   - MULTITENANCY_LANDLORD_DOMAIN (base domain only, for multi-tenant apps)
#   - MULTITENANCY_TENANT_PROTOCOL (matches URL protocol)
#
# DB_DATABASE is set later by a repo-specific hook (after .env symlink).
#
# Requires: .env file exists

if [[ ! -f "${GROVE_PATH}/.env" ]]; then
  exit 0
fi

cd "$GROVE_PATH" || exit 0

# Helper function for sed (handles macOS vs Linux)
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Extract protocol from GROVE_URL (https or http)
if [[ "$GROVE_URL" == https://* ]]; then
  URL_PROTOCOL="https"
else
  URL_PROTOCOL="http"
fi

# Set APP_URL (this may be overwritten if repo symlinks .env later)
if grep -q "^APP_URL=" .env 2>/dev/null; then
  sed_inplace "s|^APP_URL=.*|APP_URL=${GROVE_URL}|" .env
  echo "  Set APP_URL=${GROVE_URL}"
fi

# Set VITE_APP_URL to match APP_URL (for Vite dev server)
if grep -q "^VITE_APP_URL=" .env 2>/dev/null; then
  sed_inplace "s|^VITE_APP_URL=.*|VITE_APP_URL=${GROVE_URL}|" .env
  echo "  Set VITE_APP_URL=${GROVE_URL}"
fi

# Set MULTITENANCY_LANDLORD_DOMAIN for multi-tenant Laravel apps
# This must be the BASE domain (without subdomain prefix) so tenant resolution works.
# e.g., for URL https://charity-meals.speed-issues-0902.test:
#   - Full domain: charity-meals.speed-issues-0902.test (used for APP_URL)
#   - Landlord domain: speed-issues-0902.test (base domain from folder name)
#   - Tenant subdomain: charity-meals (resolved by the app at runtime)
if grep -q "^MULTITENANCY_LANDLORD_DOMAIN=" .env 2>/dev/null; then
  site_name="${GROVE_PATH##*/}"
  landlord_domain="${site_name}.test"
  sed_inplace "s|^MULTITENANCY_LANDLORD_DOMAIN=.*|MULTITENANCY_LANDLORD_DOMAIN=\"${landlord_domain}\"|" .env
  echo "  Set MULTITENANCY_LANDLORD_DOMAIN=\"${landlord_domain}\""
fi

# Set MULTITENANCY_TENANT_PROTOCOL to match URL protocol
if grep -q "^MULTITENANCY_TENANT_PROTOCOL=" .env 2>/dev/null; then
  sed_inplace "s|^MULTITENANCY_TENANT_PROTOCOL=.*|MULTITENANCY_TENANT_PROTOCOL=\"${URL_PROTOCOL}\"|" .env
  echo "  Set MULTITENANCY_TENANT_PROTOCOL=\"${URL_PROTOCOL}\""
fi

# Note: DB_DATABASE is NOT set here because:
# 1. If DB_CREATE=false, we shouldn't modify DB_DATABASE
# 2. Repo-specific hooks may symlink .env, losing any changes made here
# DB_DATABASE should be set in repo-specific hooks after .env is finalised

exit 0
