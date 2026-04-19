#!/bin/bash
# Symlink to shared storage/app for this repo
#
# This preserves uploaded files and generated content between worktrees
# by sharing a single storage/app directory.
#
# Expected path: ~/Development/Code/Worktree/${GROVE_REPO}/storage/app

STORAGE_APP_SOURCE="$HOME/Development/Code/Worktree/${GROVE_REPO}/storage/app"

# Ensure storage directory exists in worktree
mkdir -p "${GROVE_PATH}/storage"

if [[ -d "$STORAGE_APP_SOURCE" ]]; then
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
