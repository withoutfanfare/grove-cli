#!/bin/bash

# Import AI configuration and documentation files into worktree
# Source: ~/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-llm/
# Purpose: Quickly set up AI resources in git worktrees

set -e

SOURCE_DIR="$HOME/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-llm"
TARGET_DIR="${GROVE_PATH}"
CONFIG_FILE="$HOME/.import-ai.conf"

# Skip if source doesn't exist
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "  No LLM directory at $SOURCE_DIR - skipping"
  exit 0
fi

# Default exclusions
DEFAULT_EXCLUDE_PATTERNS=(
    ".claude/logs/session*"
    ".context/*"
    ".qoder"
    ".serena/"
    "*.log"
    ".cache"
    "private/*"
)

# Initialize exclude patterns with defaults
EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDE_PATTERNS[@]}")

# Load config file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
  EXCLUDE_PATTERNS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n "$line" ]] && EXCLUDE_PATTERNS+=("$line")
  done < "$CONFIG_FILE"
fi

# Build rsync exclude arguments
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  EXCLUDE_ARGS+=(--exclude="$pattern")
done

echo "  Importing AI files from $SOURCE_DIR..."

# Execute rsync
rsync -a --human-readable "${EXCLUDE_ARGS[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

echo "  AI resources imported successfully"

exit 0
