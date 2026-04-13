#!/usr/bin/env zsh
# laravel.sh - Laravel-specific commands

# cmd_migrate — Run Laravel database migrations for a worktree
cmd_migrate() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove migrate [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"
  [[ -f "$wt_path/artisan" ]] || error_exit "INVALID_INPUT" "not a Laravel project (no artisan file)" 2

  pushd "$wt_path" >/dev/null || error_exit "IO_ERROR" "failed to cd into '$wt_path'" 5
  php artisan migrate
  popd >/dev/null
}

# cmd_tinker — Open Laravel Tinker REPL for a worktree
cmd_tinker() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove tinker [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"
  [[ -f "$wt_path/artisan" ]] || error_exit "INVALID_INPUT" "not a Laravel project (no artisan file)" 2

  pushd "$wt_path" >/dev/null || error_exit "IO_ERROR" "failed to cd into '$wt_path'" 5
  php artisan tinker
  popd >/dev/null
}
