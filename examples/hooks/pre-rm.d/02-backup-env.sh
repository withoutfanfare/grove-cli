#!/bin/bash
# Backup worktree .env before removal
#
# Copies the worktree's .env to the template folder with a timestamp,
# allowing you to review any changes made during development before
# deciding whether to merge them into the main .env template.
#
# Backup location: ~/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env.backup.${branch_slug}.${timestamp}
#
# After removal, compare with:
#   diff ~/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env ~/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env.backup.*

if [[ ! -f "${GROVE_PATH}/.env" ]]; then
  exit 0
fi

# Skip if .env is a symlink (nothing worktree-specific to backup)
if [[ -L "${GROVE_PATH}/.env" ]]; then
  exit 0
fi

ENV_TEMPLATE_DIR="$HOME/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env"

# A real .env is worktree-specific data. Create its private backup directory
# rather than allowing removal merely because the repo was not preconfigured.
umask 077
mkdir -p "$ENV_TEMPLATE_DIR" || { echo "  Failed to create .env backup directory - refusing removal"; exit 1; }

# Create backup filename with branch slug and timestamp
BRANCH_SLUG="${GROVE_BRANCH//\//-}"  # Replace / with -
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${ENV_TEMPLATE_DIR}/.env.backup.${BRANCH_SLUG}.${TIMESTAMP}"

if cp "${GROVE_PATH}/.env" "$BACKUP_FILE" && chmod 600 "$BACKUP_FILE"; then
  echo "  Backed up .env → ${BACKUP_FILE##*/}"
  echo "  Compare with: diff ${ENV_TEMPLATE_DIR}/.env $BACKUP_FILE"
else
  echo "  Failed to backup .env - refusing removal"
  rm -f "$BACKUP_FILE"
  exit 1
fi

exit 0
