#!/bin/bash
# Link and secure site with Laravel Herd HTTPS
#
# Links the worktree directory to Herd (required for subdirectories)
# then creates an SSL certificate for the local development site.
# If GROVE_URL contains a subdomain (e.g., api.feature-name.test),
# the subdomain site is also linked and secured.
# Skip by setting: GROVE_SKIP_HERD=true
#
# Note: Herd has a known issue where nginx doesn't properly reload SSL configs.
# This hook sends a HUP signal to nginx workers and verifies the certificate.

if [[ "${GROVE_SKIP_HERD:-}" == "true" ]]; then
  echo "  Skipping Herd link/secure (GROVE_SKIP_HERD=true)"
  exit 0
fi

if ! command -v herd >/dev/null 2>&1; then
  echo "  Herd not found - skipping site setup"
  exit 0
fi

# Get site name from path (last component)
site_name="${GROVE_PATH##*/}"

# Extract full domain from GROVE_URL (e.g., https://api.feature-name.test -> api.feature-name.test)
full_domain="${GROVE_URL#https://}"
full_domain="${full_domain#http://}"
base_domain="${site_name}.test"

# Determine if GROVE_URL includes a subdomain prefix
subdomain_site=""
if [[ -n "$full_domain" && "$full_domain" != "$base_domain" ]]; then
  subdomain_site="${full_domain%.test}"
fi

# Link the base site (required for worktrees in subdirectories)
if (cd "$GROVE_PATH" && herd link) >/dev/null 2>&1; then
  echo "  Linked site: ${site_name}"
else
  echo "  ⚠ Could not link site: ${site_name}"
fi

# If URL has a subdomain prefix, also link the subdomain site
if [[ -n "$subdomain_site" ]]; then
  if (cd "$GROVE_PATH" && herd link "$subdomain_site") >/dev/null 2>&1; then
    echo "  Linked subdomain site: ${subdomain_site}"
  else
    echo "  ⚠ Could not link subdomain site: ${subdomain_site}"
  fi
fi

# Secure the base site
secured_base=false
if herd secure "$site_name" >/dev/null 2>&1; then
  echo "  Secured site: ${site_name}"
  secured_base=true
else
  echo "  Could not secure site - run: herd secure ${site_name}"
fi

# Secure the subdomain site
if [[ -n "$subdomain_site" ]]; then
  if herd secure "$subdomain_site" >/dev/null 2>&1; then
    echo "  Secured subdomain site: ${subdomain_site}"
  else
    echo "  Could not secure subdomain site - run: herd secure ${subdomain_site}"
  fi
fi

# Force nginx workers to reload (clears stale SSL session cache)
# Only target Herd's nginx processes to avoid affecting other nginx instances
if [[ "$secured_base" == true ]]; then
  nginx_pids=$(pgrep -u "$USER" nginx 2>/dev/null || true)
  if [[ -n "$nginx_pids" ]]; then
    # Check if these are Herd nginx processes (command contains Herd path)
    if ps -o command= -p $nginx_pids 2>/dev/null | grep -q "Herd"; then
      pkill -HUP -u "$USER" nginx 2>/dev/null || true
      # Configurable wait for nginx reload (default 3s for reliability)
      sleep "${GROVE_NGINX_RELOAD_WAIT:-3}"
    fi
  fi

  # Verify the certificate is being served correctly
  if command -v openssl >/dev/null 2>&1; then
    # Verify base domain cert
    served_cert=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$base_domain" 2>/dev/null | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null | awk -F'CN=' 'NF>1{split($2,a,","); print a[1]}')

    if [[ "$served_cert" != "$base_domain" ]]; then
      echo "  ⚠ SSL mismatch: nginx serving '$served_cert' instead of '$base_domain'"
      echo "  ⚠ Fix with: pkill -9 nginx && herd start"
    fi

    # Verify subdomain cert if applicable
    if [[ -n "$subdomain_site" ]]; then
      served_cert=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$full_domain" 2>/dev/null | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null | awk -F'CN=' 'NF>1{split($2,a,","); print a[1]}')

      if [[ "$served_cert" != "$full_domain" ]]; then
        echo "  ⚠ SSL mismatch for subdomain: nginx serving '$served_cert' instead of '$full_domain'"
        echo "  ⚠ Fix with: pkill -9 nginx && herd start"
      fi
    fi
  fi
fi

exit 0
