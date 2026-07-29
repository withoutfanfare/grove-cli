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
STORAGE_APP_TARGET="${GROVE_PATH}/storage/app"

mkdir -p "${GROVE_PATH}/storage"
if [[ ! -d "$STORAGE_APP_SOURCE" ]]; then
  echo "  Shared storage/app not found at $STORAGE_APP_SOURCE"
  echo "  Creating it now..."
  mkdir -p "$STORAGE_APP_SOURCE/public"
fi

if [[ -L "$STORAGE_APP_TARGET" ]]; then
  if [[ "$STORAGE_APP_TARGET" -ef "$STORAGE_APP_SOURCE" ]]; then
    echo "  storage/app is already linked → $STORAGE_APP_SOURCE"
    exit 0
  fi
  echo "  Refusing to replace storage/app symlink to another target"
  exit 1
elif [[ -e "$STORAGE_APP_TARGET" ]] && ! rmdir "$STORAGE_APP_TARGET" 2>/dev/null; then
  echo "  Refusing to replace non-empty storage/app (including tracked sentinels)"
  exit 1
fi

if ! ln -s "$STORAGE_APP_SOURCE" "$STORAGE_APP_TARGET"; then
  echo "  Failed to link storage/app"
  exit 1
fi
echo "  Linked storage/app → $STORAGE_APP_SOURCE"

exit 0
