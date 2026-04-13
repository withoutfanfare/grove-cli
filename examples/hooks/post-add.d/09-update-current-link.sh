#!/bin/bash
# Update {repo}-current symlink to point to the most recently created worktree
#
# This keeps a stable symlink for services like Laravel queue workers and
# schedulers that need a consistent path regardless of which worktree is active.
#
# The symlink is created at: ~/Herd/{repo}-current
# Pointing to: ~/Herd/{repo}-worktrees/{branch-slug}
#
# Skip by setting: GROVE_SKIP_CURRENT_LINK=true

if [[ "${GROVE_SKIP_CURRENT_LINK:-}" == "true" ]]; then
  echo "  Skipping current link update (GROVE_SKIP_CURRENT_LINK=true)"
  exit 0
fi

# Validate required environment variables
if [[ -z "$GROVE_REPO" || -z "$GROVE_PATH" ]]; then
  echo "  Skipping current link - missing GROVE_REPO or GROVE_PATH"
  exit 0
fi

# Derive the Herd folder from the worktree path
# GROVE_PATH is typically: ~/Herd/{repo}-worktrees/{branch-slug}
# We want: ~/Herd/{repo}-current
herd_folder="${GROVE_PATH%/*}"       # Remove branch-slug: ~/Herd/{repo}-worktrees
herd_folder="${herd_folder%/*}"   # Remove {repo}-worktrees: ~/Herd

# Verify this looks like a valid Herd folder
if [[ ! -d "$herd_folder" || "$herd_folder" != *"/Herd"* ]]; then
  echo "  Skipping current link - not in Herd folder"
  exit 0
fi

current_link="${herd_folder}/${GROVE_REPO}-current"

# Remove existing symlink (or broken symlink)
if [[ -L "$current_link" ]]; then
  rm -f "$current_link"
elif [[ -e "$current_link" ]]; then
  echo "  Warning: ${GROVE_REPO}-current exists but is not a symlink - skipping"
  exit 0
fi

# Create the new symlink
if ln -s "$GROVE_PATH" "$current_link"; then
  echo "  Updated ${GROVE_REPO}-current -> ${GROVE_PATH##*/}"
else
  echo "  Failed to create ${GROVE_REPO}-current symlink"
  exit 1
fi

exit 0
