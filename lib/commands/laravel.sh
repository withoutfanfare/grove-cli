#!/usr/bin/env zsh
# laravel.sh - Laravel-specific commands

# _run_artisan — Resolve a worktree and run an artisan subcommand within it.
#
# Arguments:
#   $1       - command name (used in usage hints, e.g. "migrate")
#   $2       - repository (optional; auto-detected when omitted)
#   $3       - branch (optional; auto-detected or selected via fzf)
#   $4...    - artisan subcommand and its arguments
#
# Propagates artisan's exit status to the caller so failures surface in CI.
_run_artisan() {
  local cmd_name="$1"; shift
  local repo="${1:-}"; local branch="${2:-}"; shift 2 2>/dev/null || true

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

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove $cmd_name [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"
  [[ -f "$wt_path/artisan" ]] || error_exit "INVALID_INPUT" "not a Laravel project (no artisan file)" 2

  # Ensure PHP is available before invoking artisan
  command -v php >/dev/null 2>&1 || error_exit "IO_ERROR" "'php' command not found - install PHP to run artisan commands" 5

  pushd "$wt_path" >/dev/null || error_exit "IO_ERROR" "failed to cd into '$wt_path'" 5
  php artisan "$@"
  local artisan_status=$?
  popd >/dev/null
  return "$artisan_status"
}

# cmd_migrate — Run Laravel database migrations for a worktree
cmd_migrate() {
  _run_artisan migrate "${1:-}" "${2:-}" migrate
}

# cmd_tinker — Open Laravel Tinker REPL for a worktree
cmd_tinker() {
  _run_artisan tinker "${1:-}" "${2:-}" tinker
}
