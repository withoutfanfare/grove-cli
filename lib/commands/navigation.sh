#!/usr/bin/env zsh
# navigation.sh - Navigation and editor commands

# cmd_code — Open a worktree in the configured editor
cmd_code() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to open")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove code [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"

  # Resolve @N shortcuts and fuzzy matching
  local original_branch="$branch"
  branch="$(resolve_branch_ref "$repo" "$branch")"
  if [[ "$branch" != "$original_branch" ]]; then
    dim "  Matched: $branch"
  fi

  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  local editor="$DEFAULT_EDITOR"

  # Detect available editor
  if ! command -v "$editor" >/dev/null 2>&1; then
    if command -v cursor >/dev/null 2>&1; then
      editor="cursor"
    elif command -v code >/dev/null 2>&1; then
      editor="code"
    else
      error_exit "IO_ERROR" "no editor found, install VS Code or Cursor, or set GROVE_EDITOR" 5
    fi
  fi

  info "Opening in ${C_BOLD}$editor${C_RESET}..."
  "$editor" "$wt_path"
}

# cmd_open — Open a worktree's URL in the default browser
cmd_open() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to open")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove open [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"

  # Resolve @N shortcuts and fuzzy matching
  local original_branch="$branch"
  branch="$(resolve_branch_ref "$repo" "$branch")"
  if [[ "$branch" != "$original_branch" ]]; then
    dim "  Matched: $branch"
  fi

  validate_name "$branch" "branch"

  # Get actual worktree path
  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # Read APP_URL from .env file, fall back to folder-based URL
  local url=""
  if [[ -f "$wt_path/.env" ]]; then
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*APP_URL= ]]; then
        url="${line#*=}"
        url="${url%%#*}"
        url="${url//[\"\' ]}"
        break
      fi
    done < "$wt_path/.env"
  fi

  # Fallback to folder-based URL if APP_URL not found
  if [[ -z "$url" ]]; then
    local folder="${wt_path:t}"
    url="https://${folder}.test"
    dim "  No APP_URL in .env, using: $url"
  fi

  command -v open >/dev/null 2>&1 || error_exit "IO_ERROR" "'open' command not found (macOS required)" 5
  open "$url"
}

# cmd_cd — Print worktree path for shell cd integration
cmd_cd() {
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

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove cd [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"

  # Resolve @N shortcuts and fuzzy matching
  local original_branch="$branch"
  branch="$(resolve_branch_ref "$repo" "$branch")"
  if [[ "$branch" != "$original_branch" ]]; then
    # Output match info to stderr so it doesn't interfere with path output
    print -r -- "  Matched: $branch" >&2
  fi

  validate_name "$branch" "branch"

  resolve_worktree_path "$repo" "$branch"
}

# cmd_switch — Switch to a worktree, opening editor and browser
cmd_switch() {
  local repo="${1:-}"; local branch="${2:-}"

  # Note: No auto-detect for switch - it's meant to switch TO a different worktree

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to switch to")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove switch <repo> [<branch>]" 2

  validate_name "$repo" "repository"

  # Resolve @N shortcuts and fuzzy matching
  local original_branch="$branch"
  branch="$(resolve_branch_ref "$repo" "$branch")"
  if [[ "$branch" != "$original_branch" ]]; then
    # Output match info to stderr so it doesn't interfere with path output
    print -r -- "  Matched: $branch" >&2
  fi

  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # Read APP_URL from .env file, fall back to folder-based URL
  local url=""
  if [[ -f "$wt_path/.env" ]]; then
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*APP_URL= ]]; then
        url="${line#*=}"
        url="${url%%#*}"
        url="${url//[\"\' ]}"
        break
      fi
    done < "$wt_path/.env"
  fi
  if [[ -z "$url" ]]; then
    url="$(url_for "$repo" "$branch")"
  fi

  # Print path for cd (user can use: cd "$(grove switch ...)")
  print -r -- "$wt_path"

  # Run post-switch hooks (updates -current symlink, restarts services, etc.)
  # Hook output goes to stderr so it doesn't interfere with path output for cd
  run_hooks "post-switch" "$repo" "$branch" "$wt_path" "$url" "" >&2

  # Open in editor (fully detached from subshell)
  local editor="$DEFAULT_EDITOR"
  if command -v "$editor" >/dev/null 2>&1; then
    (nohup "$editor" "$wt_path" >/dev/null 2>&1 &)
  fi

  # Open in browser (fully detached from subshell)
  if command -v open >/dev/null 2>&1; then
    (nohup open "$url" >/dev/null 2>&1 &)
  fi
}

# cmd_exec — Execute a command in a worktree directory
cmd_exec() {
  local repo="${1:-}"; local branch="${2:-}"
  shift 2 2>/dev/null || error_exit "INVALID_INPUT" "Usage: grove exec <repo> <branch> <command...>" 2
  local cmd=("$@")

  [[ -n "$repo" && -n "$branch" && ${#cmd[@]} -gt 0 ]] || error_exit "INVALID_INPUT" "Usage: grove exec <repo> <branch> <command...>" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path
  wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || error_exit "WORKTREE_NOT_FOUND" "worktree not found at '$wt_path'" 3

  pushd "$wt_path" >/dev/null || error_exit "IO_ERROR" "failed to cd into '$wt_path'" 5
  local cmd_exit=0
  "${cmd[@]}" || cmd_exit=$?
  popd >/dev/null
  return $cmd_exit
}
