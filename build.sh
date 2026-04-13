#!/usr/bin/env zsh
# build.sh - Concatenates lib/ modules into single grove distribution file
#
# Usage: ./build.sh [--output <file>]
#
# This script combines all modular source files from lib/ into a single
# executable grove script for distribution and installation.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT="${1:-$SCRIPT_DIR/grove}"

# Handle --output flag
if [[ "${1:-}" == "--output" && -n "${2:-}" ]]; then
  OUTPUT="$2"
fi

echo "Building grove from lib/ modules..."

# Start fresh
: > "$OUTPUT"

# Module order matters - dependencies must come first
MODULES=(
  "00-header.sh"
  "01-core.sh"
  "02-validation.sh"
  "03-paths.sh"
  "04-git.sh"
  "05-database.sh"
  "06-hooks.sh"
  "07-templates.sh"
  "08-spinner.sh"
  "09-parallel.sh"
  "10-interactive.sh"
  "11-resilience.sh"
  "12-deps.sh"
)

COMMAND_MODULES=(
  "lifecycle.sh"
  "git-ops.sh"
  "navigation.sh"
  "info.sh"
  "maintenance.sh"
  "bulk-ops.sh"
  "discovery.sh"
  "config.sh"
  "laravel.sh"
)

# Concatenate core modules
for module in "${MODULES[@]}"; do
  module_path="$SCRIPT_DIR/lib/$module"
  if [[ -f "$module_path" ]]; then
    if [[ "$module" == "00-header.sh" ]]; then
      # Include header with shebang
      cat "$module_path" >> "$OUTPUT"
    else
      # Skip shebang line for other modules
      tail -n +2 "$module_path" >> "$OUTPUT"
    fi
    echo "" >> "$OUTPUT"  # Add blank line between modules
  else
    echo "Warning: Module not found: $module" >&2
  fi
done

# Concatenate command modules
for module in "${COMMAND_MODULES[@]}"; do
  cmd_path="$SCRIPT_DIR/lib/commands/$module"
  if [[ -f "$cmd_path" ]]; then
    tail -n +2 "$cmd_path" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
  else
    echo "Warning: Command module not found: $module" >&2
  fi
done

# Concatenate main entry point
if [[ -f "$SCRIPT_DIR/lib/99-main.sh" ]]; then
  tail -n +2 "$SCRIPT_DIR/lib/99-main.sh" >> "$OUTPUT"
else
  echo "Error: Main entry point not found: lib/99-main.sh" >&2
  exit 1
fi

# Make executable
chmod +x "$OUTPUT"

# Count lines
line_count=$(wc -l < "$OUTPUT" | tr -d ' ')

echo "Built: $OUTPUT ($line_count lines)"
echo "Done!"
