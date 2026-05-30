#!/usr/bin/env zsh
# navigation.sh - Navigation and editor commands

# worktree_url — Resolve the development URL for a worktree.
#
# Reads APP_URL from the worktree's .env, cleaning the value the SAME way
# lib/01-core.sh cleans config values: strip surrounding matched quotes, and
# only for unquoted values strip a trailing " #..." comment (whitespace then #)
# — never a bare mid-value '#'. The .env is untrusted, so the value must match
# ^https?:// to be used. On a missing, empty, or non-http(s) APP_URL it falls
# back to url_for (which honours GROVE_URL_SUBDOMAIN).
#
# Arguments:
#   $1 - repo name
#   $2 - branch name
#   $3 - worktree path
#
# Output:
#   Prints the resolved URL to stdout
worktree_url() {
  local repo="$1" branch="$2" wt_path="$3"
  local url="" line value was_quoted

  if [[ -f "$wt_path/.env" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*APP_URL= ]]; then
        value="${line#*=}"
        # Clean the value like lib/01-core.sh _read_config_pairs does.
        was_quoted=false
        if [[ "$value" == \"*\" ]] || [[ "$value" == \'*\' ]]; then
          was_quoted=true
        fi
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        # Only strip a trailing " #..." comment on unquoted values — never a
        # bare mid-value '#', so URLs with a fragment survive intact.
        if [[ "$was_quoted" == false && "$value" == *[[:space:]]#* ]]; then
          value="${value%%[[:space:]]#*}"
        fi
        value="${value%"${value##*[![:space:]]}"}"
        url="$value"
        break
      fi
    done < "$wt_path/.env"
  fi

  # The .env value is untrusted: only use a well-formed http(s) URL.
  if [[ "$url" =~ ^https?:// ]]; then
    print -r -- "$url"
  else
    url_for "$repo" "$branch"
  fi
}

# resolve_repo_arg — Resolve a navigation repo argument, honouring aliases.
#
# If the argument names a real repository (a bare repo dir exists under
# HERD_ROOT) it is returned verbatim, preserving existing behaviour. Otherwise
# it is looked up as an alias via resolve_alias; on a hit the alias target's
# repo segment is returned. On no match the original argument is returned
# unchanged so downstream validation/lookup reports the usual error.
#
# Arguments:
#   $1 - repo name or alias
#
# Output:
#   Prints the resolved repo name to stdout
resolve_repo_arg() {
  local arg="$1" resolved

  # A real repo always wins — never shadow it with an alias of the same name.
  if [[ -d "$(git_dir_for "$arg")" ]]; then
    print -r -- "$arg"
    return 0
  fi

  if resolved="$(resolve_alias "$arg")"; then
    # Alias targets are stored as <repo/branch>; take the repo segment.
    print -r -- "${resolved%%/*}"
    return 0
  fi

  print -r -- "$arg"
}

# cmd_code — Open a worktree in the configured editor
cmd_code() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Resolve an alias to its repo before validation/lookup (real repos pass through)
  [[ -n "$repo" ]] && repo="$(resolve_repo_arg "$repo")"

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

  # Resolve an alias to its repo before validation/lookup (real repos pass through)
  [[ -n "$repo" ]] && repo="$(resolve_repo_arg "$repo")"

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

  # Resolve the URL (shared with switch): .env APP_URL when valid, else url_for
  local url; url="$(worktree_url "$repo" "$branch" "$wt_path")"

  # Prefer macOS `open`, fall back to Linux `xdg-open`.
  if command -v open >/dev/null 2>&1; then
    open "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url"
  else
    error_exit "IO_ERROR" "no URL opener found (need 'open' on macOS or 'xdg-open' on Linux)" 5
  fi
}

# cmd_cd — Print worktree path for shell cd integration
cmd_cd() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Resolve an alias to its repo before validation/lookup (real repos pass through)
  [[ -n "$repo" ]] && repo="$(resolve_repo_arg "$repo")"

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

  # Resolve an alias to its repo before validation/lookup (real repos pass through)
  [[ -n "$repo" ]] && repo="$(resolve_repo_arg "$repo")"

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

  # Resolve the URL (shared with open): .env APP_URL when valid, else url_for
  local url; url="$(worktree_url "$repo" "$branch" "$wt_path")"

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
  # Prefer macOS `open`, fall back to Linux `xdg-open`.
  if command -v open >/dev/null 2>&1; then
    (nohup open "$url" >/dev/null 2>&1 &)
  elif command -v xdg-open >/dev/null 2>&1; then
    (nohup xdg-open "$url" >/dev/null 2>&1 &)
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
