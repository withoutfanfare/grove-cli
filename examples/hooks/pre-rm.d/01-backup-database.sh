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
  echo "  Config loader not found - refusing removal without a safe backup check"
  exit 1
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

grove_validate_database_name "${GROVE_DB_NAME:-}" || exit 1

if ! command -v mysql >/dev/null 2>&1 || ! command -v mysqldump >/dev/null 2>&1; then
  echo "  MySQL backup tools not found - refusing removal without a backup"
  exit 1
fi

# Check connectivity separately so an authentication or server failure is not
# mistaken for a database that does not exist.
mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER" -N -B)
if ! MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "  Cannot reach MySQL - refusing removal without a database backup"
  exit 1
fi

# Check if database exists
if ! database_exists=$(MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" \
    -e "SELECT 1 FROM information_schema.SCHEMATA WHERE schema_name='${GROVE_DB_NAME}';" 2>/dev/null); then
  echo "  Could not check database - refusing removal without a backup"
  exit 1
fi
if [[ "$database_exists" != "1" ]]; then
  echo "  Database ${GROVE_DB_NAME} does not exist - skipping backup"
  exit 0
fi

# Create backup directory
umask 077
backup_dir="$DB_BACKUP_DIR/$GROVE_REPO"
mkdir -p "$backup_dir" || { echo "  Could not create backup directory"; exit 1; }

# Generate backup filename with timestamp
timestamp="$(date +%Y%m%d_%H%M%S)"
backup_file="$backup_dir/${GROVE_DB_NAME}_${timestamp}.sql"

# Build mysqldump command
mysqldump_cmd=(mysqldump -h "$DB_HOST" -u "$DB_USER")

echo "  Backing up database ${GROVE_DB_NAME}..."
if MYSQL_PWD="${DB_PASSWORD:-}" "${mysqldump_cmd[@]}" "$GROVE_DB_NAME" > "$backup_file" 2>/dev/null; then
  echo "  Backup saved: $backup_file"
  exit 0
else
  echo "  Backup failed - refusing removal"
  rm -f "$backup_file" 2>/dev/null
  exit 1
fi
