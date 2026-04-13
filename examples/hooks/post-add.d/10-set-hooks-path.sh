#!/bin/bash
# Set core.hooksPath in the worktree to point to the bare repository's hooks
#
# Worktrees don't inherit the parent repo's hooks directory by default.
# This hook configures each new worktree to use the hooks from the bare
# repository, ensuring commit hooks (pre-commit, etc.) work consistently.
#
# Sets: git config core.hooksPath ~/Herd/{repo}.git/hooks
#
# Skip by setting: GROVE_SKIP_HOOKS_PATH=true

if [[ "${GROVE_SKIP_HOOKS_PATH:-}" == "true" ]]; then
  echo "  Skipping hooks path configuration (GROVE_SKIP_HOOKS_PATH=true)"
  exit 0
fi

# Validate required environment variables
if [[ -z "$GROVE_REPO" || -z "$GROVE_PATH" ]]; then
  echo "  Skipping hooks path - missing GROVE_REPO or GROVE_PATH"
  exit 0
fi

# Derive HERD_ROOT from GROVE_PATH
# GROVE_PATH is typically: ~/Herd/{repo}-worktrees/{branch-slug}
herd_root="${GROVE_PATH%/*}"       # Remove branch-slug
herd_root="${herd_root%/*}"     # Remove {repo}-worktrees

bare_repo="${herd_root}/${GROVE_REPO}.git"
hooks_dir="${bare_repo}/hooks"

# Verify the bare repo exists
if [[ ! -d "$bare_repo" ]]; then
  echo "  Skipping hooks path - bare repo not found: $bare_repo"
  exit 0
fi

# Ensure hooks directory exists
if [[ ! -d "$hooks_dir" ]]; then
  mkdir -p "$hooks_dir"
fi

# Set core.hooksPath in the worktree
if git config core.hooksPath "$hooks_dir"; then
  echo "  Set core.hooksPath -> $hooks_dir"
else
  echo "  Failed to set core.hooksPath"
  exit 1
fi

exit 0
