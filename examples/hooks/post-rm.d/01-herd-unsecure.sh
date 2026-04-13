#!/bin/bash
# Unlink, unsecure site and clean up Herd configuration
#
# Removes the site link, SSL certificate, and nginx config for the site.
# If GROVE_URL contains a subdomain (e.g., api.feature-name.test),
# the subdomain site is also cleaned up.
#
# Respects configuration:
#   - HERD_CONFIG from config hierarchy (defaults to standard Herd location)

if ! command -v herd >/dev/null 2>&1; then
  exit 0
fi

# Load configuration (global -> project -> repo-specific)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../_lib/load-config.sh"
fi

# Default HERD_CONFIG if not set by config loader
HERD_CONFIG="${HERD_CONFIG:-$HOME/Library/Application Support/Herd/config}"

# Get site name from path (last component)
site_name="${GROVE_PATH##*/}"

# Extract full domain from GROVE_URL to detect subdomain prefix
full_domain="${GROVE_URL#https://}"
full_domain="${full_domain#http://}"
base_domain="${site_name}.test"

# Determine if GROVE_URL includes a subdomain prefix
subdomain_site=""
if [[ -n "$full_domain" && "$full_domain" != "$base_domain" ]]; then
  subdomain_site="${full_domain%.test}"
fi

# Unsecure the base site
herd unsecure "$site_name" >/dev/null 2>&1 || true

# Unsecure the subdomain site if applicable
if [[ -n "$subdomain_site" ]]; then
  herd unsecure "$subdomain_site" >/dev/null 2>&1 || true
fi

# Clean up Herd nginx configs and certificates
# This prevents nginx from failing due to stale configs
_cleanup_herd_site() {
  local domain="$1"
  local name="$2"

  # Remove nginx config
  local nginx_config="$HERD_CONFIG/valet/Nginx/$domain"
  [[ -f "$nginx_config" ]] && rm -f "$nginx_config" 2>/dev/null

  # Remove certificate files
  local cert_dir="$HERD_CONFIG/valet/Certificates"
  for ext in crt key csr conf; do
    [[ -f "$cert_dir/${domain}.${ext}" ]] && rm -f "$cert_dir/${domain}.${ext}" 2>/dev/null
  done

  # Remove the site symlink (unlink)
  local sites_dir="$HERD_CONFIG/valet/Sites"
  local site_link="$sites_dir/$name"
  [[ -L "$site_link" ]] && rm -f "$site_link" 2>/dev/null
}

# Clean up base site
_cleanup_herd_site "$base_domain" "$site_name"

# Clean up subdomain site if applicable
if [[ -n "$subdomain_site" ]]; then
  subdomain_domain="${subdomain_site}.test"
  _cleanup_herd_site "$subdomain_domain" "$subdomain_site"
  echo "  Cleaned up Herd config for ${site_name} and ${subdomain_site}"
else
  echo "  Cleaned up Herd config for ${site_name}"
fi

exit 0
