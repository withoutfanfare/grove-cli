#!/bin/bash
# Shared configuration loader for grove hooks
#
# Loads configuration in order (later values override earlier):
#   1. Defaults
#   2. Global config (~/.groverc)
#   3. Project config ($HERD_ROOT/.groveconfig)
#   4. Repo-specific config ($HERD_ROOT/$GROVE_REPO.git/.groveconfig)
#
# Usage: source this file at the start of your hook
#   source "$(dirname "$0")/../_lib/load-config.sh"
#
# After sourcing, these variables are available:
#   DB_HOST, DB_USER, DB_PASSWORD, DB_CREATE, DB_BACKUP, DB_BACKUP_DIR
#   HERD_ROOT, HERD_CONFIG, DEFAULT_BASE, PROTECTED_BRANCHES

# Set defaults
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_CREATE="${DB_CREATE:-true}"
DB_BACKUP="${DB_BACKUP:-true}"
DB_BACKUP_DIR="${DB_BACKUP_DIR:-$HOME/Code/Project Support/Worktree/Database/Backup}"
HERD_ROOT="${HERD_ROOT:-$HOME/Herd}"
HERD_CONFIG="${HERD_CONFIG:-$HOME/Library/Application Support/Herd/config}"

# Parse a config file safely (key=value format)
# Only sets whitelisted variables
_load_config_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" || "$key" =~ ^[[:space:]]*$ ]] && continue

    # Trim whitespace from key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    # Remove quotes and trailing comments from value
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    value="${value%%#*}"
    value="${value%"${value##*[![:space:]]}"}"

    # Expand $HOME in value
    value="${value//\$HOME/$HOME}"

    # Only set whitelisted variables
    case "$key" in
      HERD_ROOT) HERD_ROOT="$value" ;;
      HERD_CONFIG) HERD_CONFIG="$value" ;;
      DB_HOST) DB_HOST="$value" ;;
      DB_USER) DB_USER="$value" ;;
      DB_PASSWORD) DB_PASSWORD="$value" ;;
      DB_CREATE) DB_CREATE="$value" ;;
      DB_BACKUP) DB_BACKUP="$value" ;;
      DB_BACKUP_DIR) DB_BACKUP_DIR="$value" ;;
      DEFAULT_BASE) DEFAULT_BASE="$value" ;;
      PROTECTED_BRANCHES) PROTECTED_BRANCHES="$value" ;;
    esac
  done < "$file"
}

# Load configs in order (later overrides earlier)
# 1. Global config
_load_config_file "$HOME/.groverc"

# 2. Project config (needs HERD_ROOT from step 1)
_load_config_file "$HERD_ROOT/.groveconfig"

# 3. Repo-specific config (uses GROVE_REPO from hook environment)
if [[ -n "$GROVE_REPO" ]]; then
  _load_config_file "$HERD_ROOT/${GROVE_REPO}.git/.groveconfig"
fi

# Export for subprocesses
export DB_HOST DB_USER DB_PASSWORD DB_CREATE DB_BACKUP DB_BACKUP_DIR
export HERD_ROOT HERD_CONFIG DEFAULT_BASE PROTECTED_BRANCHES
