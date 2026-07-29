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

# Refuse receiver symlinks and type collisions before rsync; --ignore-existing
# alone can still replace a directory symlink or alter directory metadata.
while IFS= read -r -d '' source_entry; do
  relative="${source_entry#"$SOURCE_DIR"/}"
  target_entry="$TARGET_DIR/$relative"
  if [[ -L "$target_entry" ]]; then
    echo "  Refusing AI import over symlink: $relative"
    exit 1
  fi
  if [[ -e "$target_entry" ]]; then
    if [[ -L "$source_entry" ]] ||
        { [[ -d "$source_entry" ]] && [[ ! -d "$target_entry" ]]; } ||
        { [[ ! -d "$source_entry" ]] && [[ -d "$target_entry" ]]; }; then
      echo "  Refusing AI import over type collision: $relative"
      exit 1
    fi
  fi
done < <(find "$SOURCE_DIR" -mindepth 1 -print0)

# Install missing entries only; preserve all existing files and directories.
rsync -rlt --links --ignore-existing --omit-dir-times --human-readable \
  "${EXCLUDE_ARGS[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

echo "  AI resources imported successfully"

exit 0
