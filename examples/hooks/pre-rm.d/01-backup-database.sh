#!/bin/bash
# Backup database before worktree removal
#
# Creates a timestamped SQL backup in the configured backup directory.
#
# Respects configuration hierarchy:
#   1. Global config (~/.groverc)
#   2. Project config ($HERD_ROOT/.groveconfig)
#   3. Repo-specific config ($HERD_ROOT/$GROVE_REPO.git/.groveconfig)
#
# Logic:
#   - If DB_CREATE=false: Skip (databases aren't managed by grove)
#   - If DB_BACKUP=false: Skip (backups disabled)
#   - If GROVE_NO_BACKUP=true (--no-backup flag): Skip
#
# Uses: DB_HOST, DB_USER, DB_PASSWORD, DB_BACKUP_DIR

# Check for --no-backup flag first
if [[ "${GROVE_NO_BACKUP:-}" == "true" ]]; then
  echo "  Skipping database backup (--no-backup)"
  exit 0
fi

# Load configuration (global -> project -> repo-specific)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../_lib/load-config.sh"
else
  # Fallback: load from ~/.groverc directly
  if [[ -f "$HOME/.groverc" ]]; then
    DB_HOST="${DB_HOST:-$(grep '^DB_HOST=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_USER="${DB_USER:-$(grep '^DB_USER=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_PASSWORD="${DB_PASSWORD:-$(grep '^DB_PASSWORD=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_CREATE="${DB_CREATE:-$(grep '^DB_CREATE=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_BACKUP="${DB_BACKUP:-$(grep '^DB_BACKUP=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2-)}"
    DB_BACKUP_DIR="${DB_BACKUP_DIR:-$(grep '^DB_BACKUP_DIR=' "$HOME/.groverc" 2>/dev/null | cut -d= -f2- | sed 's|\$HOME|'"$HOME"'|g' | tr -d '"')}"
  fi
  DB_HOST="${DB_HOST:-127.0.0.1}"
  DB_USER="${DB_USER:-root}"
  DB_PASSWORD="${DB_PASSWORD:-}"
  DB_CREATE="${DB_CREATE:-true}"
  DB_BACKUP="${DB_BACKUP:-true}"
  DB_BACKUP_DIR="${DB_BACKUP_DIR:-$HOME/Code/Project Support/Worktree/Database/Backup}"
fi

# If database creation is disabled, we don't manage databases - skip silently
if [[ "$DB_CREATE" != "true" ]]; then
  exit 0
fi

# If backups are disabled, skip
if [[ "$DB_BACKUP" != "true" ]]; then
  echo "  Skipping database backup (DB_BACKUP=$DB_BACKUP)"
  exit 0
fi

if ! command -v mysqldump >/dev/null 2>&1; then
  echo "  mysqldump not found - skipping backup"
  exit 0
fi

# Build mysql command to check if database exists
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")
[[ -n "$DB_PASSWORD" ]] && mysql_cmd+=(-p"$DB_PASSWORD")

# Check if database exists
if ! "${mysql_cmd[@]}" -e "USE \`${GROVE_DB_NAME}\`;" 2>/dev/null; then
  echo "  Database ${GROVE_DB_NAME} does not exist - skipping backup"
  exit 0
fi

# Create backup directory
backup_dir="$DB_BACKUP_DIR/$GROVE_REPO"
mkdir -p "$backup_dir" || { echo "  Could not create backup directory"; exit 0; }

# Generate backup filename with timestamp
timestamp="$(date +%Y%m%d_%H%M%S)"
backup_file="$backup_dir/${GROVE_DB_NAME}_${timestamp}.sql"

# Build mysqldump command
mysqldump_cmd=(mysqldump -h "$DB_HOST" -u "$DB_USER")
[[ -n "$DB_PASSWORD" ]] && mysqldump_cmd+=(-p"$DB_PASSWORD")

echo "  Backing up database ${GROVE_DB_NAME}..."
if "${mysqldump_cmd[@]}" "$GROVE_DB_NAME" > "$backup_file" 2>/dev/null; then
  echo "  Backup saved: $backup_file"
  exit 0
else
  echo "  Backup failed - continuing anyway"
  rm -f "$backup_file" 2>/dev/null
  exit 0
fi
