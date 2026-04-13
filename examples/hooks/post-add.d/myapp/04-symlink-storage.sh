#!/bin/bash
# Symlink to shared storage/app directory for this specific repo
#
# This preserves uploaded files and generated content between worktrees
# by sharing a single storage/app directory across all worktrees.
#
# Benefits:
#   - Uploaded files persist across worktrees
#   - No need to re-upload test files in each worktree
#   - Shared user uploads, generated PDFs, cached images, etc.
#   - Smaller disk footprint (no duplicated storage)
#
# Setup:
#   1. Create a directory for shared storage:
#      mkdir -p ~/Code/Worktree/myapp/storage/app/public
#
#   2. Copy this hook to ~/.grove/hooks/post-add.d/myapp/
#
# Note: If you also symlink .env, this hook should run AFTER the .env
# symlink hook since Laravel may need .env for storage configuration.

# Path to your shared storage/app directory
STORAGE_APP_SOURCE="$HOME/Code/Worktree/${GROVE_REPO}/storage/app"

if [[ -d "$STORAGE_APP_SOURCE" ]]; then
  # Ensure storage directory exists in worktree
  mkdir -p "${GROVE_PATH}/storage"

  # Remove existing storage/app (directory or symlink)
  rm -rf "${GROVE_PATH}/storage/app"

  # Create symlink to shared storage/app
  ln -sf "$STORAGE_APP_SOURCE" "${GROVE_PATH}/storage/app"
  echo "  Linked storage/app → $STORAGE_APP_SOURCE"
else
  echo "  Shared storage/app not found at $STORAGE_APP_SOURCE"
  echo "  Creating it now..."
  mkdir -p "$STORAGE_APP_SOURCE/public"

  # Remove existing and create symlink
  rm -rf "${GROVE_PATH}/storage/app"
  ln -sf "$STORAGE_APP_SOURCE" "${GROVE_PATH}/storage/app"
  echo "  Created and linked storage/app → $STORAGE_APP_SOURCE"
fi

exit 0
