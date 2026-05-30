#!/usr/bin/env zsh
# 06-hooks.sh - Hook system for extensible worktree setup

# verify_hook_path_security — Check ownership and permissions of a hook file or directory
#
# Rejects paths not owned by the current user, and paths writable by group or
# other (the middle/last octal digit having a write bit). This prevents a
# co-located user or a loosely-permissioned directory from injecting code.
verify_hook_path_security() {
  # Note: avoid naming a local 'path' — it aliases zsh's $PATH array.
  local target="$1"
  local kind="$2"   # "Hook" or "Hook directory" - used for messaging
  local current_uid="${_GROVE_UID:-$(id -u)}"

  # Check ownership (macOS stat format, with Linux fallback)
  local owner; owner="$(stat -f %u "$target" 2>/dev/null || stat -c %u "$target" 2>/dev/null)"
  if [[ "$owner" != "$current_uid" ]]; then
    warn "$kind '$target' is not owned by current user - skipping for security"
    return 1
  fi

  # Check for group- or world-writable (macOS octal perms, with Linux fallback).
  # Octal write bit (2) is set when the digit is one of 2,3,6,7.
  local perms; perms="$(stat -f %Lp "$target" 2>/dev/null || stat -c %a "$target" 2>/dev/null)"
  # Normalise to a 3-digit owner/group/other string.
  perms="${perms: -3}"
  local group_digit="${perms:1:1}"
  local other_digit="${perms: -1}"
  if [[ "$group_digit" =~ [2367] ]]; then
    warn "$kind '$target' is group-writable - skipping for security"
    return 1
  fi
  if [[ "$other_digit" =~ [2367] ]]; then
    warn "$kind '$target' is world-writable - skipping for security"
    return 1
  fi

  return 0
}

# verify_hook_security — Check hook file ownership and permissions before execution
verify_hook_security() {
  verify_hook_path_security "$1" "Hook"
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

  # The subshell's exit status (and therefore this function's return value) is
  # the hook's own exit status, so callers can gate on pre-* hook failures.
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

    # Redirect stdin from /dev/null so hooks cannot deadlock by waiting on
    # input (e.g. during bulk or JSON flows).
    local hook_status=0
    "$hook_script" </dev/null || hook_status=$?

    if [[ $hook_status -eq 0 ]]; then
      ok "$display_label completed"
    else
      warn "$display_label exited with non-zero status"
    fi

    exit $hook_status
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

  # Glob qualifiers below need bare_glob_qual; no_nomatch keeps an empty .d
  # directory from raising a "no matches found" error; numeric_glob_sort makes
  # the default name sort numeric so 2 runs before 10 (not lexical 10 then 2).
  setopt local_options bare_glob_qual no_nomatch numeric_glob_sort

  # Generate branch slug for hooks that need it
  slugify_branch "$branch"
  local branch_slug="$REPLY"

  # pre-* phases are gating: any failing hook makes run_hooks return non-zero so
  # the lifecycle callers abort. post-* phases stay non-fatal (warn only).
  local is_gating=0
  [[ "$hook_name" == pre-* ]] && is_gating=1
  local overall_status=0

  # Check if hooks directory exists
  [[ -d "$GROVE_HOOKS_DIR" ]] || return 0

  local hook_file="$GROVE_HOOKS_DIR/$hook_name"

  # Check if hook exists and is owner-executable. Ownership is enforced by
  # verify_hook_security, so '-x' here matches the owner-execute 'x' glob
  # qualifier used for the .d/ scripts below.
  if [[ -x "$hook_file" ]]; then
    # Security check before executing
    if ! verify_hook_security "$hook_file"; then
      return 0
    fi

    info "Running ${C_CYAN}$hook_name${C_RESET} hook..."
    if ! _run_single_hook "$hook_file" "Hook ${C_CYAN}$hook_name${C_RESET}" \
      "$repo" "$branch" "$branch_slug" "$wt_path" "$app_url" "$db_name" "$hook_name"; then
      [[ $is_gating -eq 1 ]] && overall_status=1
    fi
  elif [[ -f "$hook_file" ]]; then
    dim "  Hook $hook_name exists but is not executable. Run: chmod +x $hook_file"
  fi

  # Also check for numbered hooks (post-add.d/*.sh pattern for multiple hooks)
  local hooks_d="$GROVE_HOOKS_DIR/${hook_name}.d"
  if [[ -d "$hooks_d" ]] && verify_hook_path_security "$hooks_d" "Hook directory"; then
    # Run global hooks (files only, not directories; follow symlinks).
    # numeric_glob_sort (set above) orders the default sort numerically.
    local hook_script script_name
    for hook_script in "$hooks_d"/*(N-.x); do
      # Security check before executing
      if ! verify_hook_security "$hook_script"; then
        continue
      fi

      script_name="${hook_script:t}"
      info "Running ${C_CYAN}$hook_name.d/$script_name${C_RESET}..."
      if ! _run_single_hook "$hook_script" "  $script_name" \
        "$repo" "$branch" "$branch_slug" "$wt_path" "$app_url" "$db_name" "$hook_name"; then
        [[ $is_gating -eq 1 ]] && overall_status=1
      fi
    done

    # Run repo-specific hooks (from subdirectory matching repo name; follow symlinks)
    local repo_hooks_d="$hooks_d/$repo"
    if [[ -d "$repo_hooks_d" ]] && verify_hook_path_security "$repo_hooks_d" "Hook directory"; then
      for hook_script in "$repo_hooks_d"/*(N-.x); do
        # Security check before executing
        if ! verify_hook_security "$hook_script"; then
          continue
        fi

        script_name="${hook_script:t}"
        info "Running ${C_CYAN}$hook_name.d/$repo/$script_name${C_RESET}..."
        if ! _run_single_hook "$hook_script" "  $repo/$script_name" \
          "$repo" "$branch" "$branch_slug" "$wt_path" "$app_url" "$db_name" "$hook_name"; then
          [[ $is_gating -eq 1 ]] && overall_status=1
        fi
      done
    fi
  fi

  return $overall_status
}
