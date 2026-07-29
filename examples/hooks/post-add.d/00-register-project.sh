#!/bin/bash
# Register worktree in ~/.projects for quick navigation
#
# This enables the cproj() shell function to quickly cd to worktrees.
# Add this to your ~/.zshrc:
#
#   cproj() {
#     local dir=$(grep "^$1=" ~/.projects 2>/dev/null | cut -d= -f2)
#     if [[ -n "$dir" && -d "$dir" ]]; then
#       cd "$dir"
#     else
#       echo "Project not found: $1"
#     fi
#   }

PROJECTS_FILE="$HOME/.projects"
PROJECT_KEY="${GROVE_PATH##*/}"

# Add the entry unless its literal key is already present.
if [[ -f "$PROJECTS_FILE" ]]; then
  while IFS='=' read -r key _; do
    [[ "$key" == "$PROJECT_KEY" ]] && exit 0
  done < "$PROJECTS_FILE"
fi

echo "${PROJECT_KEY}=${GROVE_PATH}" >> "$PROJECTS_FILE"
echo "  Registered project: ${PROJECT_KEY}"

exit 0
