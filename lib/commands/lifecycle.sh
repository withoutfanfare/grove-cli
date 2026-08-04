#!/usr/bin/env zsh
# lifecycle.sh - Worktree creation and removal commands

# _update_env_app_url — Rewrite ONLY the APP_URL= line in a .env file, preserving every
# other line. Uses a line-anchored loop (NOT a whole-file glob, which would greedily match
# across newlines and delete everything after APP_URL=). Writes via a temp file, then copies
# the new contents back into the ORIGINAL file in place — so the .env's original permissions,
# ownership and any symlink target are preserved (a plain `mv` would replace the file and drop
# all of that).
# Args: $1 = path to .env file, $2 = new URL. Returns 0 if APP_URL was found and updated.
_update_env_app_url() {
  local env_file="$1" new_url="$2"
  [[ -f "$env_file" ]] || return 1

  local line found=false
  local tmp="${env_file}.grove.tmp"
  : > "$tmp" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == APP_URL=* ]]; then
      print -r -- "APP_URL=$new_url" >> "$tmp"
      found=true
    else
      print -r -- "$line" >> "$tmp"
    fi
  done < "$env_file"

  if [[ "$found" == true ]]; then
    # Copy contents back into the original file (preserves mode, owner, symlink),
    # rather than mv'ing the temp over it (which would inherit the temp's perms
    # and break a symlinked .env).
    if cat "$tmp" > "$env_file"; then
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  return 1
}

# ── Transaction undo helpers ──────────────────────────────────────────────
# Each is a DEFINED function (required by transaction_register, which rejects
# anything that isn't a real function and calls it with no eval). They are
# deliberately tolerant: rollback runs best-effort, so a missing target is fine.

# _undo_worktree_add — Remove a worktree that was created mid-operation.
# Args: $1 = git_dir, $2 = worktree path.
_undo_worktree_add() {
  local git_dir="$1" wt_path="$2"
  [[ -n "$wt_path" ]] || return 0
  if [[ -d "$wt_path" ]]; then
    git --git-dir="$git_dir" worktree remove --force "$wt_path" 2>/dev/null || /bin/rm -rf "$wt_path" 2>/dev/null
  fi
  git --git-dir="$git_dir" worktree prune 2>/dev/null || true
}

# _undo_herd_site — Retire a Herd site that was secured mid-operation.
# Args: $1 = site name (e.g. the worktree directory basename).
_undo_herd_site() {
  local site_name="$1"
  [[ -n "$site_name" ]] || return 0
  if command -v herd >/dev/null 2>&1; then
    herd unsecure "$site_name" >/dev/null 2>&1 || true
  fi
  cleanup_herd_site "$site_name" 2>/dev/null || true
}

# _undo_clone — Remove a bare repo directory created by cmd_clone.
# Args: $1 = git_dir (bare repo path).
_undo_clone() {
  local git_dir="$1"
  [[ -n "$git_dir" && -d "$git_dir" ]] || return 0
  /bin/rm -rf "$git_dir" 2>/dev/null || true
}

# _undo_worktree_move — Move a worktree back to its original path on rollback.
# Args: $1 = git_dir, $2 = current (new) path, $3 = original path.
_undo_worktree_move() {
  local git_dir="$1" current="$2" original="$3"
  [[ -n "$current" && -n "$original" ]] || return 0
  [[ -d "$current" ]] || return 0
  git --git-dir="$git_dir" worktree move --force "$current" "$original" 2>/dev/null || true
}

# cmd_add — Create a new worktree for a branch, optionally from a base ref
cmd_add() {
  local repo="${1:-}"; local branch="${2:-}"; local base_arg="${3:-}"; local base="$base_arg"
  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove add <repo> <branch> [base]" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  # Validate branch name against configured pattern (if set)
  validate_branch_pattern "$branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Load repo-specific config (may override DEFAULT_BASE)
  load_repo_config "$git_dir"

  # Load template if specified (sets GROVE_SKIP_* environment variables)
  if [[ -n "$GROVE_TEMPLATE" ]]; then
    load_template "$GROVE_TEMPLATE"
  fi

  # Use provided base or default
  [[ -z "$base" ]] && base="$DEFAULT_BASE"

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  # Strip origin/ prefix if user accidentally included it (do this early for accurate paths)
  if [[ "$branch" == origin/* ]]; then
    branch="${branch#origin/}"
    warn "Note: 'origin/' prefix will be stripped from branch name"
  fi

  # The folder / URL / DB derive from the branch name, UNLESS --dir/--as gives a
  # custom name. That lets an existing long-named branch (e.g. user/very-long-…)
  # live in a short folder so the Herd '.test' domain stays within the SSL cap,
  # while the checked-out git branch is still the real branch.
  local derive_name="$branch"
  if [[ -n "$GROVE_DIR" ]]; then
    slugify_branch "$GROVE_DIR"
    if [[ -z "$REPLY" ]]; then
      error_exit "INVALID_INPUT" "--dir/--as value '$GROVE_DIR' slugifies to empty" 2
    fi
    derive_name="$REPLY"
  fi

  local wt_path; wt_path="$(worktree_path_for "$repo" "$derive_name")"
  local app_url; app_url="$(url_for "$repo" "$derive_name")"
  local db_name; db_name="$(db_name_for "$repo" "$derive_name")"

  if [[ -n "$GROVE_DIR" ]]; then
    dim "Using custom worktree dir: ${wt_path:t} (branch: $branch)"
  else
    # Check if site name was shortened for SSL compatibility
    slugify_branch "$branch"
    local full_slug="$REPLY"
    local full_site_name="${repo}--${full_slug}"
    local actual_site_name="${wt_path:t}"
    if [[ "$full_site_name" != "$actual_site_name" ]]; then
      dim "Site name shortened for SSL compatibility"
      dim "  Full: $full_site_name (${#full_site_name} chars)"
      dim "  Used: $actual_site_name (${#actual_site_name} chars)"
    fi
  fi

  # Dry-run mode - show what would happen without executing
  if [[ "$DRY_RUN" == true ]]; then
    print -r -- ""
    print -r -- "${C_BOLD}Dry Run Preview${C_RESET}"
    print -r -- ""
    print -r -- "${C_BOLD}Worktree Details:${C_RESET}"
    print -r -- "  Repository:  ${C_CYAN}$repo${C_RESET}"
    print -r -- "  Branch:      ${C_MAGENTA}$branch${C_RESET}"
    print -r -- "  Base:        ${C_DIM}$base${C_RESET}"
    print -r -- "  Path:        $wt_path"
    print -r -- "  URL:         ${C_CYAN}$app_url${C_RESET}"
    print -r -- "  Database:    ${C_CYAN}$db_name${C_RESET}"
    print -r -- ""
    if [[ -n "$GROVE_TEMPLATE" ]]; then
      print -r -- "${C_BOLD}Template:${C_RESET} $GROVE_TEMPLATE"
      print -r -- "  ${C_DIM}GROVE_SKIP_DB${C_RESET}=${GROVE_SKIP_DB:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_COMPOSER${C_RESET}=${GROVE_SKIP_COMPOSER:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_NPM${C_RESET}=${GROVE_SKIP_NPM:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_BUILD${C_RESET}=${GROVE_SKIP_BUILD:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_MIGRATE${C_RESET}=${GROVE_SKIP_MIGRATE:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_HERD${C_RESET}=${GROVE_SKIP_HERD:-false}"
      print -r -- ""
    fi
    print -r -- "${C_BOLD}Actions:${C_RESET}"
    print -r -- "  1. Fetch latest branches from remote"
    # Match the real add: an existing branch (local OR remote) is checked out
    # with tracking and is NOT pushed. Only a genuinely new branch is created
    # from base and pushed. Checking the remote here (not just refs/heads) keeps
    # the preview honest for remote-only branches.
    if git --git-dir="$git_dir" show-ref --quiet "refs/heads/$branch" 2>/dev/null; then
      print -r -- "  2. Create worktree from existing local branch: $branch"
    elif remote_branch_exists "$git_dir" "$branch"; then
      print -r -- "  2. Create worktree from existing remote branch: origin/$branch (tracking, no push)"
    else
      print -r -- "  2. Create new branch '$branch' from '$base'"
      print -r -- "  3. Push branch to remote and set up tracking"
    fi
    print -r -- "  4. Run pre-add hooks"
    print -r -- "  5. Run post-add hooks (environment setup)"
    print -r -- ""
    print -r -- "${C_DIM}Run without --dry-run to execute${C_RESET}"
    return 0
  fi

  # Ensure we can fetch all branches (fix corrupted refspecs)
  ensure_fetch_refspec "$git_dir"

  info "Fetching latest branches from remote..."
  with_retry 3 git --git-dir="$git_dir" fetch --all --prune --quiet || \
    error_exit "GIT_ERROR" "failed to fetch from remote after 3 attempts" 4

  # If base is a remote ref (origin/...), explicitly fetch it to ensure we have the latest
  if [[ "$base" == origin/* ]]; then
    local remote_branch="${base#origin/}"
    dim "  Fetching latest: $remote_branch"
    git --git-dir="$git_dir" fetch origin "$remote_branch:refs/remotes/origin/$remote_branch" --force 2>/dev/null || true
  fi

  # Check if branch exists on remote (using ls-remote for accuracy)
  local branch_on_remote=false
  local branch_local=false

  if git --git-dir="$git_dir" show-ref --quiet "refs/heads/$branch"; then
    branch_local=true
  fi

  if remote_branch_exists "$git_dir" "$branch"; then
    branch_on_remote=true
    # Fetch it to local tracking branch
    if [[ "$branch_local" == false ]]; then
      info "Found branch on remote: ${C_MAGENTA}$branch${C_RESET}"
      dim "  Fetching to local..."
      git --git-dir="$git_dir" fetch origin "$branch:$branch" 2>/dev/null || \
        git --git-dir="$git_dir" fetch origin "$branch:refs/remotes/origin/$branch" 2>/dev/null || true
      # Recheck local
      if git --git-dir="$git_dir" show-ref --quiet "refs/heads/$branch"; then
        branch_local=true
      fi
    fi
  fi

  [[ ! -d "$wt_path" ]] || error_exit "WORKTREE_EXISTS" "worktree already exists at '$wt_path'" 4

  # If branch doesn't exist anywhere, warn the user before creating
  if [[ "$branch_local" == false && "$branch_on_remote" == false ]]; then
    # Verify base branch exists
    if ! git --git-dir="$git_dir" rev-parse --verify "$base" >/dev/null 2>&1; then
      error_exit "BRANCH_NOT_FOUND" "base branch '$base' not found, run: git --git-dir=\"$git_dir\" branch -a" 3
    fi

    warn "Branch ${C_MAGENTA}$branch${C_RESET} does not exist locally or on remote"
    print -r -- ""
    print -r -- "  ${C_BOLD}This will CREATE a new branch${C_RESET} from ${C_DIM}$base${C_RESET}"
    print -r -- ""

    # In non-interactive mode, show how to check out existing branches
    if [[ "$INTERACTIVE" != true && "$FORCE" != true ]]; then
      print -r -- "  ${C_DIM}If you meant to check out an existing branch:${C_RESET}"
      print -r -- "    1. Check available branches: git --git-dir=\"$git_dir\" branch -r"
      print -r -- "    2. Ensure the branch has been pushed to origin"
      print -r -- "    3. Use the exact branch name without 'origin/' prefix"
      print -r -- ""
      print -r -- "  ${C_DIM}To create the new branch anyway, run with --force${C_RESET}"
      error_exit "BRANCH_NOT_FOUND" "aborted: use --force to create new branch, or check the branch name" 3
    fi
  fi

  # Run pre-add hooks (can abort by returning non-zero)
  if ! run_hooks "pre-add" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"; then
    error_exit "HOOK_FAILED" "pre-add hook failed, aborting" 5
  fi

  # Begin a transaction: every side effect below registers an undo step so a
  # mid-operation failure (or Ctrl-C) rolls the worktree back cleanly. The
  # module-level TRAPEXIT runs the registered steps in reverse if the shell
  # exits while the transaction is still active (e.g. via error_exit/die).
  transaction_start

  # Ensure there's room for the new worktree before creating it. The parent of
  # wt_path is the per-repo worktrees container (created by git as needed); fall
  # back to its parent if it doesn't exist yet so df has a real path to inspect.
  local wt_parent_dir="${wt_path:h}"
  [[ -d "$wt_parent_dir" ]] || wt_parent_dir="${wt_parent_dir:h}"
  check_disk_space "$wt_parent_dir"

  local created_from_base=false
  if [[ "$branch_local" == true ]]; then
    info "Creating worktree from existing branch: ${C_MAGENTA}$branch${C_RESET}"
    git --git-dir="$git_dir" worktree add "$wt_path" "$branch" >&2
  elif [[ "$branch_on_remote" == true ]]; then
    # Branch exists on remote but fetch to local failed - try worktree add with remote tracking
    info "Creating worktree tracking remote branch: ${C_MAGENTA}origin/$branch${C_RESET}"
    git --git-dir="$git_dir" worktree add --track -b "$branch" "$wt_path" "origin/$branch" >&2
  else
    created_from_base=true
    info "Creating NEW branch ${C_MAGENTA}$branch${C_RESET} from ${C_DIM}$base${C_RESET}"
    git --git-dir="$git_dir" worktree add --no-track -b "$branch" "$wt_path" "$base" >&2
  fi
  # Worktree now exists on disk — register its removal (and any Herd site set up
  # by post-add hooks) so a later failure tears down the partial state.
  transaction_register _undo_herd_site "${wt_path:t}"
  transaction_register _undo_worktree_add "$git_dir" "$wt_path"

  # Ensure config.worktree exists when bare repo uses extensions.worktreeConfig
  ensure_worktree_config "$git_dir" "$wt_path"

  # Set up remote tracking (only push if creating new branch)
  if [[ "$branch_on_remote" == true ]]; then
    # Branch already exists on remote, just set up tracking
    dim "  Branch already exists on remote - setting up tracking"
    /usr/bin/git -C "$wt_path" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null 2>&1 || true
  else
    # New branch - push to remote
    info "Pushing new branch to remote..."
    if GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git -C "$wt_path" push -u origin "$branch:$branch" 2>/dev/null; then
      ok "Remote branch created and tracking set"
    else
      dim "  Push failed (may need to push manually later): git push -u origin $branch"
    fi
  fi

  # Store the base ref this worktree should compare against (for summary/diff/sync defaults).
  # Only do this when we definitely created from a base, or when the user explicitly provided a base.
  if [[ "$created_from_base" == true || -n "$base_arg" ]]; then
    set_worktree_base "$wt_path" "$base"
  fi

  # Success - commit the transaction so the registered undo steps do NOT run.
  # Done before post-add hooks: those are non-fatal environment setup, so a hook
  # failure must not tear down the (now valid) worktree.
  transaction_commit

  # Run post-add hooks
  # Register before the post-add hooks so a hook can already resume the ledger.
  # Best effort: a failure here never undoes a successful add.
  ledger_register "$wt_path"

  run_hooks "post-add" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"

  # Restart Herd services to pick up new site
  restart_herd_service

  if [[ "$JSON_OUTPUT" == true ]]; then
    json_escape "$wt_path"; local _je_path="$REPLY"
    json_escape "$app_url"; local _je_url="$REPLY"
    json_escape "$branch"; local _je_branch="$REPLY"
    json_escape "$db_name"; local _je_db="$REPLY"
    print -r -- "{\"path\": \"$_je_path\", \"url\": \"$_je_url\", \"branch\": \"$_je_branch\", \"database\": \"$_je_db\"}"
  else
    print -r -- ""
    ok "${C_BOLD}Worktree ready${C_RESET}"
    print -r -- "   ${C_DIM}Path${C_RESET}  $wt_path"
    print -r -- "   ${C_DIM}URL${C_RESET}   ${C_CYAN}$app_url${C_RESET}"
    print -r -- "   ${C_DIM}DB${C_RESET}    ${C_CYAN}$db_name${C_RESET}"
    print -r -- ""
  fi
}

# cmd_rm — Remove a worktree and optionally delete its branch
cmd_rm() {
  local repo="${1:-}"; local branch="${2:-}"

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to remove")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove rm [-f] [--delete-branch] <repo> <branch>" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  local app_url; app_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"
  local site_name="${wt_path:t}"

  ensure_bare_repo "$git_dir"
  [[ -d "$wt_path" ]] || error_exit "WORKTREE_NOT_FOUND" "worktree not found at '$wt_path'" 3

  # Branch protection check
  if is_protected_branch "$branch" && [[ "$FORCE" == false ]]; then
    error_exit "PROTECTED_BRANCH" "branch '$branch' is protected, use -f to force removal" 4
  fi

  # Worktree Ledger gate. Deliberately BEFORE the pre-rm hooks and before git
  # touches anything, and deliberately not conditioned on $FORCE: -f forces git,
  # it does not accept the loss of work nobody has recorded. The only way past
  # this is a one-use token from `way worktree removal-check --acknowledge`,
  # supplied as --ledger-ack.
  if ! ledger_check_removal "$wt_path" "$LEDGER_ACK"; then
    error_exit "LEDGER_BLOCKED" "removal blocked by the worktree ledger (see above). To proceed, run 'way worktree removal-check --acknowledge' in the worktree and pass the token with --ledger-ack" 6
  fi

  # Check for uncommitted changes and confirm (unless --force)
  if [[ "$FORCE" == false ]]; then
    local wt_status; wt_status="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || wt_status=""
    if [[ -n "$wt_status" ]]; then
      local changes; changes="$(count_lines "$wt_status")"
      warn "Worktree has ${C_BOLD}$changes${C_RESET}${C_YELLOW} uncommitted change(s):${C_RESET}"
      git -C "$wt_path" status --short
      print -n "${C_YELLOW}Continue with removal? [y/N]${C_RESET} "
      local response
      read -r response
      [[ "$response" =~ ^[Yy]$ ]] || error_exit "INVALID_INPUT" "aborted by user" 2
    fi
  fi

  # Run pre-rm hooks
  if ! run_hooks "pre-rm" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"; then
    error_exit "HOOK_FAILED" "pre-rm hook failed, aborting" 5
  fi

  info "Removing worktree ${C_CYAN}$wt_path${C_RESET}"
  local remove_output remove_status
  if [[ "$FORCE" == true ]]; then
    # Capture status with '|| remove_status=$?' so a failing command substitution
    # does not abort the script under 'set -e' (a plain assignment would).
    remove_status=0
    remove_output="$(git --git-dir="$git_dir" worktree remove --force "$wt_path" 2>&1)" || remove_status=$?
    # A worktree locked by another tool (e.g. Supacode) refuses a single --force.
    # With -f the user has asked to remove it regardless, so unlock and retry.
    if (( remove_status != 0 )) && [[ "$remove_output" == *"locked working tree"* ]]; then
      warn "Worktree is locked - unlocking and retrying..."
      git --git-dir="$git_dir" worktree unlock "$wt_path" 2>/dev/null || true
      remove_status=0
      remove_output="$(git --git-dir="$git_dir" worktree remove --force "$wt_path" 2>&1)" || remove_status=$?
    fi
    if (( remove_status != 0 )); then
      # Handle "Directory not empty" caused by untracked files left in the worktree directory
      if [[ "$remove_output" == *"Directory not empty"* && -d "$wt_path" ]]; then
        warn "Directory contains untracked files - cleaning up..."
        if ! rm -rf "$wt_path"; then
          error_exit "IO_ERROR" "failed to clean up worktree directory at '$wt_path'" 5
        fi
        if [[ -d "$wt_path" ]]; then
          error_exit "IO_ERROR" "cleanup failed, worktree directory still exists at '$wt_path'" 5
        fi
        # Prune git worktree metadata now that the directory has been removed
        git --git-dir="$git_dir" worktree prune 2>/dev/null || warn "Failed to prune git worktree metadata"
      else
        error_exit "GIT_ERROR" "failed to remove worktree: $remove_output" 4
      fi
    fi
  else
    remove_output="$(git --git-dir="$git_dir" worktree remove "$wt_path" 2>&1)" || {
      if [[ "$remove_output" == *"Directory not empty"* && -d "$wt_path" ]]; then
        warn "Directory contains untracked files - use -f to force removal"
        error_exit "GIT_ERROR" "worktree directory not empty" 4
      else
        error_exit "GIT_ERROR" "failed to remove worktree: $remove_output" 4
      fi
    }
  fi

  # Delete branch if requested. Capture the REAL outcome (not the request flag)
  # so the JSON contract reports what actually happened — a swallowed failure
  # would otherwise desync the consuming app's branch list.
  local branch_deleted=false
  if [[ "$DELETE_BRANCH" == true ]]; then
    info "Deleting branch ${C_MAGENTA}$branch${C_RESET}"
    if git --git-dir="$git_dir" branch -D "$branch" >&2; then
      branch_deleted=true
    else
      warn "Could not delete branch (may not exist locally)"
    fi
  fi

  info "Pruning stale worktrees..."
  git --git-dir="$git_dir" worktree prune

  # Run post-rm hooks
  run_hooks "post-rm" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"

  # Restart Herd services to clean up removed site
  restart_herd_service

  if [[ "$JSON_OUTPUT" == true ]]; then
    json_escape "$repo"; local _je_repo="$REPLY"
    json_escape "$branch"; local _je_branch="$REPLY"
    json_escape "$wt_path"; local _je_path="$REPLY"
    # branch_deleted = the REAL deletion outcome. db_drop_requested = the request
    # intent only: the DB drop is delegated to hooks (grove can't confirm it ran),
    # so we report what was asked for, not a result we cannot verify.
    local _je_branch_deleted; _je_branch_deleted="$(to_json_bool "$branch_deleted")"
    local _je_db_requested; _je_db_requested="$(to_json_bool "$DROP_DB")"
    format_json "{\"success\": true, \"repo\": \"$_je_repo\", \"branch\": \"$_je_branch\", \"path\": \"$_je_path\", \"branch_deleted\": $_je_branch_deleted, \"db_drop_requested\": $_je_db_requested}"
  else
    ok "Worktree removed"
    print -r -- ""
  fi
}

# cmd_move — Move a worktree to a new directory name
cmd_move() {
  local repo="${1:-}"; local branch="${2:-}"; local new_name="${3:-}"

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to move")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove move <repo> <branch> <new-name>" 2

  # Prompt for new name if not provided
  if [[ -z "$new_name" ]]; then
    print -n "${C_CYAN}New directory name: ${C_RESET}"
    read -r new_name
    [[ -n "$new_name" ]] || error_exit "INVALID_INPUT" "new directory name is required" 2
  fi

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  # Validate new name with the full whitelist (charset, leading/trailing dots, traversal,
  # flag injection) — consistent with repo/branch validation elsewhere.
  validate_name "$new_name" "directory name"
  # Additional check: directory names must not contain slashes
  if [[ "$new_name" == */* ]]; then
    error_exit "INVALID_INPUT" "invalid directory name '$new_name', slashes not allowed" 2
  fi

  local git_dir; git_dir="$(git_dir_for "$repo")"
  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  local wt_parent="${wt_path:h}"
  local old_site_name="${wt_path:t}"
  local new_wt_path="$wt_parent/$new_name"
  local new_site_name="$new_name"

  # Get old URL and database name for hooks
  local old_url; old_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"

  ensure_bare_repo "$git_dir"
  [[ -d "$wt_path" ]] || error_exit "WORKTREE_NOT_FOUND" "worktree not found at '$wt_path'" 3
  [[ ! -d "$new_wt_path" ]] || error_exit "WORKTREE_EXISTS" "destination already exists: '$new_wt_path'" 4

  # Check if old site is secured
  local was_secured=false
  if command -v herd >/dev/null 2>&1; then
    if herd secured 2>/dev/null | grep -q "^| ${old_site_name}.test "; then
      was_secured=true
    fi
  fi

  info "Moving worktree:"
  print -r -- "  ${C_DIM}From:${C_RESET} ${C_CYAN}$wt_path${C_RESET}"
  print -r -- "  ${C_DIM}To:${C_RESET}   ${C_CYAN}$new_wt_path${C_RESET}"

  # Confirm unless --force
  if [[ "$FORCE" == false ]]; then
    print -n "${C_YELLOW}Continue? [y/N]${C_RESET} "
    local response
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || error_exit "INVALID_INPUT" "aborted by user" 2
  fi

  # Run pre-move hooks (with old path, URL, and db_name)
  if ! run_hooks "pre-move" "$repo" "$branch" "$wt_path" "$old_url" "$db_name"; then
    error_exit "HOOK_FAILED" "pre-move hook failed, aborting" 5
  fi

  # Begin a transaction so a failure after the move (securing the new site,
  # rewriting .env) rolls the worktree back to its original path.
  transaction_start

  # Move the worktree FIRST — before tearing down the old Herd site — so that a move
  # failure leaves the old site intact rather than unsecured with no worktree to serve.
  info "Moving worktree..."
  if [[ "$FORCE" == true ]]; then
    git --git-dir="$git_dir" worktree move --force "$wt_path" "$new_wt_path"
  else
    git --git-dir="$git_dir" worktree move "$wt_path" "$new_wt_path"
  fi

  # Assert the new path actually landed before we tear down the old Herd site.
  # If it isn't there, the move silently no-op'd — aborting now (rollback runs)
  # avoids unsecuring a site whose worktree never moved.
  [[ -d "$new_wt_path" ]] || error_exit "IO_ERROR" "worktree move did not produce '$new_wt_path'" 5
  transaction_register _undo_worktree_move "$git_dir" "$new_wt_path" "$wt_path"

  # Move succeeded — now retire the old Herd site (unsecure + clean nginx/certificates)
  if [[ "$was_secured" == true ]]; then
    info "Unsecuring old site ${C_CYAN}${old_site_name}.test${C_RESET}"
    herd unsecure "$old_site_name" >/dev/null 2>&1 || true
  fi
  if command -v herd >/dev/null 2>&1; then
    cleanup_herd_site "$old_site_name"
  fi

  # Re-secure new site if old was secured
  if [[ "$was_secured" == true ]]; then
    info "Securing new site ${C_CYAN}${new_site_name}.test${C_RESET}"
    if ! herd secure "$new_site_name" >/dev/null 2>&1; then
      warn "Could not secure new site - you may need to run: herd secure $new_site_name"
    else
      ok "Site secured"
      # Registered after the move undo so rollback unsecures the new site first.
      transaction_register _undo_herd_site "$new_site_name"
    fi
  fi

  # Calculate new URL (based on new directory name, not repo--branch pattern)
  local new_url="https://${new_site_name}.test"
  if [[ -n "$GROVE_URL_SUBDOMAIN" ]]; then
    new_url="https://${GROVE_URL_SUBDOMAIN}.${new_site_name}.test"
  fi

  # Update APP_URL in .env if it exists (line-anchored — preserves all other keys)
  if _update_env_app_url "$new_wt_path/.env" "$new_url"; then
    dim "  Updated APP_URL in .env"
  fi

  # Everything reversible has succeeded — commit so the registered undo steps do
  # NOT run. Done before the non-fatal post-move hooks.
  transaction_commit

  # Run post-move hooks (with new path, URL, and db_name)
  # The worktree id is unchanged; only its observed path moves.
  ledger_moved "$new_wt_path"

  run_hooks "post-move" "$repo" "$branch" "$new_wt_path" "$new_url" "$db_name"

  print -r -- ""
  ok "Worktree moved successfully"
  print -r -- ""
  print -r -- "  ${C_DIM}Path:${C_RESET} ${C_CYAN}$new_wt_path${C_RESET}"
  print -r -- "  ${C_DIM}URL:${C_RESET}  ${C_CYAN}$new_url${C_RESET}"
  print -r -- ""
}

# cmd_clone — Clone a repository as a bare repo and optionally create an initial worktree
cmd_clone() {
  local url="${1:-}"; local repo="${2:-}"; local initial_branch="${3:-}"
  [[ -n "$url" ]] || error_exit "INVALID_INPUT" "Usage: grove clone <url> [repo-name] [branch]" 2

  # Extract repo name from URL if not provided
  if [[ -z "$repo" ]]; then
    repo="${url##*/}"
    repo="${repo%.git}"
  fi

  validate_name "$repo" "repository"
  [[ -z "$initial_branch" ]] || validate_name "$initial_branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"

  [[ ! -d "$git_dir" ]] || error_exit "REPO_EXISTS" "bare repo already exists at '$git_dir'" 3

  # For JSON output, capture errors and output structured response
  if [[ "$JSON_OUTPUT" == true ]]; then
    local clone_output clone_exit=0
    clone_output=$(GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git clone --bare "$url" "$git_dir" 2>&1) || clone_exit=$?

    if [[ $clone_exit -ne 0 ]]; then
      json_escape "$repo"; local _je_repo="$REPLY"
      json_escape "$git_dir"; local _je_dir="$REPLY"
      json_escape "$clone_output"; local _je_msg="$REPLY"
      print -r -- "{\"success\": false, \"repo\": \"$_je_repo\", \"path\": \"$_je_dir\", \"message\": \"$_je_msg\"}"
      return 1
    fi

    # Configure fetch to get all branches
    /usr/bin/git --git-dir="$git_dir" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    # Fetch all branches (ignore errors for JSON - already cloned)
    GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git --git-dir="$git_dir" fetch --all --prune 2>/dev/null || true

    json_escape "$repo"; local _je_repo2="$REPLY"
    json_escape "$git_dir"; local _je_dir2="$REPLY"
    print -r -- "{\"success\": true, \"repo\": \"$_je_repo2\", \"path\": \"$_je_dir2\", \"message\": \"Repository cloned successfully\"}"
    return 0
  fi

  # Non-JSON output (original behaviour)
  # Begin a transaction so a failed fetch rolls back the half-created bare repo.
  # We commit BEFORE handing off to cmd_add (which runs its own worktree
  # transaction): once the bare repo + branches exist it is a durable artifact,
  # and cmd_add's commit would otherwise clear our registered undo step anyway.
  transaction_start

  info "Cloning ${C_CYAN}$url${C_RESET} as bare repo..."
  GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git clone --bare "$url" "$git_dir"
  transaction_register _undo_clone "$git_dir"

  # Configure fetch to get all branches
  /usr/bin/git --git-dir="$git_dir" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

  info "Fetching all branches..."
  with_retry 3 env GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git --git-dir="$git_dir" fetch --all --prune || \
    error_exit "GIT_ERROR" "failed to fetch branches after 3 attempts" 4

  # Bare repo is complete — commit so the clone survives even if a later
  # worktree creation (cmd_add, with its own transaction) is aborted.
  transaction_commit

  print -r -- ""
  ok "Bare repo created at ${C_CYAN}$git_dir${C_RESET}"

  # If specific branch requested, create worktree for it
  if [[ -n "$initial_branch" ]]; then
    print -r -- ""
    if /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/$initial_branch"; then
      info "Creating worktree for ${C_GREEN}$initial_branch${C_RESET}..."
      cmd_add "$repo" "$initial_branch" "origin/$initial_branch"
    else
      # Prefer the configured DEFAULT_BASE (normalised to origin/<name>), then
      # fall back to the conventional staging → main → master ladder.
      local base_branch=""
      local default_base_name="${DEFAULT_BASE#origin/}"
      if [[ -n "$default_base_name" ]] && /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/$default_base_name" 2>/dev/null; then
        base_branch="origin/$default_base_name"
      elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/staging"; then
        base_branch="origin/staging"
      elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/main"; then
        base_branch="origin/main"
      elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/master"; then
        base_branch="origin/master"
      else
        error_exit "BRANCH_NOT_FOUND" "branch '$initial_branch' not found on remote and no default base branch available" 3
      fi
      info "Creating new branch ${C_GREEN}$initial_branch${C_RESET} from $base_branch..."
      cmd_add "$repo" "$initial_branch" "$base_branch"
    fi
  elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/staging"; then
    print -r -- ""
    info "Found staging branch - creating worktree..."
    cmd_add "$repo" "staging" "origin/staging"
  elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/main"; then
    print -r -- ""
    info "Found main branch - creating worktree..."
    cmd_add "$repo" "main" "origin/main"
  elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/master"; then
    print -r -- ""
    info "Found master branch - creating worktree..."
    cmd_add "$repo" "master" "origin/master"
  else
    dim "  Create a worktree with: grove add $repo <branch>"
    print -r -- ""
  fi

  notify "grove clone" "Repository $repo cloned successfully"
}

# cmd_fresh — Refresh a worktree by running migrate:fresh, npm ci, and build
cmd_fresh() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
    dim "  Detected: $repo / $branch"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to refresh")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove fresh [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  pushd "$wt_path" >/dev/null || error_exit "IO_ERROR" "failed to cd into '$wt_path'" 5
  # Restore the directory stack on ANY exit from this function (zsh runs a
  # function-local EXIT trap on return), so we never leave the caller stranded
  # in the worktree if an early return or unexpected error fires below.
  trap 'popd >/dev/null 2>&1 || true' EXIT

  print -r -- ""
  print -r -- "${C_BOLD}Refreshing ${C_CYAN}$repo${C_RESET} / ${C_MAGENTA}$branch${C_RESET}"
  print -r -- ""

  # Run migrate:fresh --seed (with confirmation unless forced)
  if [[ -f "artisan" ]]; then
    if [[ "$FORCE" == false ]]; then
      warn "This will DROP ALL TABLES in the database!"
      print -n "${C_YELLOW}Continue with migrate:fresh? [y/N]${C_RESET} "
      local response
      read -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        warn "Skipping migrate:fresh"
        return 0
      fi
    fi

    info "Running migrate:fresh --seed..."
    if php artisan migrate:fresh --seed; then
      ok "Database refreshed"
    else
      warn "migrate:fresh --seed failed"
    fi
  fi

  # Run npm ci
  if [[ -f "package.json" ]]; then
    info "Running npm ci..."
    if npm ci; then
      ok "npm dependencies installed"
    else
      warn "npm ci failed"
    fi

    info "Running npm run build..."
    if npm run build; then
      ok "Assets built"
    else
      warn "npm run build failed"
    fi
  fi

  # popd handled by the EXIT trap installed above.
  notify "grove fresh" "Completed for $repo / $branch"
  print -r -- ""
  ok "Fresh complete!"
  print -r -- ""
}

# _restructure_migrate_one — Migrate a SINGLE worktree from the old flat layout
# (HERD_ROOT/repo--branch) to the nested layout (HERD_ROOT/repo-worktrees/site).
#
# Extracted so the main porcelain loop AND the trailing last-entry block share
# ONE implementation — previously the last entry did only the git move, leaving
# its Herd SSL and .env APP_URL stale depending on a trailing blank line.
#
# Args: $1 = git_dir, $2 = repo, $3 = new_container, $4 = wt_path, $5 = branch
# Returns: 0 = migrated, 2 = skipped (already migrated / not old layout),
#          1 = attempted but failed or destination exists (count as neither).
_restructure_migrate_one() {
  local git_dir="$1" repo="$2" new_container="$3" wt_path="$4" branch="$5"
  local folder="${wt_path:t}"
  local parent="${wt_path:h}"
  local parent_name="${parent:t}"

  # Skip if already in new structure
  if [[ "$parent_name" == "${repo}-worktrees" ]]; then
    dim "  Already migrated: $branch → $folder"
    return 2
  fi

  # Only migrate worktrees in the old structure (at HERD_ROOT with repo-- prefix)
  if [[ "$parent" != "$HERD_ROOT" || "$folder" != "${repo}--"* ]]; then
    dim "  Skipping: $branch (not in old structure)"
    return 2
  fi

  local new_site_name; new_site_name="$(site_name_for "$repo" "$branch")"
  local new_path="$new_container/$new_site_name"

  if [[ -d "$new_path" ]]; then
    warn "Cannot migrate $branch: destination already exists at $new_path"
    return 1
  fi

  info "Migrating: ${C_MAGENTA}$branch${C_RESET}"
  dim "  From: $wt_path"
  dim "  To:   $new_path"

  # Use git worktree move (capture stderr so failures are surfaced, not hidden)
  local move_err
  if ! move_err="$(git --git-dir="$git_dir" worktree move "$wt_path" "$new_path" 2>&1)"; then
    warn "  Failed to migrate: ${move_err:-unknown error}"
    dim "  Try manually: git --git-dir=\"$git_dir\" worktree move \"$wt_path\" \"$new_path\""
    return 1
  fi
  ok "  Migrated successfully"

  # Update Herd site (unsecure old, secure new) and rewrite APP_URL in .env
  if command -v herd >/dev/null 2>&1; then
    herd unsecure "$folder" 2>/dev/null || true
    herd secure "$new_site_name" 2>/dev/null || true
    dim "  Updated Herd SSL for $new_site_name"

    # Update APP_URL in .env if it exists (line-anchored — preserves all other keys)
    local new_url="https://${new_site_name}.test"
    if _update_env_app_url "$new_path/.env" "$new_url"; then
      dim "  Updated APP_URL in .env"
    fi
  fi

  return 0
}

# cmd_restructure — Migrate worktrees from flat layout to nested directory structure
cmd_restructure() {
  local repo="${1:-}"

  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove restructure <repo> - Migrates all worktrees from old structure (repo--branch) to new structure (repo-worktrees/feature-name)" 2

  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Confirm before a bulk, multi-worktree operation that moves directories and rewrites
  # each worktree's APP_URL in .env (gated by --force / non-interactive fails safe).
  if ! confirm "Restructure all old-layout worktrees for '$repo'? This moves directories and updates APP_URL in each .env."; then
    die "Restructure aborted"
  fi

  # Create the new worktrees container if it doesn't exist
  local new_container="$HERD_ROOT/${repo}-worktrees"
  if [[ ! -d "$new_container" ]]; then
    info "Creating worktrees container: ${C_CYAN}$new_container${C_RESET}"
    mkdir -p "$new_container"
  fi

  # Get all worktrees for this repo
  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || error_exit "GIT_ERROR" "failed to list worktrees" 4

  local wt_path="" branch=""
  local -i migrated=0 skipped=0
  local line="" migrate_rc=0
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      if [[ -n "$wt_path" && -n "$branch" && "$wt_path" != *.git ]]; then
        # One shared per-worktree migration path (move + Herd SSL + .env APP_URL).
        migrate_rc=0
        _restructure_migrate_one "$git_dir" "$repo" "$new_container" "$wt_path" "$branch" || migrate_rc=$?
        case "$migrate_rc" in
          0) migrated+=1 ;;
          2) skipped+=1 ;;
        esac
      fi
      wt_path=""
      branch=""
      continue
    fi
    [[ "$line" == worktree\ * ]] && wt_path="${line#worktree }"
    [[ "$line" == branch\ refs/heads/* ]] && branch="${line#branch refs/heads/}"
  done <<< "$out"

  # Handle last entry (no trailing blank line) via the SAME helper, so the final
  # worktree also gets its Herd SSL refreshed and .env APP_URL rewritten.
  if [[ -n "$wt_path" && -n "$branch" && "$wt_path" != *.git ]]; then
    migrate_rc=0
    _restructure_migrate_one "$git_dir" "$repo" "$new_container" "$wt_path" "$branch" || migrate_rc=$?
    case "$migrate_rc" in
      0) migrated+=1 ;;
      2) skipped+=1 ;;
    esac
  fi

  print -r -- ""
  ok "Migration complete: ${C_GREEN}$migrated${C_RESET} migrated, ${C_DIM}$skipped${C_RESET} skipped"
  print -r -- ""
}
