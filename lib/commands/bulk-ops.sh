#!/usr/bin/env zsh
# bulk-ops.sh - Bulk operations across multiple worktrees

# Check if a command string matches a few well-known destructive patterns and,
# if so, ask for confirmation before running it across every worktree.
#
# This is a courtesy guard, not a security boundary — it only spots a handful of
# obvious patterns and is easily bypassed. Treat it as a typo-catcher.
#
# Arguments:
#   $1 - command string to check
#
# Returns:
#   0 if no pattern matched or the user confirmed; exits if the user aborts
_check_dangerous_command() {
  local cmd_str="$1"

  if [[ "$cmd_str" == *"rm -rf"* ]] || [[ "$cmd_str" == *"mkfs"* ]] || \
     [[ "$cmd_str" =~ '(^|[[:space:];|&])dd([[:space:]]|$)' ]] || [[ "$cmd_str" == *":()"* ]] || \
     [[ "$cmd_str" =~ '>[[:space:]]*/dev/(disk|rdisk|sd|nvme|mmcblk|vd|xvd|md|mapper/|dm-)' ]] || [[ "$cmd_str" == *"shutdown"* ]] || \
     [[ "$cmd_str" == *"reboot"* ]] || [[ "$cmd_str" == *"init 0"* ]]; then
    warn "This looks like it could be destructive: $cmd_str"
    print -r -- ""
    if ! confirm "Run this across every worktree?"; then
      error_exit "INVALID_INPUT" "aborted by user" 2
    fi
    print -r -- ""
  fi
}

# cmd_build_all — Run npm build across all worktrees in parallel
cmd_build_all() {
  local repo="${1:-}"

  # Multi-repo mode
  if [[ "${ALL_REPOS:-false}" == true ]]; then
    info "Building all worktrees across all repositories..."
    print -r -- ""

    for git_dir in "$HERD_ROOT"/*.git(N); do
      [[ -d "$git_dir" ]] || continue
      local repo_name="${${git_dir:t}%.git}"
      print -r -- "${C_BOLD}${C_CYAN}$repo_name${C_RESET}"
      _build_all_for_repo "$repo_name" "$git_dir"
      print -r -- ""
    done

    ok "Build complete across all repositories"
    notify "grove build-all" "Completed across all repos"
    return 0
  fi

  # Group mode: @name expands to the repos configured via `grove group`
  if [[ "$repo" == @* ]]; then
    local group_name="${repo#@}"
    local resolved
    if ! resolved="$(resolve_group "$group_name")"; then
      error_exit "INVALID_INPUT" "group not found: '@$group_name' (see: grove group list)" 2
    fi

    info "Building all worktrees across group @$group_name..."
    print -r -- ""

    local repo_name git_dir
    for repo_name in ${=resolved}; do
      validate_name "$repo_name" "repository"
      git_dir="$(git_dir_for "$repo_name")"
      ensure_bare_repo "$git_dir"
      print -r -- "${C_BOLD}${C_CYAN}$repo_name${C_RESET}"
      _build_all_for_repo "$repo_name" "$git_dir"
      print -r -- ""
    done

    ok "Build complete across group @$group_name"
    notify "grove build-all" "Completed across group @$group_name"
    return 0
  fi

  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove build-all <repo>
       Use --all-repos to build across all repositories." 2

  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  _build_all_for_repo "$repo" "$git_dir"
  notify "grove build-all" "Completed for $repo"
}

_build_all_for_repo() {
  local repo="$1"
  local git_dir="$2"

  # Collect worktrees
  local worktrees=()
  collect_worktrees "$git_dir" worktrees

  (( ${#worktrees[@]} > 0 )) || { dim "  No worktrees found."; return 0; }

  # Build operations list in "label|path|command" form. parallel_run's fixed
  # wrapper performs the cd into the path (passed as argv, not interpolated), so
  # we never build a `cd '$path' && ...` string ourselves — see lib/09-parallel.sh.
  local operations=()
  local wt_path wt_branch
  for wt_entry in "${worktrees[@]}"; do
    wt_path="${wt_entry%%|*}"
    wt_branch="${wt_entry##*|}"
    if [[ -f "$wt_path/package.json" ]]; then
      operations+=("$wt_branch|$wt_path|npm run build")
    fi
  done

  if (( ${#operations[@]} > 0 )); then
    parallel_run report_results "${operations[@]}"
  else
    dim "  No worktrees with package.json"
  fi
}


# cmd_exec_all — Execute a command across all worktrees in parallel
cmd_exec_all() {
  local repo="${1:-}"

  # Multi-repo mode
  if [[ "${ALL_REPOS:-false}" == true ]]; then
    shift || true
    local cmd=("$@")
    (( ${#cmd[@]} > 0 )) || error_exit "INVALID_INPUT" "Usage: grove exec-all --all-repos <command...>" 2

    local cmd_str="${cmd[*]}"
    _check_dangerous_command "$cmd_str"

    info "Executing '$cmd_str' across all repositories..."
    print -r -- ""

    for git_dir in "$HERD_ROOT"/*.git(N); do
      [[ -d "$git_dir" ]] || continue
      local repo_name="${${git_dir:t}%.git}"
      print -r -- "${C_BOLD}${C_CYAN}$repo_name${C_RESET}"
      _exec_all_for_repo "$repo_name" "$git_dir" "$cmd_str"
      print -r -- ""
    done

    ok "Execution complete across all repositories"
    return 0
  fi

  shift || true
  local cmd=("$@")

  # Group mode: @name expands to the repos configured via `grove group`
  if [[ "$repo" == @* ]]; then
    (( ${#cmd[@]} > 0 )) || error_exit "INVALID_INPUT" "Usage: grove exec-all @<group> <command...>" 2

    local group_name="${repo#@}"
    local resolved
    if ! resolved="$(resolve_group "$group_name")"; then
      error_exit "INVALID_INPUT" "group not found: '@$group_name' (see: grove group list)" 2
    fi

    local cmd_str="${cmd[*]}"
    _check_dangerous_command "$cmd_str"

    info "Executing '$cmd_str' across group @$group_name..."
    print -r -- ""

    local repo_name git_dir
    for repo_name in ${=resolved}; do
      validate_name "$repo_name" "repository"
      git_dir="$(git_dir_for "$repo_name")"
      ensure_bare_repo "$git_dir"
      print -r -- "${C_BOLD}${C_CYAN}$repo_name${C_RESET}"
      _exec_all_for_repo "$repo_name" "$git_dir" "$cmd_str"
      print -r -- ""
    done

    ok "Execution complete across group @$group_name"
    return 0
  fi

  [[ -n "$repo" && ${#cmd[@]} -gt 0 ]] || error_exit "INVALID_INPUT" "Usage: grove exec-all <repo> <command...>
       Use --all-repos to execute across all repositories." 2

  validate_name "$repo" "repository"

  local cmd_str="${cmd[*]}"
  _check_dangerous_command "$cmd_str"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  _exec_all_for_repo "$repo" "$git_dir" "$cmd_str"
}

_exec_all_for_repo() {
  local repo="$1"
  local git_dir="$2"
  local cmd_str="$3"

  # Collect worktrees
  local worktrees=()
  collect_worktrees "$git_dir" worktrees

  (( ${#worktrees[@]} > 0 )) || { dim "  No worktrees found."; return 0; }

  # Build operations list in "label|path|command" form. parallel_run's fixed
  # wrapper cds into the path (passed as argv) and runs the command, so the user
  # command is passed verbatim as the command field — see lib/09-parallel.sh.
  local operations=()
  local wt_path wt_branch
  for wt_entry in "${worktrees[@]}"; do
    wt_path="${wt_entry%%|*}"
    wt_branch="${wt_entry##*|}"
    operations+=("$wt_branch|$wt_path|$cmd_str")
  done

  parallel_run report_results "${operations[@]}"
}

# ============================================================================
# New commands: upgrade, info, recent, clean, alias
# ============================================================================

