#!/usr/bin/env zsh
# 05-database.sh - Database and Herd operations
#
# NOTE ON THE DB MODEL: grove does NOT create/back-up/drop databases itself during the
# worktree lifecycle. That work is delegated to user lifecycle hooks (see examples/hooks/
# post-add.d/, pre-rm.d/, post-rm.d/), which receive GROVE_DB_NAME / GROVE_DROP_DB /
# GROVE_NO_BACKUP from run_hooks. The create_database/backup_database/drop_database helpers
# below are a safe, MYSQL_PWD-based reference implementation that hooks may call (or copy);
# db_name_for() IS used directly (by health/info) to derive the canonical database name.

# db_name_for — Generate MySQL-safe database name for a repo/branch pair (≤64 chars)
db_name_for() {
  local repo="$1"
  local branch="$2"
  if [[ -n "${3:-}" ]]; then
    worktree_database_for "$repo" "$branch" "$3"
    return $?
  fi
  # Defence-in-depth: strip backticks so the name can never break out of a
  # `quoted` MySQL identifier even if a caller bypasses upstream validation.
  repo="${repo//\`/}"
  branch="${branch//\`/}"
  slugify_branch "$branch"
  local slug="$REPLY"
  # Replace dashes with underscores for MySQL compatibility
  local db_name="${repo}__${slug}"
  db_name="${db_name//-/_}"

  # MySQL database name limit is 64 characters
  if (( ${#db_name} > 64 )); then
    # Truncate and add hash suffix for uniqueness
    local hash; hash="$(print -r -- "$slug" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-8)"
    # Guard against an empty hash (no md5sum/md5 available): fall back to a
    # length-based suffix so distinct long names cannot collapse to the same name.
    if [[ -z "$hash" ]]; then
      hash="${#slug}"
    fi
    # Reserve space: 10 chars for "__" + 8-char hash (2 + 8 = 10)
    local max_repo_len=$((64 - 10))

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

# The database belongs to the worktree, not its current folder name. Store it
# beside Git's per-worktree index so git worktree move preserves the identity.
worktree_database_file() {
  local wt_path="$1" raw
  raw="$(git -C "$wt_path" rev-parse --git-path grove-database 2>/dev/null)" || return 1
  [[ "$raw" == /* ]] || raw="$wt_path/$raw"
  print -r -- "$raw"
}

_database_env_pair() {
  [[ "$1" == DB_DATABASE ]] && print -r -- "$2"
  return 0
}

worktree_database_for() {
  local repo="$1" branch="$2" wt_path="$3"
  local sidecar db_name="" expected
  sidecar="$(worktree_database_file "$wt_path")" || return 1
  if [[ -e "$sidecar" || -L "$sidecar" ]]; then
    [[ -f "$sidecar" && -r "$sidecar" ]] || return 1
    db_name="$(<"$sidecar")"
    _validate_database_name "$db_name" || return 1
    print -r -- "$db_name"
    return 0
  fi

  # Legacy worktrees may already have an explicitly selected database. Parse
  # literal values only; never source .env or evaluate shell substitutions.
  db_name="$(_read_config_pairs "$wt_path/.env" _database_env_pair)" || return 1
  if [[ -n "$db_name" ]]; then
    _validate_database_name "$db_name" || return 1
    print -r -- "$db_name"
    return 0
  fi

  expected="$(worktree_path_for "$repo" "$branch")"
  # Without recorded metadata, a custom folder could be an alias OR a move.
  # Guessing either name could select an unrelated database for backup/drop.
  [[ "${wt_path:A}" == "${expected:A}" ]] || return 1
  db_name_for "$repo" "$branch"
}

set_worktree_database() {
  local wt_path="$1" db_name="$2" sidecar tmp
  _validate_database_name "$db_name" || return 1
  sidecar="$(worktree_database_file "$wt_path")" || return 1
  tmp="$(mktemp "${sidecar}.tmp.XXXXXX")" || return 1
  if print -r -- "$db_name" > "$tmp" && mv -f "$tmp" "$sidecar"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# _validate_database_name — Reject unsafe MySQL identifiers supplied by hooks
_validate_database_name() {
  local db_name="${1:-}"

  if [[ -z "$db_name" || ${#db_name} -gt 64 || ! "$db_name" =~ ^[a-zA-Z0-9_.]+$ ]]; then
    warn "Refusing database operation for invalid database name: '$db_name'"
    return 1
  fi
}

# create_database — Create a MySQL database (respects DB_CREATE config)
create_database() {
  local db_name="$1"

  if [[ "$DB_CREATE" != "true" ]]; then
    dim "  Database creation disabled (GROVE_DB_CREATE=false)"
    return 0
  fi

  _validate_database_name "$db_name" || return 1

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

  _validate_database_name "$db_name" || return 1

  if ! command -v mysqldump >/dev/null 2>&1; then
    warn "mysqldump not found - refusing removal without a database backup"
    return 1
  fi

  # Probe connectivity FIRST so a connection/auth failure is never mistaken for
  # "database does not exist" — silently skipping the backup right before the
  # worktree (and DB) is removed would be data-loss-adjacent.
  local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER" -N -B)

  # Use MYSQL_PWD env var instead of -p flag to avoid password exposure in ps
  if ! MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
    warn "Cannot reach MySQL ($DB_HOST as $DB_USER) - NOT skipping backup silently"
    warn "Database may still exist; back up '$db_name' manually before removing the worktree"
    return 1
  fi

  # Connection is good — now decide existence via information_schema (a failed
  # USE could mean connection loss, so it is unsafe as an existence test).
  local database_exists
  if ! database_exists=$(MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" \
      -e "SELECT 1 FROM information_schema.SCHEMATA WHERE schema_name='$db_name';" 2>/dev/null); then
    warn "Could not check whether database $db_name exists - refusing removal without a backup"
    return 1
  fi
  if [[ "$database_exists" != "1" ]]; then
    dim "  Database $db_name does not exist - skipping backup"
    return 0
  fi

  (
    umask 077

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
  )
}

# drop_database — Drop a MySQL database by name
drop_database() {
  local db_name="$1"

  _validate_database_name "$db_name" || return 1

  if ! command -v mysql >/dev/null 2>&1; then
    # Consistent with create_database: a missing client is a non-fatal skip, not
    # a hard failure (avoids blocking worktree cleanup over an absent tool).
    warn "MySQL client not found - skipping database drop"
    dim "  Drop manually: DROP DATABASE \`$db_name\`;"
    return 0
  fi

  local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER" -N -B)

  # Probe connectivity first so a connection/auth failure is not mistaken for
  # "database does not exist" (which would silently leave the DB behind).
  if ! MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
    warn "Cannot reach MySQL ($DB_HOST as $DB_USER) - could not drop database"
    dim "  Drop manually: DROP DATABASE \`$db_name\`;"
    return 1
  fi

  # Decide existence via information_schema (a failed USE could mean a lost
  # connection, so it is unsafe as an existence test).
  local database_exists
  if ! database_exists=$(MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" \
      -e "SELECT 1 FROM information_schema.SCHEMATA WHERE schema_name='$db_name';" 2>/dev/null); then
    warn "Could not check whether database $db_name exists - database was not dropped"
    return 1
  fi
  if [[ "$database_exists" != "1" ]]; then
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

  # Validate BEFORE deriving any path we rm: site_name is interpolated straight
  # into delete targets, so a hostile value (path traversal, slash, dash, empty)
  # must never reach the filesystem operations below.
  if [[ -z "$site_name" || "$site_name" == *".."* || "$site_name" == */* \
        || "$site_name" == .* || "$site_name" == -* \
        || ! "$site_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    warn "Refusing to clean Herd files for invalid site name: '$site_name'"
    return 1
  fi

  local site_domain="${site_name}.test"
  local nginx_config="$HERD_CONFIG/valet/Nginx/$site_domain"
  local cert_dir="$HERD_CONFIG/valet/Certificates"
  local cleaned=false

  # Remove nginx config if it exists
  if [[ -f "$nginx_config" ]]; then
    rm -f "$nginx_config" 2>/dev/null && cleaned=true
  fi

  # Remove certificate files (crt, key, csr, conf)
  for ext in crt key csr conf; do
    local cert_file="$cert_dir/${site_domain}.${ext}"
    if [[ -f "$cert_file" ]]; then
      rm -f "$cert_file" 2>/dev/null && cleaned=true
    fi
  done

  if [[ "$cleaned" == true ]]; then
    dim "  Cleaned up Herd nginx config and certificates"
  fi
}
