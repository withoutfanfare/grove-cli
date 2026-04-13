#!/usr/bin/env zsh
# bulk-ops.sh - Bulk operations across multiple worktrees

# Check if a command string contains dangerous patterns and prompt for confirmation
#
# Arguments:
#   $1 - command string to check
#
# Returns:
#   0 if safe or user confirmed, exits via die if user aborts
_check_dangerous_command() {
  local cmd_str="$1"

  if [[ "$cmd_str" == *"rm -rf"* ]] || [[ "$cmd_str" == *"mkfs"* ]] || \
     [[ "$cmd_str" == *"dd "* ]] || [[ "$cmd_str" == *":()"* ]] || \
     [[ "$cmd_str" == *">/dev/"* ]] || [[ "$cmd_str" == *"shutdown"* ]] || \
     [[ "$cmd_str" == *"reboot"* ]] || [[ "$cmd_str" == *"init 0"* ]]; then
    warn "DANGEROUS COMMAND DETECTED: $cmd_str"
    print -r -- ""
    if ! confirm "This command could be destructive. Continue?"; then
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

  # Build operations list
  local operations=()
  for wt_entry in "${worktrees[@]}"; do
    local wt_path="${wt_entry%%|*}"
    local wt_branch="${wt_entry##*|}"
    if [[ -f "$wt_path/package.json" ]]; then
      operations+=("$wt_branch|cd '$wt_path' && npm run build")
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

  # Build operations list
  local operations=()
  for wt_entry in "${worktrees[@]}"; do
    local wt_path="${wt_entry%%|*}"
    local wt_branch="${wt_entry##*|}"
    operations+=("$wt_branch|cd '$wt_path' && $cmd_str")
  done

  parallel_run report_results "${operations[@]}"
}

# ============================================================================
# New commands: upgrade, info, recent, clean, alias
# ============================================================================


