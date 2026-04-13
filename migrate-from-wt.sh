#!/usr/bin/env bash
# migrate-from-wt.sh - Migrate from wt to grove (rebranded worktree manager)
#
# This script helps existing wt users migrate their configuration, hooks,
# templates, and per-repo settings to the new grove naming convention.
#
# Usage:
#   ./migrate-from-wt.sh [--dry-run] [--no-symlink] [--force]
#
# Flags:
#   --dry-run      Show what would be done without making changes
#   --no-symlink   Skip creating wt -> grove symlink
#   --force        Don't prompt for confirmation

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

DRY_RUN=false
NO_SYMLINK=false
FORCE=false

# Colour codes (disabled if not a tty)
C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_DIM="" C_BOLD=""
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
fi

# Counters for summary
CHANGES_MADE=0
WARNINGS_ISSUED=0
SKIPPED=0

# ============================================================================
# Output helpers
# ============================================================================

info()    { echo "${C_BLUE}->  ${C_RESET}$*"; }
ok()      { echo "${C_GREEN} ok ${C_RESET}$*"; }
warn()    { echo "${C_YELLOW} !! ${C_RESET}$*"; WARNINGS_ISSUED=$((WARNINGS_ISSUED + 1)); }
error()   { echo "${C_RED}ERR ${C_RESET}$*" >&2; }
dim()     { echo "${C_DIM}    $*${C_RESET}"; }
dry()     { echo "${C_CYAN}dry ${C_RESET}$*"; }
skip()    { echo "${C_DIM}--- ${C_RESET}$*"; SKIPPED=$((SKIPPED + 1)); }

# ============================================================================
# Helpers
# ============================================================================

timestamp() {
  date +%Y%m%d-%H%M%S
}

backup_path() {
  local path="$1"
  echo "${path}.bak.$(timestamp)"
}

# Create a backup of a file or directory
# Returns 0 on success, 1 on failure
backup_item() {
  local src="$1"
  local bak
  bak="$(backup_path "$src")"

  if [[ "$DRY_RUN" == true ]]; then
    dry "Would back up: $src -> $bak"
    return 0
  fi

  if cp -a "$src" "$bak" 2>/dev/null; then
    ok "Backed up: ${C_DIM}$src${C_RESET} -> ${C_DIM}$bak${C_RESET}"
    return 0
  else
    error "Failed to back up: $src"
    return 1
  fi
}

# Rename a file or directory
rename_item() {
  local src="$1"
  local dst="$2"

  if [[ "$DRY_RUN" == true ]]; then
    dry "Would rename: $src -> $dst"
    CHANGES_MADE=$((CHANGES_MADE + 1))
    return 0
  fi

  if mv "$src" "$dst" 2>/dev/null; then
    ok "Renamed: ${C_DIM}$src${C_RESET} -> ${C_DIM}$dst${C_RESET}"
    CHANGES_MADE=$((CHANGES_MADE + 1))
    return 0
  else
    error "Failed to rename: $src -> $dst"
    return 1
  fi
}

# Replace WT_ prefixed variable names with GROVE_ in a file
# This handles config variable names only, not arbitrary content
replace_wt_vars_in_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  # Check if file contains any WT_ references
  if ! grep -q 'WT_' "$file" 2>/dev/null; then
    dim "No WT_ references found in: $file"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    local count
    count="$(grep -c 'WT_' "$file" 2>/dev/null || echo 0)"
    dry "Would update $count WT_ reference(s) in: $file"
    CHANGES_MADE=$((CHANGES_MADE + 1))
    return 0
  fi

  # Back up before modifying
  backup_item "$file" || return 1

  # Replace WT_ variable prefixes with GROVE_
  # Handles: WT_SKIP_*, WT_HOOKS_DIR, WT_TEMPLATES_DIR, WT_CONFIG, WT_DB_*, etc.
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' \
      -e 's/WT_SKIP_/GROVE_SKIP_/g' \
      -e 's/WT_HOOKS_DIR/GROVE_HOOKS_DIR/g' \
      -e 's/WT_TEMPLATES_DIR/GROVE_TEMPLATES_DIR/g' \
      -e 's/WT_CONFIG_DIR/GROVE_CONFIG_DIR/g' \
      -e 's/WT_CONFIG/GROVE_CONFIG/g' \
      -e 's/WT_DB_HOST/GROVE_DB_HOST/g' \
      -e 's/WT_DB_USER/GROVE_DB_USER/g' \
      -e 's/WT_DB_PASSWORD/GROVE_DB_PASSWORD/g' \
      -e 's/WT_DB_CREATE/GROVE_DB_CREATE/g' \
      -e 's/WT_DB_BACKUP_DIR/GROVE_DB_BACKUP_DIR/g' \
      -e 's/WT_DB_BACKUP/GROVE_DB_BACKUP/g' \
      -e 's/WT_BASE_DEFAULT/GROVE_BASE_DEFAULT/g' \
      -e 's/WT_EDITOR/GROVE_EDITOR/g' \
      -e 's/WT_URL_SUBDOMAIN/GROVE_URL_SUBDOMAIN/g' \
      -e 's/WT_MAX_PARALLEL/GROVE_MAX_PARALLEL/g' \
      -e 's/WT_PROTECTED_BRANCHES/GROVE_PROTECTED_BRANCHES/g' \
      -e 's/WT_BRANCH_PATTERN/GROVE_BRANCH_PATTERN/g' \
      -e 's/WT_BRANCH_EXAMPLES/GROVE_BRANCH_EXAMPLES/g' \
      -e 's/WT_REPO_GROUPS/GROVE_REPO_GROUPS/g' \
      -e 's/WT_SHARED_DEPS_DIR/GROVE_SHARED_DEPS_DIR/g' \
      -e 's/WT_FETCH_CACHE_TTL/GROVE_FETCH_CACHE_TTL/g' \
      "$file"
  else
    sed -i \
      -e 's/WT_SKIP_/GROVE_SKIP_/g' \
      -e 's/WT_HOOKS_DIR/GROVE_HOOKS_DIR/g' \
      -e 's/WT_TEMPLATES_DIR/GROVE_TEMPLATES_DIR/g' \
      -e 's/WT_CONFIG_DIR/GROVE_CONFIG_DIR/g' \
      -e 's/WT_CONFIG/GROVE_CONFIG/g' \
      -e 's/WT_DB_HOST/GROVE_DB_HOST/g' \
      -e 's/WT_DB_USER/GROVE_DB_USER/g' \
      -e 's/WT_DB_PASSWORD/GROVE_DB_PASSWORD/g' \
      -e 's/WT_DB_CREATE/GROVE_DB_CREATE/g' \
      -e 's/WT_DB_BACKUP_DIR/GROVE_DB_BACKUP_DIR/g' \
      -e 's/WT_DB_BACKUP/GROVE_DB_BACKUP/g' \
      -e 's/WT_BASE_DEFAULT/GROVE_BASE_DEFAULT/g' \
      -e 's/WT_EDITOR/GROVE_EDITOR/g' \
      -e 's/WT_URL_SUBDOMAIN/GROVE_URL_SUBDOMAIN/g' \
      -e 's/WT_MAX_PARALLEL/GROVE_MAX_PARALLEL/g' \
      -e 's/WT_PROTECTED_BRANCHES/GROVE_PROTECTED_BRANCHES/g' \
      -e 's/WT_BRANCH_PATTERN/GROVE_BRANCH_PATTERN/g' \
      -e 's/WT_BRANCH_EXAMPLES/GROVE_BRANCH_EXAMPLES/g' \
      -e 's/WT_REPO_GROUPS/GROVE_REPO_GROUPS/g' \
      -e 's/WT_SHARED_DEPS_DIR/GROVE_SHARED_DEPS_DIR/g' \
      -e 's/WT_FETCH_CACHE_TTL/GROVE_FETCH_CACHE_TTL/g' \
      "$file"
  fi

  ok "Updated WT_ -> GROVE_ variable names in: ${C_DIM}$file${C_RESET}"
  CHANGES_MADE=$((CHANGES_MADE + 1))
}

# ============================================================================
# Migration steps
# ============================================================================

# Step 1: Migrate ~/.wtrc -> ~/.groverc
migrate_wtrc() {
  info "Checking global config file (~/.wtrc)..."

  if [[ -f "$HOME/.groverc" ]] && [[ ! -f "$HOME/.wtrc" ]]; then
    skip "Already migrated: ~/.groverc exists, ~/.wtrc does not"
    return 0
  fi

  if [[ ! -f "$HOME/.wtrc" ]]; then
    skip "No ~/.wtrc found -- nothing to migrate"
    return 0
  fi

  if [[ -f "$HOME/.groverc" ]]; then
    warn "Both ~/.wtrc and ~/.groverc exist. Skipping rename to avoid data loss."
    warn "Please merge these files manually, then remove ~/.wtrc"
    return 0
  fi

  # Back up and rename
  backup_item "$HOME/.wtrc" || return 1
  rename_item "$HOME/.wtrc" "$HOME/.groverc" || return 1

  # Update variable names inside the new file
  replace_wt_vars_in_file "$HOME/.groverc"
}

# Step 2: Migrate ~/.wt/ -> ~/.grove/
migrate_wt_dir() {
  info "Checking config directory (~/.wt/)..."

  if [[ -d "$HOME/.grove" ]] && [[ ! -d "$HOME/.wt" ]]; then
    skip "Already migrated: ~/.grove/ exists, ~/.wt/ does not"
    return 0
  fi

  if [[ ! -d "$HOME/.wt" ]]; then
    skip "No ~/.wt/ directory found -- nothing to migrate"
    return 0
  fi

  if [[ -d "$HOME/.grove" ]]; then
    warn "Both ~/.wt/ and ~/.grove/ exist. Skipping rename to avoid data loss."
    warn "Please merge these directories manually, then remove ~/.wt/"
    return 0
  fi

  # Back up and rename
  backup_item "$HOME/.wt" || return 1
  rename_item "$HOME/.wt" "$HOME/.grove" || return 1
}

# Step 3: Update template files in ~/.grove/templates/
migrate_templates() {
  local templates_dir="$HOME/.grove/templates"

  info "Checking template files in ${templates_dir}..."

  if [[ ! -d "$templates_dir" ]]; then
    skip "No templates directory found at $templates_dir"
    return 0
  fi

  local found_templates=false
  for conf_file in "$templates_dir"/*.conf; do
    [[ -f "$conf_file" ]] || continue
    found_templates=true

    if grep -q 'WT_SKIP_' "$conf_file" 2>/dev/null; then
      replace_wt_vars_in_file "$conf_file"
    else
      dim "No WT_SKIP_* references in: ${conf_file##*/}"
    fi
  done

  if [[ "$found_templates" == false ]]; then
    skip "No template .conf files found in $templates_dir"
  fi
}

# Step 4: Scan for per-repo .wtconfig files
migrate_repo_configs() {
  local herd_root="${HERD_ROOT:-$HOME/Herd}"

  info "Checking per-repo .wtconfig files in ${herd_root}..."

  if [[ ! -d "$herd_root" ]]; then
    skip "Herd root not found at $herd_root"
    return 0
  fi

  # Check the Herd root itself
  if [[ -f "$herd_root/.wtconfig" ]]; then
    if [[ -f "$herd_root/.groveconfig" ]]; then
      warn "Both .wtconfig and .groveconfig exist in $herd_root. Skipping to avoid data loss."
    else
      backup_item "$herd_root/.wtconfig" || true
      rename_item "$herd_root/.wtconfig" "$herd_root/.groveconfig" || true
      replace_wt_vars_in_file "$herd_root/.groveconfig"
    fi
  fi

  # Check inside each bare repo (*.git directories)
  for git_dir in "$herd_root"/*.git; do
    [[ -d "$git_dir" ]] || continue

    if [[ -f "$git_dir/.wtconfig" ]]; then
      local repo_name="${git_dir##*/}"
      repo_name="${repo_name%.git}"

      if [[ -f "$git_dir/.groveconfig" ]]; then
        warn "Both .wtconfig and .groveconfig exist in $git_dir. Skipping $repo_name to avoid data loss."
        continue
      fi

      info "Migrating .wtconfig for repository: ${C_BOLD}$repo_name${C_RESET}"
      backup_item "$git_dir/.wtconfig" || continue
      rename_item "$git_dir/.wtconfig" "$git_dir/.groveconfig" || continue
      replace_wt_vars_in_file "$git_dir/.groveconfig"
    fi
  done
}

# Step 5: Update git config keys (wt.base -> grove.base)
migrate_git_config() {
  local herd_root="${HERD_ROOT:-$HOME/Herd}"

  info "Checking git config keys (wt.base -> grove.base)..."

  if [[ ! -d "$herd_root" ]]; then
    skip "Herd root not found at $herd_root"
    return 0
  fi

  for git_dir in "$herd_root"/*.git; do
    [[ -d "$git_dir" ]] || continue

    local repo_name="${git_dir##*/}"
    repo_name="${repo_name%.git}"

    # List all worktrees for this repo
    local worktree_list
    worktree_list="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null || true)"

    if [[ -z "$worktree_list" ]]; then
      continue
    fi

    # Extract worktree paths
    local wt_path
    while IFS= read -r line; do
      if [[ "$line" == "worktree "* ]]; then
        wt_path="${line#worktree }"

        # Check if this worktree has wt.base configured
        local old_base
        old_base="$(git -C "$wt_path" config --local --get wt.base 2>/dev/null || true)"

        if [[ -n "$old_base" ]]; then
          if [[ "$DRY_RUN" == true ]]; then
            dry "Would migrate git config wt.base -> grove.base in: $wt_path (value: $old_base)"
            CHANGES_MADE=$((CHANGES_MADE + 1))
          else
            # Set the new key
            git -C "$wt_path" config --local grove.base "$old_base" 2>/dev/null || true
            # Remove the old key
            git -C "$wt_path" config --local --unset wt.base 2>/dev/null || true
            ok "Migrated git config wt.base -> grove.base in: ${C_DIM}$wt_path${C_RESET} (${old_base})"
            CHANGES_MADE=$((CHANGES_MADE + 1))
          fi
        fi
      fi
    done <<< "$worktree_list"
  done
}

# Step 6: Warn about custom hook scripts containing WT_ references
check_hook_scripts() {
  local hooks_dir="$HOME/.grove/hooks"

  # Fall back to old location if grove dir doesn't exist yet
  if [[ ! -d "$hooks_dir" ]]; then
    hooks_dir="$HOME/.wt/hooks"
  fi

  info "Checking hook scripts for WT_ references..."

  if [[ ! -d "$hooks_dir" ]]; then
    skip "No hooks directory found"
    return 0
  fi

  local found_refs=false

  # Find all executable files in hooks directory
  while IFS= read -r hook_file; do
    [[ -f "$hook_file" ]] || continue

    if grep -q 'WT_' "$hook_file" 2>/dev/null; then
      found_refs=true
      local ref_count
      ref_count="$(grep -c 'WT_' "$hook_file" 2>/dev/null || echo 0)"
      warn "Hook contains $ref_count WT_ reference(s): ${C_DIM}$hook_file${C_RESET}"

      # Show the specific references
      grep -n 'WT_' "$hook_file" 2>/dev/null | while IFS= read -r match; do
        dim "  $match"
      done
    fi
  done < <(find "$hooks_dir" -type f 2>/dev/null)

  if [[ "$found_refs" == true ]]; then
    echo ""
    warn "Hook scripts were ${C_BOLD}not${C_RESET} automatically modified."
    warn "Grove still exports WT_* variables for backward compatibility, but you"
    warn "should update your hooks to use GROVE_* variables when convenient."
    warn "  WT_REPO        -> GROVE_REPO"
    warn "  WT_BRANCH      -> GROVE_BRANCH"
    warn "  WT_BRANCH_SLUG -> GROVE_BRANCH_SLUG"
    warn "  WT_PATH        -> GROVE_PATH"
    warn "  WT_URL         -> GROVE_URL"
    warn "  WT_DB_NAME     -> GROVE_DB_NAME"
    warn "  WT_HOOK_NAME   -> GROVE_HOOK_NAME"
    warn "  WT_SKIP_*      -> GROVE_SKIP_*"
    echo ""
  else
    ok "No WT_ references found in hook scripts"
  fi
}

# Step 7: Check and update shell config files for WT_ references
migrate_shell_configs() {
  info "Checking shell configuration files for WT_ references..."

  local shell_files=(
    "$HOME/.zshrc"
    "$HOME/.zprofile"
    "$HOME/.zshenv"
    "$HOME/.zsh_exports"
    "$HOME/.zsh_aliases"
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.bash_exports"
    "$HOME/.profile"
  )

  local found_refs=false

  for shell_file in "${shell_files[@]}"; do
    [[ -f "$shell_file" ]] || continue

    if grep -q 'WT_' "$shell_file" 2>/dev/null; then
      found_refs=true
      local ref_count
      ref_count="$(grep -c 'WT_' "$shell_file" 2>/dev/null || echo 0)"

      if [[ "$DRY_RUN" == true ]]; then
        dry "Would update $ref_count WT_ reference(s) in: $shell_file"
        grep -n 'WT_' "$shell_file" 2>/dev/null | while IFS= read -r match; do
          dim "  $match"
        done
        CHANGES_MADE=$((CHANGES_MADE + 1))
      else
        info "Found $ref_count WT_ reference(s) in: ${C_BOLD}${shell_file##*/}${C_RESET}"
        grep -n 'WT_' "$shell_file" 2>/dev/null | while IFS= read -r match; do
          dim "  $match"
        done

        replace_wt_vars_in_file "$shell_file"
      fi
    fi
  done

  # Also check ~/.zsh/functions/ directory if it exists
  if [[ -d "$HOME/.zsh/functions" ]]; then
    while IFS= read -r func_file; do
      [[ -f "$func_file" ]] || continue

      if grep -q 'WT_' "$func_file" 2>/dev/null; then
        found_refs=true
        local ref_count
        ref_count="$(grep -c 'WT_' "$func_file" 2>/dev/null || echo 0)"

        if [[ "$DRY_RUN" == true ]]; then
          dry "Would update $ref_count WT_ reference(s) in: $func_file"
          CHANGES_MADE=$((CHANGES_MADE + 1))
        else
          info "Found $ref_count WT_ reference(s) in: ${C_BOLD}${func_file}${C_RESET}"
          replace_wt_vars_in_file "$func_file"
        fi
      fi
    done < <(find "$HOME/.zsh/functions" -type f -name "*.zsh" 2>/dev/null)
  fi

  if [[ "$found_refs" == false ]]; then
    ok "No WT_ references found in shell configuration files"
  fi
}

# Step 8: Create wt -> grove symlink
create_symlink() {
  if [[ "$NO_SYMLINK" == true ]]; then
    skip "Symlink creation skipped (--no-symlink)"
    return 0
  fi

  info "Checking wt -> grove command symlink..."

  # Find where grove is installed
  local grove_path
  grove_path="$(command -v grove 2>/dev/null || true)"

  if [[ -z "$grove_path" ]]; then
    warn "grove command not found in PATH. Skipping symlink creation."
    warn "Install grove first, then re-run this script to create the symlink."
    return 0
  fi

  local wt_path
  wt_path="$(command -v wt 2>/dev/null || true)"

  # Check if wt already points to grove (or is the same binary)
  if [[ -n "$wt_path" ]] && [[ -L "$wt_path" ]]; then
    local link_target
    link_target="$(readlink "$wt_path" 2>/dev/null || true)"
    if [[ "$link_target" == *"grove"* ]]; then
      skip "wt is already symlinked to grove: $wt_path -> $link_target"
      return 0
    fi
  fi

  # If wt exists and is not a symlink to grove, don't overwrite it
  if [[ -n "$wt_path" ]] && [[ ! -L "$wt_path" || "$(readlink "$wt_path" 2>/dev/null)" != *"grove"* ]]; then
    warn "Existing wt command found at: $wt_path"
    warn "Not overwriting. Remove it manually first if you want the symlink."
    return 0
  fi

  # Determine symlink location (same directory as grove)
  local grove_dir
  grove_dir="$(dirname "$grove_path")"
  local symlink_path="$grove_dir/wt"

  if [[ -e "$symlink_path" ]]; then
    skip "File already exists at $symlink_path"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    dry "Would create symlink: $symlink_path -> $grove_path"
    CHANGES_MADE=$((CHANGES_MADE + 1))
    return 0
  fi

  if ln -s "$grove_path" "$symlink_path" 2>/dev/null; then
    ok "Created symlink: ${C_DIM}$symlink_path${C_RESET} -> ${C_DIM}$grove_path${C_RESET}"
    ok "You can still use 'wt' as an alias for 'grove' during transition"
    CHANGES_MADE=$((CHANGES_MADE + 1))
  else
    warn "Could not create symlink at $symlink_path (permission denied?)"
    warn "You can create it manually: sudo ln -s $grove_path $symlink_path"
  fi
}

# ============================================================================
# Main
# ============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)    DRY_RUN=true ;;
      --no-symlink) NO_SYMLINK=true ;;
      --force)      FORCE=true ;;
      --help|-h)
        echo "Usage: $0 [--dry-run] [--no-symlink] [--force]"
        echo ""
        echo "Migrate existing wt configuration to grove."
        echo ""
        echo "Flags:"
        echo "  --dry-run      Show what would be done without making changes"
        echo "  --no-symlink   Skip creating wt -> grove symlink"
        echo "  --force        Don't prompt for confirmation"
        echo ""
        echo "This script is idempotent and safe to run multiple times."
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        echo "Run '$0 --help' for usage information."
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  echo ""
  echo "${C_BOLD}grove migration tool${C_RESET}"
  echo "${C_DIM}Migrate from wt to grove${C_RESET}"
  echo ""

  if [[ "$DRY_RUN" == true ]]; then
    echo "${C_CYAN}${C_BOLD}DRY RUN MODE${C_RESET} -- no changes will be made"
    echo ""
  fi

  # Pre-flight: check what exists
  local has_wtrc=false
  local has_wt_dir=false
  local has_wtconfig=false
  local herd_root="${HERD_ROOT:-$HOME/Herd}"

  [[ -f "$HOME/.wtrc" ]] && has_wtrc=true
  [[ -d "$HOME/.wt" ]] && has_wt_dir=true
  [[ -f "$herd_root/.wtconfig" ]] && has_wtconfig=true

  # Also check for per-repo .wtconfig files
  if [[ -d "$herd_root" ]]; then
    for git_dir in "$herd_root"/*.git; do
      [[ -d "$git_dir" ]] || continue
      [[ -f "$git_dir/.wtconfig" ]] && has_wtconfig=true
    done
  fi

  # If nothing to migrate, report and exit
  if [[ "$has_wtrc" == false ]] && [[ "$has_wt_dir" == false ]] && [[ "$has_wtconfig" == false ]]; then
    # Check if already migrated
    if [[ -f "$HOME/.groverc" ]] || [[ -d "$HOME/.grove" ]]; then
      ok "Already using grove configuration. Nothing to migrate."
    else
      ok "No wt configuration found. Nothing to migrate."
    fi
    echo ""

    # Still offer symlink creation
    create_symlink
    print_summary
    return 0
  fi

  # Show what was detected
  echo "${C_BOLD}Detected:${C_RESET}"
  [[ "$has_wtrc" == true ]]     && echo "  ${C_YELLOW}*${C_RESET} ~/.wtrc (global config)"
  [[ "$has_wt_dir" == true ]]   && echo "  ${C_YELLOW}*${C_RESET} ~/.wt/ (config directory with hooks, templates, etc.)"
  [[ "$has_wtconfig" == true ]] && echo "  ${C_YELLOW}*${C_RESET} Per-repo .wtconfig files"
  echo ""

  # Confirmation prompt
  if [[ "$FORCE" != true ]] && [[ "$DRY_RUN" != true ]]; then
    echo "${C_YELLOW}This will rename files and update variable names.${C_RESET}"
    echo "${C_DIM}All original files will be backed up with timestamps.${C_RESET}"
    echo ""
    read -rp "Proceed with migration? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo ""
      echo "Migration cancelled."
      exit 0
    fi
    echo ""
  fi

  # Run migration steps
  echo "${C_BOLD}Step 1/8:${C_RESET} Global config file"
  migrate_wtrc
  echo ""

  echo "${C_BOLD}Step 2/8:${C_RESET} Config directory"
  migrate_wt_dir
  echo ""

  echo "${C_BOLD}Step 3/8:${C_RESET} Template files"
  migrate_templates
  echo ""

  echo "${C_BOLD}Step 4/8:${C_RESET} Per-repo config files"
  migrate_repo_configs
  echo ""

  echo "${C_BOLD}Step 5/8:${C_RESET} Git config keys"
  migrate_git_config
  echo ""

  echo "${C_BOLD}Step 6/8:${C_RESET} Hook scripts (advisory)"
  check_hook_scripts

  echo "${C_BOLD}Step 7/8:${C_RESET} Shell configuration files"
  migrate_shell_configs
  echo ""

  echo "${C_BOLD}Step 8/8:${C_RESET} Command symlink"
  create_symlink
  echo ""

  print_summary
}

print_summary() {
  echo "${C_BOLD}========================================${C_RESET}"
  echo "${C_BOLD}Migration Summary${C_RESET}"
  echo "${C_BOLD}========================================${C_RESET}"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  Mode:     ${C_CYAN}Dry run (no changes made)${C_RESET}"
  fi

  echo "  Changes:  ${C_GREEN}$CHANGES_MADE${C_RESET}"
  echo "  Warnings: ${C_YELLOW}$WARNINGS_ISSUED${C_RESET}"
  echo "  Skipped:  ${C_DIM}$SKIPPED${C_RESET}"
  echo ""

  if [[ "$DRY_RUN" == true ]] && [[ "$CHANGES_MADE" -gt 0 ]]; then
    echo "${C_DIM}Run without --dry-run to apply these changes.${C_RESET}"
    echo ""
  fi

  if [[ "$CHANGES_MADE" -gt 0 ]] && [[ "$DRY_RUN" != true ]]; then
    ok "Migration complete. You can now use 'grove' instead of 'wt'."
    echo ""
  fi
}

main "$@"
