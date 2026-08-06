#!/bin/bash
# Symlink to shared storage/app for this repo
#
# This preserves uploaded files and generated content between worktrees
# by sharing a single storage/app directory.
#
# Expected path: ~/Development/Code/Worktree/${GROVE_REPO}/storage/app

STORAGE_APP_SOURCE="$HOME/Development/Code/Worktree/${GROVE_REPO}/storage/app"
STORAGE_APP_TARGET="${GROVE_PATH}/storage/app"

# Ensure storage directory exists in worktree
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
