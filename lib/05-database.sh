#!/usr/bin/env zsh
# 05-database.sh - Database and Herd operations

# db_name_for — Generate MySQL-safe database name for a repo/branch pair (≤64 chars)
db_name_for() {
  local repo="$1"
  local branch="$2"
  slugify_branch "$branch"
  local slug="$REPLY"
  # Replace dashes with underscores for MySQL compatibility
  local db_name="${repo}__${slug}"
  db_name="${db_name//-/_}"

  # MySQL database name limit is 64 characters
  if (( ${#db_name} > 64 )); then
    # Truncate and add hash suffix for uniqueness
    local hash; hash="$(print -r -- "$slug" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-8)"
    # Reserve space: 11 chars for (__<8-char-hash>)
    local max_repo_len=$((64 - 11))

    # Ensure at least 5 chars of repo name preserved
    if (( ${#repo} < max_repo_len )); then
      max_repo_len=${#repo}
    fi
    if (( max_repo_len < 5 )); then
      max_repo_len=5
    fi

    local truncated_repo="${repo:0:$max_repo_len}"
    db_name="${truncated_repo}__${hash}"
    db_name="${db_name//-/_}"
  fi

  print -r -- "$db_name"
}

# create_database — Create a MySQL database (respects DB_CREATE config)
create_database() {
  local db_name="$1"

  if [[ "$DB_CREATE" != "true" ]]; then
    dim "  Database creation disabled (GROVE_DB_CREATE=false)"
    return 0
  fi

  if ! command -v mysql >/dev/null 2>&1; then
    warn "MySQL client not found - skipping database creation"
    dim "  Create manually: CREATE DATABASE \`$db_name\`;"
    return 0
  fi

  local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")

  info "Creating database ${C_CYAN}$db_name${C_RESET}"

  # Use MYSQL_PWD env var instead of -p flag to avoid password exposure in ps
  if MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "CREATE DATABASE IF NOT EXISTS \`$db_name\`;" 2>/dev/null; then
    ok "Database created: $db_name"
    return 0
  else
    warn "Could not create database - check MySQL connection"
    dim "  Create manually: CREATE DATABASE \`$db_name\`;"
    return 1
  fi
}

# backup_database — Dump a MySQL database to a timestamped SQL file (respects DB_BACKUP config)
backup_database() {
  local db_name="$1"
  local repo="$2"

  if [[ "$DB_BACKUP" != "true" ]]; then
    dim "  Database backup disabled (GROVE_DB_BACKUP=false)"
    return 0
  fi

  if ! command -v mysqldump >/dev/null 2>&1; then
    warn "mysqldump not found - skipping database backup"
    return 0
  fi

  # Check if database exists
  local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")

  # Use MYSQL_PWD env var instead of -p flag to avoid password exposure in ps
  if ! MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "USE \`$db_name\`;" 2>/dev/null; then
    dim "  Database $db_name does not exist - skipping backup"
    return 0
  fi

  # Create backup directory
  local backup_dir="$DB_BACKUP_DIR/$repo"
  mkdir -p "$backup_dir" || { warn "Could not create backup directory: $backup_dir"; return 1; }

  # Generate backup filename with timestamp
  local timestamp; timestamp="$(date +%Y%m%d_%H%M%S)"
  local backup_file="$backup_dir/${db_name}_${timestamp}.sql"

  local mysqldump_cmd=(mysqldump -h "$DB_HOST" -u "$DB_USER")

  info "Backing up database ${C_CYAN}$db_name${C_RESET}"

  # Use MYSQL_PWD env var instead of -p flag to avoid password exposure in ps
  if MYSQL_PWD="${DB_PASSWORD:-}" "${mysqldump_cmd[@]}" "$db_name" > "$backup_file" 2>/dev/null; then
    ok "Database backed up: ${C_DIM}$backup_file${C_RESET}"
    return 0
  else
    warn "Could not backup database"
    rm -f "$backup_file" 2>/dev/null
    return 1
  fi
}

# drop_database — Drop a MySQL database by name
drop_database() {
  local db_name="$1"

  if ! command -v mysql >/dev/null 2>&1; then
    warn "MySQL client not found - cannot drop database"
    return 1
  fi

  local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")

  # Check if database exists (use MYSQL_PWD env var for password)
  if ! MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "USE \`$db_name\`;" 2>/dev/null; then
    dim "  Database $db_name does not exist"
    return 0
  fi

  info "Dropping database ${C_CYAN}$db_name${C_RESET}"

  # Use MYSQL_PWD env var instead of -p flag to avoid password exposure in ps
  if MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "DROP DATABASE \`$db_name\`;" 2>/dev/null; then
    ok "Database dropped: $db_name"
    return 0
  else
    warn "Could not drop database"
    return 1
  fi
}

# unsecure_site — Remove Herd SSL for a site and clean up nginx/certificate files
unsecure_site() {
  local site_name="$1"

  if ! command -v herd >/dev/null 2>&1; then
    return 0
  fi

  info "Unsecuring site ${C_CYAN}$site_name${C_RESET}"
  if herd unsecure "$site_name" >/dev/null 2>&1; then
    ok "Site unsecured"
  else
    # Site might not be secured, which is fine
    dim "  Site was not secured or already unsecured"
  fi

  # Clean up Herd nginx configs and certificates to prevent stale config issues
  cleanup_herd_site "$site_name"
}

# cleanup_herd_site — Remove stale Herd nginx config and certificate files for a site
cleanup_herd_site() {
  local site_name="$1"
  local site_domain="${site_name}.test"
  local nginx_config="$HERD_CONFIG/valet/Nginx/$site_domain"
  local cert_dir="$HERD_CONFIG/valet/Certificates"
  local cleaned=false

  # Remove nginx config if it exists
  if [[ -f "$nginx_config" ]]; then
    /bin/rm -f "$nginx_config" 2>/dev/null && cleaned=true
  fi

  # Remove certificate files (crt, key, csr, conf)
  for ext in crt key csr conf; do
    local cert_file="$cert_dir/${site_domain}.${ext}"
    if [[ -f "$cert_file" ]]; then
      /bin/rm -f "$cert_file" 2>/dev/null && cleaned=true
    fi
  done

  if [[ "$cleaned" == true ]]; then
    dim "  Cleaned up Herd nginx config and certificates"
  fi
}
