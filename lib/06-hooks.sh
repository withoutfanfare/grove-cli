#!/usr/bin/env zsh
# 06-hooks.sh - Hook system for extensible worktree setup

# verify_hook_security — Check hook ownership and permissions before execution
verify_hook_security() {
  local hook_file="$1"
  local current_uid="${_GROVE_UID:-$(id -u)}"

  # Check ownership (macOS stat format, with Linux fallback)
  local file_owner; file_owner="$(stat -f %u "$hook_file" 2>/dev/null || stat -c %u "$hook_file" 2>/dev/null)"
  if [[ "$file_owner" != "$current_uid" ]]; then
    warn "Hook '$hook_file' is not owned by current user - skipping for security"
    return 1
  fi

  # Check for world-writable (macOS octal perms, with Linux fallback)
  local file_perms; file_perms="$(stat -f %Lp "$hook_file" 2>/dev/null || stat -c %a "$hook_file" 2>/dev/null)"
  if [[ "${file_perms: -1}" =~ [2367] ]]; then
    warn "Hook '$hook_file' is world-writable - skipping for security"
    return 1
  fi

  return 0
}

# Execute a single hook script in a subshell with the standard environment
#
# Arguments:
#   $1 - hook script path
#   $2 - display label (e.g. "post-add" or "post-add.d/01-setup.sh")
#   $3 - repo name
#   $4 - branch name
#   $5 - branch slug
#   $6 - worktree path
#   $7 - app URL
#   $8 - database name
#   $9 - hook event name
_run_single_hook() {
  local hook_script="$1"
  local display_label="$2"
  local repo="$3"
  local branch="$4"
  local branch_slug="$5"
  local wt_path="$6"
  local app_url="$7"
  local db_name="$8"
  local hook_name="$9"

  (
    export GROVE_REPO="$repo"
    export GROVE_BRANCH="$branch"
    export GROVE_BRANCH_SLUG="$branch_slug"
    export GROVE_PATH="$wt_path"
    export GROVE_URL="$app_url"
    export GROVE_DB_NAME="$db_name"
    export GROVE_HOOK_NAME="$hook_name"
    # Control flags for hooks
    [[ "$NO_BACKUP" == true ]] && export GROVE_NO_BACKUP="true"
    [[ "$DROP_DB" == true ]] && export GROVE_DROP_DB="true"

    # Run hook from the worktree directory
    cd "$wt_path" 2>/dev/null || cd "$HOME"

    if "$hook_script"; then
      ok "$display_label completed"
    else
      warn "$display_label exited with non-zero status"
    fi
  )
}

# run_hooks — Execute lifecycle hooks (global, numbered, and repo-specific) for an event
run_hooks() {
  local hook_name="$1"
  local repo="$2"
  local branch="$3"
  local wt_path="$4"
  local app_url="$5"
  local db_name="$6"

  # Generate branch slug for hooks that need it
  slugify_branch "$branch"
  local branch_slug="$REPLY"

  # Check if hooks directory exists
  [[ -d "$GROVE_HOOKS_DIR" ]] || return 0

  local hook_file="$GROVE_HOOKS_DIR/$hook_name"

  # Check if hook exists and is executable
  if [[ -x "$hook_file" ]]; then
    # Security check before executing
    if ! verify_hook_security "$hook_file"; then
      return 0
    fi

    info "Running ${C_CYAN}$hook_name${C_RESET} hook..."
    _run_single_hook "$hook_file" "Hook ${C_CYAN}$hook_name${C_RESET}" \
      "$repo" "$branch" "$branch_slug" "$wt_path" "$app_url" "$db_name" "$hook_name"
  elif [[ -f "$hook_file" ]]; then
    dim "  Hook $hook_name exists but is not executable. Run: chmod +x $hook_file"
  fi

  # Also check for numbered hooks (post-add.d/*.sh pattern for multiple hooks)
  local hooks_d="$GROVE_HOOKS_DIR/${hook_name}.d"
  if [[ -d "$hooks_d" ]]; then
    # Run global hooks (files only, not directories; follow symlinks)
    local hook_script script_name
    for hook_script in "$hooks_d"/*(N-.x); do
      # Security check before executing
      if ! verify_hook_security "$hook_script"; then
        continue
      fi

      script_name="${hook_script:t}"
      info "Running ${C_CYAN}$hook_name.d/$script_name${C_RESET}..."
      _run_single_hook "$hook_script" "  $script_name" \
        "$repo" "$branch" "$branch_slug" "$wt_path" "$app_url" "$db_name" "$hook_name"
    done

    # Run repo-specific hooks (from subdirectory matching repo name; follow symlinks)
    local repo_hooks_d="$hooks_d/$repo"
    if [[ -d "$repo_hooks_d" ]]; then
      for hook_script in "$repo_hooks_d"/*(N-.x); do
        # Security check before executing
        if ! verify_hook_security "$hook_script"; then
          continue
        fi

        script_name="${hook_script:t}"
        info "Running ${C_CYAN}$hook_name.d/$repo/$script_name${C_RESET}..."
        _run_single_hook "$hook_script" "  $repo/$script_name" \
          "$repo" "$branch" "$branch_slug" "$wt_path" "$app_url" "$db_name" "$hook_name"
      done
    fi
  fi

  return 0
}
