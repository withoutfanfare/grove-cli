#!/usr/bin/env zsh
# build.sh - Concatenates lib/ modules into single grove distribution file
#
# Usage: ./build.sh [--output <file>]
#
# This script combines all modular source files from lib/ into a single
# executable grove script for distribution and installation.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT="$SCRIPT_DIR/grove"

# Parse arguments. --output requires a non-empty, non-whitespace path; a bare
# --output (or one followed by a space-only value) is a usage error rather than
# silently writing to a file literally named "--output".
if [[ "${1:-}" == "--output" ]]; then
  if [[ -z "${2:-}" || -z "${2// /}" ]]; then
    echo "Error: --output requires a file path" >&2
    echo "Usage: ./build.sh [--output <file>]" >&2
    exit 1
  fi
  OUTPUT="$2"
elif [[ -n "${1:-}" ]]; then
  # A single positional argument is treated as the output path (back-compat).
  OUTPUT="$1"
fi

echo "Building grove from lib/ modules..."

# Start fresh
: > "$OUTPUT"

# Append a module, stripping only a genuine leading shebang (#!) so the combined
# file keeps a single shebang. A module whose first line is real code is appended
# verbatim rather than having a valid line of code silently removed.
append_module() {
  # Note: avoid naming this `path` — in zsh that local would clobber the special
  # $path/$PATH array and break command lookup for the rest of the function.
  local module_file="$1"
  local first_line
  read -r first_line < "$module_file"
  if [[ "$first_line" == '#!'* ]]; then
    tail -n +2 "$module_file" >> "$OUTPUT"
  else
    cat "$module_file" >> "$OUTPUT"
  fi
}

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
  "services.sh"
)

# Concatenate core modules
for module in "${MODULES[@]}"; do
  module_path="$SCRIPT_DIR/lib/$module"
  if [[ -f "$module_path" ]]; then
    if [[ "$module" == "00-header.sh" ]]; then
      # Include header with shebang
      cat "$module_path" >> "$OUTPUT"
    else
      # Strip the leading shebang for other modules (only if present)
      append_module "$module_path"
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
    append_module "$cmd_path"
    echo "" >> "$OUTPUT"
  else
    echo "Warning: Command module not found: $module" >&2
  fi
done

# Concatenate main entry point
if [[ -f "$SCRIPT_DIR/lib/99-main.sh" ]]; then
  append_module "$SCRIPT_DIR/lib/99-main.sh"
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
