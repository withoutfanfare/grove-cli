#!/bin/bash
# Link a repo to use the shared Laravel hooks
#
# Usage: ./link-repo.sh <repo-name>
# Example: ./link-repo.sh newproject
#
# This creates symlinks from ~/.grove/hooks/post-add.d/<repo>/ to the
# shared _laravel hooks, so the repo gets Laravel-specific setup.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -z "$1" ]]; then
  echo "Usage: $0 <repo-name>"
  echo ""
  echo "Links a repo to use the shared Laravel post-add hooks."
  echo ""
  echo "Currently linked repos:"
  for dir in "$HOOKS_DIR"/*/; do
    [[ "$(basename "$dir")" == _* ]] && continue
    if [[ -L "$dir/01-ai-files.sh" ]]; then
      echo "  - $(basename "$dir")"
    fi
  done
  exit 1
fi

REPO="$1"
REPO_DIR="$HOOKS_DIR/$REPO"

if [[ ! "$REPO" =~ ^[[:alnum:]][[:alnum:]._-]*$ ]]; then
  echo "Invalid repo name: $REPO" >&2
  exit 1
fi

if [[ -L "$REPO_DIR" ]]; then
  echo "Refusing to write through symlinked repo directory: $REPO_DIR" >&2
  exit 1
fi

# Create repo directory if it doesn't exist
mkdir -p "$REPO_DIR"

# Create symlinks
for hook in "$SCRIPT_DIR"/*.sh; do
  hook_name=$(basename "$hook")
  [[ "$hook_name" == "link-repo.sh" ]] && continue
  hook_link="../_laravel/$hook_name"
  hook_target="$REPO_DIR/$hook_name"

  if [[ -e "$hook_target" || -L "$hook_target" ]]; then
    if [[ -L "$hook_target" && "$(readlink "$hook_target")" == "$hook_link" ]]; then
      echo "  Already linked $hook_name"
    else
      echo "  Preserved existing $hook_name"
    fi
    continue
  fi

  ln -s "$hook_link" "$hook_target"
  echo "  Linked $hook_name"
done

echo ""
echo "✓ $REPO is now using shared Laravel hooks"
echo ""
echo "Expected directory structure for $REPO:"
echo "  ~/Code/Worktree/$REPO/"
echo "    ├── ${REPO}-llm/        # AI/LLM files (optional)"
echo "    ├── ${REPO}-env/.env    # .env template - copied to each worktree (optional)"
echo "    ├── ${REPO}-db/${REPO}.sql.gz  # DB dump (optional)"
echo "    └── storage/app/        # Shared storage (created if missing)"

exit 0
