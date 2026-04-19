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

# Create repo directory if it doesn't exist
mkdir -p "$REPO_DIR"

# Create symlinks
for hook in "$SCRIPT_DIR"/*.sh; do
  hook_name=$(basename "$hook")
  [[ "$hook_name" == "link-repo.sh" ]] && continue

  ln -sf "../_laravel/$hook_name" "$REPO_DIR/$hook_name"
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
