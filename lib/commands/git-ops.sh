#!/usr/bin/env zsh
# git-ops.sh - Git operation commands

# cmd_pull — Pull latest changes for a single worktree with rebase
cmd_pull() {
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
    branch="$(select_branch_fzf "$repo" "Select worktree to pull")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove pull [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"

  ensure_bare_repo "$git_dir"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # Capture pull output and exit code for JSON support
  local pull_output pull_exit_code=0
  [[ "$JSON_OUTPUT" != true ]] && info "Pulling latest changes in ${C_MAGENTA}$branch${C_RESET}..."
  pull_output="$(GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git -C "$wt_path" pull --rebase 2>&1)" || pull_exit_code=$?

  if [[ "$JSON_OUTPUT" == true ]]; then
    local already_up_to_date=false conflicts=false commits_pulled=0

    if [[ "$pull_output" == *"Already up to date"* ]]; then
      already_up_to_date=true
    elif (( pull_exit_code != 0 )) && [[ "$pull_output" == *"CONFLICT"* ]]; then
      conflicts=true
    fi

    # Extract commit count from "Updating abc123..def456" in pull output
    if [[ "$pull_output" =~ Updating\ ([a-f0-9]+)\.\.([a-f0-9]+) ]]; then
      local from_sha="${match[1]}"
      local to_sha="${match[2]}"
      commits_pulled="$(git -C "$wt_path" rev-list --count "$from_sha".."$to_sha" 2>/dev/null)" || commits_pulled=0
    fi

    local success_bool; [[ $pull_exit_code -eq 0 ]] && success_bool="true" || success_bool="false"
    json_escape "$pull_output"; local _je_msg="$REPLY"
    format_json "{\"success\": $success_bool, \"already_up_to_date\": $already_up_to_date, \"conflicts\": $conflicts, \"commits_pulled\": $commits_pulled, \"message\": \"$_je_msg\"}"

    # Run post-pull hooks even for JSON output (only on success)
    if (( pull_exit_code == 0 )); then
      local app_url; app_url="$(url_for "$repo" "$branch")"
      local db_name; db_name="$(db_name_for "$repo" "$branch")"
      run_hooks "post-pull" "$repo" "$branch" "$wt_path" "$app_url" "$db_name" >/dev/null 2>&1
    fi
    return $pull_exit_code
  fi

  # Text output mode
  if (( pull_exit_code != 0 )); then
    print -r -- "$pull_output"
    error_exit "GIT_ERROR" "pull failed" 4
  fi
  print -r -- "$pull_output"
  ok "Pull complete"

  # Run post-pull hooks
  local app_url; app_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"
  run_hooks "post-pull" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"
}

# cmd_pull_all — Pull latest changes for all worktrees in a repository in parallel
cmd_pull_all() {
  local repo="${1:-}"

  # Multi-repo mode (not supported with JSON)
  if [[ "${ALL_REPOS:-false}" == true || -z "$repo" ]]; then
    [[ "$JSON_OUTPUT" == true ]] && error_exit "INVALID_INPUT" "JSON output not supported with --all-repos" 2

    if [[ "${ALL_REPOS:-false}" == true ]]; then
      info "Pulling all worktrees across all repositories..."
      print -r -- ""
    else
      [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove pull-all <repo> - Use --all-repos to pull across all repositories." 2
    fi

    local total_success=0 total_failed=0
    for git_dir in "$HERD_ROOT"/*.git(N); do
      [[ -d "$git_dir" ]] || continue
      local repo_name="${${git_dir:t}%.git}"
      print -r -- "${C_BOLD}${C_CYAN}$repo_name${C_RESET}"
      _pull_all_for_repo "$repo_name" "$git_dir"
      print -r -- ""
    done

    ok "Pull complete across all repositories"
    return 0
  fi

  validate_name "$repo" "repository"

  local git_dir
  git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  _pull_all_for_repo "$repo" "$git_dir"
}

_pull_all_for_repo() {
  local repo="$1"
  local git_dir="$2"

  [[ "$JSON_OUTPUT" != true ]] && dim "  Fetching latest..."
  git --git-dir="$git_dir" fetch --all --prune --quiet 2>/dev/null || true

  # Collect worktrees using shared helper
  local worktrees=()
  collect_worktrees "$git_dir" worktrees

  if (( ${#worktrees[@]} == 0 )); then
    if [[ "$JSON_OUTPUT" == true ]]; then
      json_escape "$repo"; local _je_repo="$REPLY"
      format_json "{\"repo\":\"$_je_repo\",\"worktrees\":[],\"summary\":{\"total\":0,\"succeeded\":0,\"failed\":0,\"up_to_date\":0}}"
      return 0
    fi
    dim "No worktrees found."
    return 0
  fi

  # Pull each worktree in parallel
  local total=${#worktrees[@]}
  local count=0 failed=0 up_to_date=0
  export GIT_SSH_COMMAND="/usr/bin/ssh"

  [[ "$JSON_OUTPUT" != true ]] && info "Pulling $total worktree(s) in parallel..."

  # Create temp directory for results
  local tmpdir; tmpdir="$(/usr/bin/mktemp -d)"
  trap "/bin/rm -rf '$tmpdir'" EXIT

  # Launch parallel pulls
  local pids=()
  local idx=0
  local wt_path wt_branch
  for wt_entry in "${worktrees[@]}"; do
    wt_path="${wt_entry%%|*}"
    wt_branch="${wt_entry##*|}"

    (
      local pull_output pull_exit_code=0
      pull_output="$(/usr/bin/git -C "$wt_path" pull --rebase 2>&1)" || pull_exit_code=$?

      local result_status="ok"
      local already_up_to_date=false
      local commits_pulled=0

      if (( pull_exit_code != 0 )); then
        result_status="fail"
      elif [[ "$pull_output" == *"Already up to date"* ]]; then
        already_up_to_date=true
      fi

      # Extract commit count from "Updating abc123..def456" in pull output
      if [[ "$pull_output" =~ Updating\ ([a-f0-9]+)\.\.([a-f0-9]+) ]]; then
        local from_sha="${match[1]}"
        local to_sha="${match[2]}"
        commits_pulled="$(git -C "$wt_path" rev-list --count "$from_sha".."$to_sha" 2>/dev/null)" || commits_pulled=0
      fi

      # Write result as JSON line for later parsing
      json_escape "$pull_output"
      print -r -- "{\"status\":\"$result_status\",\"already_up_to_date\":$already_up_to_date,\"commits_pulled\":$commits_pulled,\"message\":\"$REPLY\"}" > "$tmpdir/$idx"
    ) &
    pids+=($!)
    idx=$((idx + 1))
  done

  # Wait for all to complete
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # JSON output mode - collect results into JSON array
  if [[ "$JSON_OUTPUT" == true ]]; then
    local worktree_results=()
    # Declare loop variables outside the loop to avoid zsh re-declaration issues
    local wt_branch result_data result_status already_up commits msg success
    idx=0
    for wt_entry in "${worktrees[@]}"; do
      wt_branch="${wt_entry##*|}"
      if [[ -f "$tmpdir/$idx" ]]; then
        result_data="$(/bin/cat "$tmpdir/$idx")"
        # Parse JSON using pure Zsh (zero subprocess spawns)
        result_status="$(json_get_string "$result_data" "status")"
        already_up="$(json_get_value "$result_data" "already_up_to_date")"
        commits="$(json_get_value "$result_data" "commits_pulled")"
        msg="$(json_get_string "$result_data" "message")"

        # Provide defaults for potentially empty values to ensure valid JSON
        [[ -z "$already_up" ]] && already_up="false"
        [[ -z "$commits" ]] && commits="0"

        success=true
        [[ "$result_status" == "fail" ]] && success=false
        [[ "$result_status" == "ok" ]] && count=$((count + 1))
        [[ "$result_status" == "fail" ]] && failed=$((failed + 1))
        [[ "$already_up" == "true" ]] && up_to_date=$((up_to_date + 1))

        json_escape "$wt_branch"; local _je_branch="$REPLY"
        worktree_results+=("{\"branch\":\"$_je_branch\",\"success\":$success,\"already_up_to_date\":$already_up,\"commits_pulled\":$commits,\"message\":\"$msg\"}")
      fi
      idx=$((idx + 1))
    done

    /bin/rm -rf "$tmpdir"
    trap - EXIT

    json_escape "$repo"; local _je_repo2="$REPLY"
    format_json "{\
\"repo\":\"$_je_repo2\",\
\"worktrees\":[${(j:,:)worktree_results}],\
\"summary\":{\"total\":$total,\"succeeded\":$count,\"failed\":$failed,\"up_to_date\":$up_to_date}\
}"
    return 0
  fi

  # Text output mode - collect results
  # Declare loop variables outside the loop to avoid zsh re-declaration output
  local wt_branch result_data result_status
  idx=0
  for wt_entry in "${worktrees[@]}"; do
    wt_branch="${wt_entry##*|}"
    if [[ -f "$tmpdir/$idx" ]]; then
      result_data="$(/bin/cat "$tmpdir/$idx")"
      # Parse JSON using pure Zsh (zero subprocess spawns)
      result_status="$(json_get_string "$result_data" "status")"
      if [[ "$result_status" == "ok" ]]; then
        ok "  $wt_branch"
        count=$((count + 1))
      else
        warn "  $wt_branch - failed"
        failed=$((failed + 1))
      fi
    fi
    idx=$((idx + 1))
  done

  /bin/rm -rf "$tmpdir"
  trap - EXIT

  print -r -- ""
  ok "Pulled $count worktree(s)"
  (( failed > 0 )) && warn "$failed worktree(s) had issues"

  # Send notification
  if (( failed > 0 )); then
    notify "grove pull-all" "Completed: $count success, $failed failed"
  else
    notify "grove pull-all" "All $count worktrees updated"
  fi
}

# cmd_sync — Rebase a worktree onto a base branch
cmd_sync() {
  local repo="${1:-}"; local branch="${2:-}"; local base="${3:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
    dim "  Detected: $repo / $branch"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to sync")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove sync [<repo> [<branch>]] [base] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Load repo-specific config (may override DEFAULT_BASE)
  load_repo_config "$git_dir"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # Use provided base, or the worktree's configured base, or default
  [[ -n "$base" ]] || base="$(worktree_base_for "$wt_path" "$DEFAULT_BASE")"

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  [[ "$JSON_OUTPUT" != true ]] && info "Fetching latest..."
  git --git-dir="$git_dir" fetch --all --prune --quiet 2>/dev/null || { [[ "$JSON_OUTPUT" != true ]] && warn "Fetch failed (continuing with local refs)"; }

  # Check for uncommitted changes
  if [[ -n "$(/usr/bin/git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
    if [[ "$JSON_OUTPUT" == true ]]; then
      json_escape "$base"; local _je_base="$REPLY"
      format_json "{\"success\": false, \"base\": \"$_je_base\", \"conflicts\": false, \"dirty\": true, \"commits_rebased\": 0, \"message\": \"worktree has uncommitted changes, commit or stash them first\"}"
      return 1
    fi
    error_exit "GIT_ERROR" "worktree has uncommitted changes, commit or stash them first" 4
  fi

  # JSON output mode
  if [[ "$JSON_OUTPUT" == true ]]; then
    local sync_output sync_exit_code=0
    sync_output="$(GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git -C "$wt_path" rebase "$base" 2>&1)" || sync_exit_code=$?

    local conflicts=false commits_rebased=0

    if (( sync_exit_code != 0 )) && [[ "$sync_output" == *"CONFLICT"* ]]; then
      conflicts=true
    fi

    # Extract commit count from rebase output (e.g., "Rebasing (3/5)" or count applied commits)
    if [[ "$sync_output" =~ Successfully\ rebased\ and\ updated ]]; then
      # Count commits between base and HEAD after successful rebase
      commits_rebased="$(git -C "$wt_path" rev-list --count "$base"..HEAD 2>/dev/null)" || commits_rebased=0
    fi

    local success_bool; [[ $sync_exit_code -eq 0 ]] && success_bool="true" || success_bool="false"
    json_escape "$base"; local _je_base2="$REPLY"
    json_escape "$sync_output"; local _je_sync="$REPLY"
    format_json "{\"success\": $success_bool, \"base\": \"$_je_base2\", \"conflicts\": $conflicts, \"dirty\": false, \"commits_rebased\": $commits_rebased, \"message\": \"$_je_sync\"}"

    # Run post-sync hooks even for JSON output (only on success)
    if (( sync_exit_code == 0 )); then
      local app_url; app_url="$(url_for "$repo" "$branch")"
      local db_name; db_name="$(db_name_for "$repo" "$branch")"
      run_hooks "post-sync" "$repo" "$branch" "$wt_path" "$app_url" "$db_name" >/dev/null 2>&1
    fi
    return $sync_exit_code
  fi

  # Text output mode
  info "Rebasing ${C_MAGENTA}$branch${C_RESET} onto ${C_DIM}$base${C_RESET}..."
  GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git -C "$wt_path" rebase "$base"
  ok "Sync complete"

  # Run post-sync hooks
  local app_url; app_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"
  run_hooks "post-sync" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"
}

# cmd_prune — Prune stale worktree references and optionally delete merged branches
cmd_prune() {
  local repo="${1:-}"

  # Multi-repo parallel mode (not supported with JSON)
  if [[ "${ALL_REPOS:-false}" == true ]]; then
    [[ "$JSON_OUTPUT" == true ]] && error_exit "INVALID_INPUT" "JSON output not supported with --all-repos" 2

    info "Pruning all repositories in parallel..."
    print -r -- ""

    local total_success=0 total_failed=0
    local operations=()

    # Collect all repos for parallel processing
    for git_dir in "$HERD_ROOT"/*.git(N); do
      [[ -d "$git_dir" ]] || continue
      local repo_name="${${git_dir:t}%.git}"
      operations+=("$repo_name|_prune_single_repo '$repo_name' '$git_dir'")
    done

    if (( ${#operations[@]} == 0 )); then
      dim "No repositories found."
      return 0
    fi

    # Process repos in parallel
    local tmpdir; tmpdir="$(/usr/bin/mktemp -d)"
    trap "/bin/rm -rf '$tmpdir'" EXIT

    local pids=()
    local idx=0
    for op in "${operations[@]}"; do
      local repo_name="${op%%|*}"
      local git_dir="$HERD_ROOT/${repo_name}.git"

      (
        local result="ok"
        git --git-dir="$git_dir" worktree prune -v >/dev/null 2>&1 || result="fail"
        print -r -- "$result" > "$tmpdir/$idx"
      ) &
      pids+=($!)
      idx=$((idx + 1))

      # Limit parallel jobs
      if (( ${#pids[@]} >= GROVE_MAX_PARALLEL )); then
        wait "${pids[1]}" 2>/dev/null || true
        shift pids
      fi
    done

    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
      wait "$pid" 2>/dev/null || true
    done

    # Collect results
    idx=0
    for op in "${operations[@]}"; do
      local repo_name="${op%%|*}"
      if [[ -f "$tmpdir/$idx" && "$(/bin/cat "$tmpdir/$idx")" == "ok" ]]; then
        ok "  $repo_name"
        total_success=$((total_success + 1))
      else
        warn "  $repo_name - failed"
        total_failed=$((total_failed + 1))
      fi
      idx=$((idx + 1))
    done

    /bin/rm -rf "$tmpdir"
    trap - EXIT

    print -r -- ""
    ok "Pruned $total_success repository(ies)"
    (( total_failed > 0 )) && warn "$total_failed repository(ies) had issues"

    notify "grove prune" "Completed: $total_success success, $total_failed failed"
    return 0
  fi

  # Single repo mode
  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove prune <repo> - Use --all-repos to prune across all repositories." 2

  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Prune stale worktrees and capture output
  [[ "$JSON_OUTPUT" != true ]] && info "Pruning stale worktrees..."
  local prune_output; prune_output="$(git --git-dir="$git_dir" worktree prune -v 2>&1)" || true
  local stale_refs_pruned=0
  if [[ -n "$prune_output" ]]; then
    stale_refs_pruned="$(print -r -- "$prune_output" | grep -c 'Removing' 2>/dev/null)" || stale_refs_pruned=0
  fi
  [[ "$JSON_OUTPUT" != true ]] && [[ -n "$prune_output" ]] && print -r -- "$prune_output"

  [[ "$JSON_OUTPUT" != true ]] && info "Looking for merged branches..."

  # Get list of branches that have been merged to staging/main
  # Get merged branches and trim whitespace using Zsh
  local merged_raw; merged_raw="$(git --git-dir="$git_dir" branch --merged origin/staging 2>/dev/null | grep -v 'staging\|main\|master')" || merged_raw=""
  local merged=""
  local branch_line
  while IFS= read -r branch_line; do
    # Trim leading/trailing whitespace using Zsh parameter expansion
    branch_line="${branch_line#"${branch_line%%[![:space:]]*}"}"
    branch_line="${branch_line%"${branch_line##*[![:space:]]}"}"
    [[ -n "$branch_line" ]] && merged+="${merged:+$'\n'}$branch_line"
  done <<< "$merged_raw"

  # JSON output mode
  if [[ "$JSON_OUTPUT" == true ]]; then
    local merged_branches=()
    local branches_found=0 branches_deleted=0

    if [[ -n "$merged" ]]; then
      while IFS= read -r b; do
        [[ -n "$b" ]] || continue
        branches_found=$((branches_found + 1))
        local deleted=false
        if [[ "$FORCE" == true ]]; then
          if git --git-dir="$git_dir" branch -D "$b" >/dev/null 2>&1; then
            deleted=true
            branches_deleted=$((branches_deleted + 1))
          fi
        fi
        json_escape "$b"; merged_branches+=("{\"name\":\"$REPLY\",\"deleted\":$deleted,\"reason\":\"merged to origin/staging\"}")
      done <<< "$merged"
    fi

    json_escape "$repo"; local _je_repo3="$REPLY"
    format_json "{\
\"repo\":\"$_je_repo3\",\
\"stale_refs_pruned\":$stale_refs_pruned,\
\"merged_branches\":[${(j:,:)merged_branches}],\
\"summary\":{\"branches_found\":$branches_found,\"branches_deleted\":$branches_deleted}\
}"
    return 0
  fi

  # Text output mode
  if [[ -n "$merged" ]]; then
    print -r -- ""
    warn "The following branches appear to be merged:"
    print -r -- "$merged" | while read -r b; do
      [[ -n "$b" ]] && print -r -- "  ${C_DIM}$b${C_RESET}"
    done
    print -r -- ""

    if [[ "$FORCE" == true ]]; then
      print -r -- "$merged" | while read -r b; do
        [[ -n "$b" ]] && git --git-dir="$git_dir" branch -D "$b" 2>/dev/null && ok "Deleted $b"
      done
    else
      dim "Run with -f to delete merged branches"
    fi
  else
    ok "No merged branches to clean up"
  fi

  ok "Prune complete"
}

# cmd_log — Show recent commit log for a worktree
cmd_log() {
  local repo="" branch="" count=5
  local args=()

  # Parse arguments - handle -n flag
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        shift
        if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
          count="$1"
          shift
        else
          error_exit "INVALID_INPUT" "Usage: grove log <repo> <branch> [--json] [-n <count>]" 2
        fi
        ;;
      -n*)
        # Handle -n5 format (no space)
        count="${1#-n}"
        if [[ ! "$count" =~ ^[0-9]+$ ]]; then
          error_exit "INVALID_INPUT" "Usage: grove log <repo> <branch> [--json] [-n <count>]" 2
        fi
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  # Extract repo and branch from remaining args
  repo="${args[1]:-}"
  branch="${args[2]:-}"

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

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove log <repo> <branch> [--json] [-n <count>]" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # JSON output mode
  if [[ "$JSON_OUTPUT" == true ]]; then
    local commits_json=()
    local log_output sha msg author date_iso

    # Get commits with specific format for JSON parsing
    # Format: %H|%s|%an|%aI (full sha, subject, author name, ISO date)
    while IFS='|' read -r sha msg author date_iso; do
      [[ -z "$sha" ]] && continue
      # Truncate SHA to 7 chars for display
      local short_sha="${sha:0:7}"
      json_escape "$short_sha"; local _je_sha="$REPLY"
      json_escape "$msg"; local _je_msg="$REPLY"
      json_escape "$author"; local _je_auth="$REPLY"
      json_escape "$date_iso"; local _je_date="$REPLY"
      commits_json+=("{\"sha\": \"$_je_sha\", \"message\": \"$_je_msg\", \"author\": \"$_je_auth\", \"date\": \"$_je_date\"}")
    done < <(git -C "$wt_path" log --format='%H|%s|%an|%aI' -n "$count" 2>/dev/null || true)

    format_json "{\"commits\": [${(j:, :)commits_json}]}"
    return 0
  fi

  # Text output mode (original behaviour)
  local base; base="$(worktree_base_for "$wt_path" "$DEFAULT_BASE")"

  print -r -- ""
  print -r -- "${C_BOLD}Recent commits in ${C_MAGENTA}$branch${C_RESET} ${C_DIM}(vs $base)${C_RESET}"
  print -r -- ""

  git -C "$wt_path" log --oneline --graph -n "$count" "$base"..HEAD 2>/dev/null || \
    git -C "$wt_path" log --oneline --graph -n "$count"

  print -r -- ""
}

# cmd_diff — Show diff stats between a worktree and its base branch
cmd_diff() {
  local repo="${1:-}"; local branch="${2:-}"; local base="${3:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to diff")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove diff [<repo> [<branch>]] [base] - Run from within a worktree to auto-detect, or specify repo/branch. Default base: $DEFAULT_BASE" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"

  ensure_bare_repo "$git_dir"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # Load repo-specific config (may override DEFAULT_BASE)
  load_repo_config "$git_dir"

  # Use provided base, or the worktree's configured base, or default
  [[ -n "$base" ]] || base="$(worktree_base_for "$wt_path" "$DEFAULT_BASE")"

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  # Fetch to ensure we have latest base
  info "Fetching latest..."
  cached_fetch "$git_dir" --all --prune --quiet || warn "Fetch failed (continuing with local refs)"

  # Check if base exists
  if ! git -C "$wt_path" rev-parse --verify "$base" >/dev/null 2>&1; then
    error_exit "BRANCH_NOT_FOUND" "base branch '$base' not found, try: origin/main, origin/staging, or origin/master" 3
  fi

  # Get stats
  local commits; commits="$(git -C "$wt_path" rev-list --count "$base"..HEAD 2>/dev/null)" || commits="?"
  local files; files="$(git -C "$wt_path" diff --stat "$base"..HEAD 2>/dev/null | tail -1)" || files=""

  print -r -- ""
  print -r -- "${C_BOLD}Diff: ${C_MAGENTA}$branch${C_RESET} ${C_DIM}vs${C_RESET} ${C_CYAN}$base${C_RESET}"
  print -r -- ""
  print -r -- "  ${C_DIM}Commits:${C_RESET} $commits"
  [[ -n "$files" ]] && print -r -- "  ${C_DIM}Summary:${C_RESET} $files"
  print -r -- ""

  # Show the diff
  git -C "$wt_path" diff "$base"..HEAD --stat

  print -r -- ""
  dim "  For full diff: git -C \"$wt_path\" diff $base..HEAD"
  dim "  For patch:     git -C \"$wt_path\" diff $base..HEAD > changes.patch"
  print -r -- ""
}

# cmd_summary — Show comprehensive summary of a worktree vs its base branch
cmd_summary() {
  local repo="${1:-}"; local branch="${2:-}"; local base="${3:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to summarise")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove summary [<repo> [<branch>]] [base] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Load repo-specific config (may override DEFAULT_BASE)
  load_repo_config "$git_dir"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # Use provided base, or the worktree's configured base, or default
  [[ -n "$base" ]] || base="$(worktree_base_for "$wt_path" "$DEFAULT_BASE")"

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  # Best-effort fetch for up-to-date comparison (non-fatal if offline)
  info "Fetching latest..."
  cached_fetch "$git_dir" --all --prune --quiet || warn "Fetch failed (continuing with local refs)"

  if ! git -C "$wt_path" rev-parse --verify "$base" >/dev/null 2>&1; then
    error_exit "BRANCH_NOT_FOUND" "base branch '$base' not found, try: origin/main, origin/staging, or origin/master" 3
  fi

  local counts; counts="$(get_ahead_behind "$wt_path" "$base")"
  local ahead="${counts%% *}" behind="${counts##* }"

  local st; st="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
  local change_count=0 staged=0 modified=0 untracked=0
  if [[ -n "$st" ]]; then
    change_count="$(count_lines "$st")"
    local status_counts
    status_counts="$(count_git_status_types "$st")"
    staged="${status_counts%% *}"
    local rest="${status_counts#* }"
    modified="${rest%% *}"
    untracked="${rest##* }"
  fi

  local ahead_total; ahead_total="$(git -C "$wt_path" rev-list --count "$base"..HEAD 2>/dev/null || print -r -- 0)"
  local behind_total; behind_total="$(git -C "$wt_path" rev-list --count HEAD.."$base" 2>/dev/null || print -r -- 0)"

  local shortstat; shortstat="$(git -C "$wt_path" diff --shortstat --no-color "$base"..HEAD 2>/dev/null || true)"
  local diffstat; diffstat="$(git -C "$wt_path" diff --stat --no-color "$base"..HEAD 2>/dev/null || true)"

  # JSON output mode
  if [[ "$JSON_OUTPUT" == true ]]; then
    local ahead_commits=() behind_commits=()
    local line="" sha="" subject=""

    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      sha="${line%% *}"
      subject="${line#* }"
      json_escape "$sha"; local _je_sha="$REPLY"
      json_escape "$subject"; local _je_subj="$REPLY"
      ahead_commits+=("{\"sha\":\"$_je_sha\",\"subject\":\"$_je_subj\"}")
    done < <(git -C "$wt_path" log --oneline --no-decorate -n 10 "$base"..HEAD 2>/dev/null || true)

    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      sha="${line%% *}"
      subject="${line#* }"
      json_escape "$sha"; _je_sha="$REPLY"
      json_escape "$subject"; _je_subj="$REPLY"
      behind_commits+=("{\"sha\":\"$_je_sha\",\"subject\":\"$_je_subj\"}")
    done < <(git -C "$wt_path" log --oneline --no-decorate -n 10 HEAD.."$base" 2>/dev/null || true)

    local diff_summary=""
    if [[ -n "$diffstat" ]]; then
      diff_summary="$(print -r -- "$diffstat" | tail -1)"
    fi

    json_escape "$repo"; local _je_repo="$REPLY"
    json_escape "$branch"; local _je_branch="$REPLY"
    json_escape "$wt_path"; local _je_path="$REPLY"
    json_escape "$base"; local _je_base="$REPLY"
    json_escape "${shortstat:-}"; local _je_stat="$REPLY"
    json_escape "$diff_summary"; local _je_diff="$REPLY"
    format_json "{\
\"repo\":\"$_je_repo\",\
\"branch\":\"$_je_branch\",\
\"path\":\"$_je_path\",\
\"base\":\"$_je_base\",\
\"ahead\":$ahead,\
\"behind\":$behind,\
\"ahead_commits_total\":$ahead_total,\
\"behind_commits_total\":$behind_total,\
\"uncommitted\":{\"total\":$change_count,\"staged\":$staged,\"modified\":$modified,\"untracked\":$untracked},\
\"diff\":{\"shortstat\":\"$_je_stat\",\"summary\":\"$_je_diff\"},\
\"ahead_commits\":[${(j:,:)ahead_commits}],\
\"behind_commits\":[${(j:,:)behind_commits}]\
}"
    return 0
  fi

  print -r -- ""
  print -r -- "${C_BOLD}Summary:${C_RESET} ${C_CYAN}$repo${C_RESET} / ${C_MAGENTA}$branch${C_RESET}"
  print -r -- ""
  print -r -- "  ${C_DIM}Path:${C_RESET} ${C_CYAN}$wt_path${C_RESET}"
  print -r -- "  ${C_DIM}Base:${C_RESET} ${C_DIM}$base${C_RESET}"
  print -r -- "  ${C_DIM}Sync:${C_RESET} ${C_GREEN}↑$ahead${C_RESET} ${C_RED}↓$behind${C_RESET}"
  print -r -- ""

  print -r -- "${C_BOLD}Working Tree${C_RESET}"
  if [[ -n "$st" ]]; then
    print -r -- "  ${C_DIM}Changes:${C_RESET} ${C_YELLOW}$change_count${C_RESET} total (${C_GREEN}$staged staged${C_RESET}, ${C_YELLOW}$modified modified${C_RESET}, ${C_DIM}$untracked untracked${C_RESET})"
    local shown=0
    print -r -- ""
    local status_short; status_short="$(git -C "$wt_path" status --short 2>/dev/null)"
    print -r -- "${C_DIM}$(first_n_lines "$status_short" 20)${C_RESET}"
    shown="$(count_lines "$status_short")"
    if (( shown > 20 )); then
      print -r -- "${C_DIM}... and $((shown - 20)) more${C_RESET}"
    fi
  else
    print -r -- "  ${C_GREEN}● Clean${C_RESET}"
  fi
  print -r -- ""

  print -r -- "${C_BOLD}Commits${C_RESET}"
  if (( ahead_total > 0 )); then
    print -r -- "  ${C_DIM}Ahead of base:${C_RESET} ${C_GREEN}$ahead_total${C_RESET}"
    git -C "$wt_path" log --oneline --no-decorate -n 10 "$base"..HEAD 2>/dev/null || true
    (( ahead_total > 10 )) && print -r -- "${C_DIM}... and $((ahead_total - 10)) more${C_RESET}"
  else
    print -r -- "  ${C_DIM}Ahead of base:${C_RESET} 0"
  fi
  print -r -- ""
  if (( behind_total > 0 )); then
    print -r -- "  ${C_DIM}Behind base:${C_RESET} ${C_RED}$behind_total${C_RESET}"
    git -C "$wt_path" log --oneline --no-decorate -n 10 HEAD.."$base" 2>/dev/null || true
    (( behind_total > 10 )) && print -r -- "${C_DIM}... and $((behind_total - 10)) more${C_RESET}"
  else
    print -r -- "  ${C_DIM}Behind base:${C_RESET} 0"
  fi
  print -r -- ""

  print -r -- "${C_BOLD}Diff (tree)${C_RESET} ${C_DIM}($branch vs $base)${C_RESET}"
  if [[ -n "$shortstat" ]]; then
    print -r -- "  ${C_DIM}$shortstat${C_RESET}"
  else
    print -r -- "  ${C_GREEN}No changes${C_RESET}"
  fi
  if [[ -n "$diffstat" ]]; then
    local lines=("${(@f)diffstat}")
    local total_lines=${#lines[@]}
    local summary_line="${lines[-1]}"
    local max_files=15

    print -r -- ""
    local i=1
    while (( i < total_lines && i <= max_files )); do
      print -r -- "  ${C_DIM}${lines[$i]}${C_RESET}"
      i=$((i + 1))
    done
    if (( total_lines > max_files + 1 )); then
      print -r -- "  ${C_DIM}... and $((total_lines - max_files - 1)) more file(s)${C_RESET}"
    fi
    print -r -- ""
    print -r -- "  ${C_DIM}$summary_line${C_RESET}"
  fi
  print -r -- ""

  dim "Next: grove diff \"$repo\" \"$branch\" \"$base\" | grove sync \"$repo\" \"$branch\" \"$base\""
  print -r -- ""
}

# cmd_changes — Get uncommitted file changes for a worktree
# Returns files with status codes (M=modified, A=added, D=deleted, ?=untracked)
cmd_changes() {
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

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove changes <repo> <branch> [--json]" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  # Get git status in porcelain format
  local st; st="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || st=""

  # JSON output mode
  if [[ "$JSON_OUTPUT" == true ]]; then
    local files_json=()

    if [[ -n "$st" ]]; then
      # Declare loop variables outside the loop to avoid zsh re-declaration issues
      local line status_code file_path simple_status
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Extract status code (first 2 chars) and file path (rest after space)
        # Porcelain format: XY filename (where XY is the status)
        status_code="${line:0:2}"
        file_path="${line:3}"

        # Simplify status code for JSON output
        # M = modified, A = added, D = deleted, R = renamed, C = copied, ? = untracked
        case "$status_code" in
          "??")  simple_status="?" ;;
          "!!")  simple_status="!" ;;  # Ignored
          " M"|"M "|"MM") simple_status="M" ;;
          " A"|"A "|"AM") simple_status="A" ;;
          " D"|"D ") simple_status="D" ;;
          "R "*)  simple_status="R" ;;
          "C "*)  simple_status="C" ;;
          "U"*|*"U")  simple_status="U" ;;  # Unmerged
          *)  simple_status="${status_code:0:1}" ;;  # First non-space char
        esac

        # Handle renamed files (format: R  old -> new)
        if [[ "$status_code" == "R "* && "$file_path" == *" -> "* ]]; then
          file_path="${file_path##* -> }"
        fi

        json_escape "$file_path"; files_json+=("{\"path\": \"$REPLY\", \"status\": \"$simple_status\"}")
      done <<< "$st"
    fi

    format_json "{\"files\": [${(j:, :)files_json}]}"
    return 0
  fi

  # Text output mode
  print -r -- ""
  print -r -- "${C_BOLD}Uncommitted changes in ${C_MAGENTA}$branch${C_RESET}"
  print -r -- ""

  if [[ -z "$st" ]]; then
    print -r -- "  ${C_GREEN}No uncommitted changes${C_RESET}"
  else
    local count; count="$(count_lines "$st")"
    print -r -- "  ${C_YELLOW}$count${C_RESET} file(s) with changes:"
    print -r -- ""

    # Show status with colours
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local status_code="${line:0:2}"
      local file_path="${line:3}"

      case "$status_code" in
        "??")
          print -r -- "  ${C_DIM}?${C_RESET}  ${C_DIM}$file_path${C_RESET}"
          ;;
        " M"|"M "|"MM")
          print -r -- "  ${C_YELLOW}M${C_RESET}  $file_path"
          ;;
        " A"|"A "|"AM")
          print -r -- "  ${C_GREEN}A${C_RESET}  $file_path"
          ;;
        " D"|"D ")
          print -r -- "  ${C_RED}D${C_RESET}  $file_path"
          ;;
        "R "*)
          print -r -- "  ${C_CYAN}R${C_RESET}  $file_path"
          ;;
        *)
          print -r -- "  ${C_MAGENTA}${status_code}${C_RESET} $file_path"
          ;;
      esac
    done <<< "$st"
  fi

  print -r -- ""
}
