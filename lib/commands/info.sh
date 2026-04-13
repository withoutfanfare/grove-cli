#!/usr/bin/env zsh
# info.sh - Information and status commands

# Display a single worktree entry for cmd_ls (text or JSON)
#
# In JSON mode, sets REPLY to a JSON object string.
# In text mode, prints formatted worktree details to stdout.
#
# Arguments:
#   $1 - index number
#   $2 - worktree path
#   $3 - branch name
#   $4 - HEAD ref (for detached worktrees)
#   $5 - repository name
_display_worktree() {
  local idx="$1" wt_path="$2" branch="$3" head="$4" repo="$5"
  local folder="${wt_path:t}"
  local url=""
  if [[ -n "$GROVE_URL_SUBDOMAIN" && -n "$branch" ]]; then
    # When a subdomain is configured, always use url_for() for the browser URL
    # (.env APP_URL is a Laravel internal config without subdomain prefix)
    url="$(url_for "$repo" "$branch")"
  elif [[ -f "$wt_path/.env" ]]; then
    # Extract APP_URL using pure Zsh (no subprocess spawns)
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*APP_URL= ]]; then
        url="${line#*=}"           # After =
        url="${url%%#*}"           # Before # (comments)
        url="${url//[\"\' ]}"      # Remove quotes and spaces
        break
      fi
    done < "$wt_path/.env"
  fi
  [[ -z "$url" ]] && url="https://${folder}.test"

  # Use cached status if available, fallback to direct git calls
  local sha dirty_status state_icon state_color state_text ahead behind
  local dirty=false
  local mismatch=false

  if has_cached_status "$wt_path"; then
    sha="$(get_cached_status "$wt_path" sha)"
    dirty_status="$(get_cached_status "$wt_path" dirty)"
    ahead="$(get_cached_status "$wt_path" ahead)"
    behind="$(get_cached_status "$wt_path" behind)"

    if [[ "$dirty_status" == "dirty" ]]; then
      # Need to get actual change count for display
      local st="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
      local changes="$(count_lines "$st")"
      state_icon="◐"
      state_color="$C_YELLOW"
      state_text="$changes uncommitted"
      dirty=true
    else
      state_icon="●"
      state_color="$C_GREEN"
      state_text="clean"
    fi
  else
    # Fallback to direct git calls
    sha="$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null || true)"
    local st="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
    state_icon="●"
    state_color="$C_GREEN"
    state_text="clean"

    if [[ -n "$st" ]]; then
      local changes="$(count_lines "$st")"
      state_icon="◐"
      state_color="$C_YELLOW"
      state_text="$changes uncommitted"
      dirty=true
    fi

    # Get ahead/behind via fallback
    local counts="$(get_ahead_behind "$wt_path" "$DEFAULT_BASE")"
    ahead="${counts%% *}"
    behind="${counts##* }"
  fi

  # Check for branch/directory mismatch
  local match_result="" expected_slug=""
  if [[ -n "$branch" ]]; then
    match_result="$(check_branch_directory_match "$wt_path" "$branch" "$repo")"
    if [[ "$match_result" == mismatch\|* ]]; then
      mismatch=true
      expected_slug="${match_result#mismatch|}"
    fi
  fi

  # Calculate health score
  local health_result; health_result="$(calculate_health_score "$wt_path")"
  local health_grade="${health_result%%|*}"
  local health_rest="${health_result#*|}"
  local health_score="${health_rest%%|*}"
  local health_issues="${health_rest#*|}"

  # Calculate new fields for enhanced JSON output
  local last_accessed="" merged=false stale=false

  if [[ "$JSON_OUTPUT" == true ]]; then
    # Get last accessed timestamp as ISO 8601
    last_accessed="$(get_last_accessed_iso "$wt_path")"

    # Derive merge status from health issues (avoids duplicate is_branch_merged call)
    if [[ "$health_issues" != *"unmerged"* ]]; then
      merged=true
    fi

    # Check if branch is stale (configurable commits behind base)
    if [[ "$(is_branch_stale "$wt_path" "$DEFAULT_BASE" "${GROVE_STALE_THRESHOLD:-50}")" == "true" ]]; then
      stale=true
    fi

    # Build JSON with new fields
    json_escape "$wt_path"; local _je_path="$REPLY"
    json_escape "$branch"; local _je_branch="$REPLY"
    json_escape "$sha"; local _je_sha="$REPLY"
    json_escape "$url"; local _je_url="$REPLY"
    local json_item="{"
    json_item+="\"path\": \"$_je_path\", "
    json_item+="\"branch\": \"$_je_branch\", "
    json_item+="\"sha\": \"$_je_sha\", "
    json_item+="\"url\": \"$_je_url\", "
    json_item+="\"dirty\": $dirty, "
    json_item+="\"ahead\": $ahead, "
    json_item+="\"behind\": $behind, "
    json_item+="\"mismatch\": $mismatch, "
    json_item+="\"health_grade\": \"$health_grade\", "
    json_item+="\"health_score\": $health_score, "
    # New fields for Phase 2/3
    if [[ -n "$last_accessed" ]]; then
      json_item+="\"lastAccessed\": \"$last_accessed\", "
    else
      json_item+="\"lastAccessed\": null, "
    fi
    json_item+="\"merged\": $merged, "
    json_item+="\"stale\": $stale"
    json_item+="}"

    REPLY="$json_item"
  else
    format_health_indicator "$health_grade"
    print -r -- "${C_BOLD}[$idx]${C_RESET} $REPLY ${C_CYAN}$wt_path${C_RESET}"
    if [[ -n "$branch" ]]; then
      print -r -- "    ${C_DIM}branch${C_RESET}  ${C_MAGENTA}$branch${C_RESET}"
    else
      [[ -n "$head" ]] && print -r -- "    ${C_DIM}head${C_RESET}    ${C_YELLOW}${head:0:12}${C_RESET} (detached)"
    fi
    [[ -n "$sha" ]] && print -r -- "    ${C_DIM}sha${C_RESET}     ${C_DIM}$sha${C_RESET}"
    print -r -- "    ${C_DIM}state${C_RESET}   ${state_color}${state_icon} ${state_text}${C_RESET}"
    format_grade "$health_grade"
    print -r -- "    ${C_DIM}health${C_RESET}  $REPLY ${C_DIM}($health_score/100)${C_RESET}"
    if (( ahead > 0 || behind > 0 )); then
      print -r -- "    ${C_DIM}sync${C_RESET}    ${C_GREEN}↑$ahead${C_RESET} ${C_RED}↓$behind${C_RESET}"
    fi
    print -r -- "    ${C_DIM}url${C_RESET}     ${C_BLUE}$url${C_RESET}"
    print -r -- "    ${C_DIM}cd${C_RESET}      ${C_DIM}cd ${(q)wt_path}${C_RESET}"
    if [[ "$mismatch" == true ]]; then
      print -r -- "    ${C_RED}MISMATCH${C_RESET} Directory name doesn't match branch!"
      print -r -- "      ${C_DIM}Expected:${C_RESET} ${repo}--${expected_slug}"
    fi
    print -r -- ""
    REPLY=""
  fi
}

# cmd_ls — List worktrees for a repository with status, health, and sync info
cmd_ls() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove ls [--json] <repo>" 2

  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"
  load_repo_config "$git_dir"

  # Clear any stale cache and collect fresh statuses
  clear_git_cache
  collect_worktree_statuses "$git_dir"

  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || true
  [[ -n "$out" ]] || { dim "No worktrees found."; return 0; }

  local json_items=()

  local wt_path="" branch="" head="" idx=0 line=""
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      # Skip bare repo entry (ends with .git)
      if [[ -n "$wt_path" && "$wt_path" != *.git ]]; then
        idx=$((idx + 1))
        _display_worktree "$idx" "$wt_path" "$branch" "$head" "$repo"
        [[ -n "$REPLY" ]] && json_items+=("$REPLY")
      fi
      wt_path=""; branch=""; head=""
      continue
    fi

    [[ "$line" == worktree\ * ]] && wt_path="${line#worktree }"
    [[ "$line" == branch\ refs/heads/* ]] && branch="${line#branch refs/heads/}"
    [[ "$line" == HEAD\ * ]] && head="${line#HEAD }"
  done <<< "$out"

  # Handle last entry (no trailing blank line) - skip bare repo
  if [[ -n "$wt_path" && "$wt_path" != *.git ]]; then
    idx=$((idx + 1))
    _display_worktree "$idx" "$wt_path" "$branch" "$head" "$repo"
    [[ -n "$REPLY" ]] && json_items+=("$REPLY")
  fi

  if [[ "$JSON_OUTPUT" == true ]]; then
    format_json "[${(j:, :)json_items}]"
  fi
}

# Display a single status row for cmd_status (text or JSON)
#
# In JSON mode, sets REPLY to a JSON object string.
# In text mode, prints a formatted table row to stdout.
# Sets REPLY2 to a mismatch entry string if a mismatch is detected, or "" otherwise.
#
# Arguments:
#   $1 - worktree path
#   $2 - branch name
#   $3 - repository name
#   $4 - stale threshold (commits behind)
#   $5 - inactive days threshold
_display_status_row() {
  local p="$1" b="$2" repo="$3" stale_threshold="$4" inactive_days="$5"

  local sha st state_icon state_color changes counts ahead behind
  local age age_days merged_icon sync_display is_stale is_inactive

  state_icon="●"
  state_color="$C_GREEN"
  is_stale=false
  is_inactive=false
  changes=0

  # Use cached status if available, fallback to direct git calls
  if has_cached_status "$p"; then
    sha="$(get_cached_status "$p" sha)"
    local dirty_status="$(get_cached_status "$p" dirty)"
    ahead="$(get_cached_status "$p" ahead)"
    behind="$(get_cached_status "$p" behind)"

    if [[ "$dirty_status" == "dirty" ]]; then
      # Need to get actual change count for display
      st="$(git -C "$p" status --porcelain 2>/dev/null)" || st=""
      changes="$(count_lines "$st")"
      state_icon="◐ $changes"
      state_color="$C_YELLOW"
    else
      st=""
    fi
  else
    # Fallback to direct git calls
    sha="$(git -C "$p" rev-parse --short HEAD 2>/dev/null)" || sha="?"
    st="$(git -C "$p" status --porcelain 2>/dev/null)" || st=""

    if [[ -n "$st" ]]; then
      changes="$(count_lines "$st")"
      state_icon="◐ $changes"
      state_color="$C_YELLOW"
    fi

    # Get sync status via fallback
    counts="$(get_ahead_behind "$p" "$DEFAULT_BASE")"
    ahead="${counts%% *}"
    behind="${counts##* }"
  fi

  # Check for mismatch
  REPLY2=""
  local match_result expected_slug
  match_result="$(check_branch_directory_match "$p" "$b" "$repo")"
  if [[ "$match_result" == mismatch\|* ]]; then
    expected_slug="${match_result#mismatch|}"
    REPLY2="${p:t}|$b|$expected_slug"
  fi

  # Check if stale (exceeds commits-behind threshold)
  if (( behind > stale_threshold )); then
    is_stale=true
    sync_display="${C_RED}↑$ahead ↓$behind${C_RESET}"
  else
    sync_display="↑$ahead ↓$behind"
  fi

  # Get age
  age="$(get_last_commit_age "$p")"
  age_days="$(get_commit_age_days "$p")"
  if (( age_days > inactive_days )); then
    is_inactive=true
  fi

  # Check if merged (cache result for reuse in JSON output)
  local merged=false
  if is_branch_merged "$p" "$DEFAULT_BASE"; then
    merged=true
    merged_icon="${C_DIM}✓${C_RESET}"
  else
    merged_icon="${C_DIM}-${C_RESET}"
  fi

  # Apply row colouring for stale/inactive
  local branch_display="${b:0:26}"
  local age_display="$age"
  if [[ "$is_stale" == true ]]; then
    branch_display="${C_RED}${b:0:26}${C_RESET}"
    state_color="$C_RED"
  elif [[ "$is_inactive" == true ]]; then
    age_display="${C_YELLOW}$age${C_RESET}"
  fi

  if [[ "$JSON_OUTPUT" == true ]]; then
    local dirty=false
    [[ -n "$st" ]] && dirty=true
    json_escape "$b"; local _je_b="$REPLY"
    json_escape "$p"; local _je_p="$REPLY"
    json_escape "$sha"; local _je_sha="$REPLY"
    REPLY="{\"branch\": \"$_je_b\", \"path\": \"$_je_p\", \"sha\": \"$_je_sha\", \"dirty\": $dirty, \"changes\": ${changes:-0}, \"ahead\": $ahead, \"behind\": $behind, \"stale\": $is_stale, \"age\": \"$age\", \"age_days\": $age_days, \"merged\": $merged}"
  else
    printf "  %-28s ${state_color}%-10s${C_RESET} %-14s %-6s %-7s ${C_DIM}%-10s${C_RESET}\n" \
      "$branch_display" "$state_icon" "$sync_display" "$age_display" "$merged_icon" "$sha"
    REPLY=""
  fi
}

# cmd_status — Show compact status table for all worktrees in a repository
cmd_status() {
  local repo="${1:-}"
  local stale_threshold="$GROVE_STALE_THRESHOLD"
  local inactive_days=30

  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove status <repo>" 2

  validate_name "$repo" "repository"

  local git_dir
  git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  info "Fetching latest..."
  cached_fetch "$git_dir" --all --prune --quiet

  # Clear any stale cache and collect fresh statuses
  clear_git_cache
  collect_worktree_statuses "$git_dir"

  # Collect worktrees using shared helper
  local status_worktrees=()
  collect_worktrees "$git_dir" status_worktrees
  (( ${#status_worktrees[@]} > 0 )) || { dim "No worktrees found."; return 0; }

  # JSON output mode
  local json_items=()

  if [[ "$JSON_OUTPUT" != true ]]; then
    print -r -- ""
    print -r -- "${C_BOLD}Worktree Status: ${C_CYAN}$repo${C_RESET}"
    print -r -- ""
    printf "  ${C_DIM}%-28s %-10s %-14s %-6s %-7s %-10s${C_RESET}\n" "BRANCH" "STATE" "SYNC" "AGE" "MERGED" "SHA"
    print -r -- "  ${C_DIM}$(printf '%.0s─' {1..83})${C_RESET}"
  fi

  local wt_path="" branch=""
  local mismatches=()

  local wt_entry
  for wt_entry in "${status_worktrees[@]}"; do
    wt_path="${wt_entry%%|*}"
    branch="${wt_entry##*|}"
    _display_status_row "$wt_path" "$branch" "$repo" "$stale_threshold" "$inactive_days"
    [[ -n "$REPLY" ]] && json_items+=("$REPLY")
    [[ -n "$REPLY2" ]] && mismatches+=("$REPLY2")
  done

  # JSON output
  if [[ "$JSON_OUTPUT" == true ]]; then
    format_json "[${(j:, :)json_items}]"
    return 0
  fi

  # Show mismatch warnings
  if (( ${#mismatches[@]} > 0 )); then
    print -r -- ""
    print -r -- "${C_RED}${C_BOLD}Branch/Directory Mismatches Detected:${C_RESET}"
    for m in "${mismatches[@]}"; do
      local dir="${m%%|*}"
      local rest="${m#*|}"
      local actual_branch="${rest%%|*}"
      local expected_slug="${rest#*|}"
      print -r -- "  ${C_YELLOW}$dir${C_RESET}"
      print -r -- "    ${C_DIM}Current branch:${C_RESET}  ${C_MAGENTA}$actual_branch${C_RESET}"
      print -r -- "    ${C_DIM}Expected dir:${C_RESET}    ${repo}--${expected_slug}"
      print -r -- "    ${C_DIM}Fix:${C_RESET} Checkout correct branch or recreate worktree"
    done
  fi

  print -r -- ""
}

# cmd_repos — List all repositories managed by grove
#
# Globals:
#   JSON_OUTPUT - when true, outputs JSON array of repo objects
#
# Returns:
#   0 on success
cmd_repos() {
  local repos; repos="$(list_repos)"

  if [[ -z "$repos" ]]; then
    dim "No repositories found in $HERD_ROOT"
    return 0
  fi

  # Declare loop variables outside loops to avoid zsh re-declaration output
  local git_dir wt_list wt_count _je_repo

  if [[ "$JSON_OUTPUT" == true ]]; then
    local json_items=()
    while IFS= read -r repo; do
      git_dir="$(git_dir_for "$repo")"
      wt_list="$(git --git-dir="$git_dir" worktree list 2>/dev/null)"
      wt_count="$(count_lines "$wt_list")"
      wt_count=$((wt_count - 1))  # Subtract bare repo entry
      (( wt_count < 0 )) && wt_count=0
      json_escape "$repo"; _je_repo="$REPLY"
      json_items+=("{\"name\": \"$_je_repo\", \"worktrees\": $wt_count}")
    done <<< "$repos"
    format_json "[${(j:, :)json_items}]"
  else
    print -r -- ""
    print -r -- "${C_BOLD}Repositories in ${C_CYAN}$HERD_ROOT${C_RESET}"
    print -r -- ""
    while IFS= read -r repo; do
      git_dir="$(git_dir_for "$repo")"
      wt_list="$(git --git-dir="$git_dir" worktree list 2>/dev/null)"
      wt_count="$(count_lines "$wt_list")"
      wt_count=$((wt_count - 1))  # Subtract bare repo entry
      (( wt_count < 0 )) && wt_count=0
      print -r -- "  ${C_GREEN}$repo${C_RESET} ${C_DIM}($wt_count worktrees)${C_RESET}"
    done <<< "$repos"
    print -r -- ""
  fi
}

# cmd_branches — List available branches for a repository (local and remote)
#
# Used by the grove-app Tauri desktop GUI for branch picker. Builds
# O(1) worktree lookup maps to efficiently mark which branches have
# active worktrees.
#
# Arguments:
#   $1 - repository name
#
# Globals:
#   JSON_OUTPUT - when true, outputs JSON with branch details
#
# Returns:
#   0 on success
cmd_branches() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove branches <repo>" 2
  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Fetch latest branches if not in quiet mode
  if [[ "$QUIET" != true && "$JSON_OUTPUT" != true ]]; then
    info "Fetching latest branches..."
  fi
  git --git-dir="$git_dir" fetch --all --prune --quiet 2>/dev/null || true

  # Build associative arrays for O(1) worktree lookups
  typeset -A worktree_by_branch    # branch -> path
  typeset -A has_worktree_map      # branch -> 1

  local wt_list
  wt_list="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || wt_list=""

  local current_path="" current_branch=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        current_path="${line#worktree }"
        ;;
      "branch "*)
        current_branch="${line#branch refs/heads/}"
        ;;
      "")
        if [[ -n "$current_branch" && -n "$current_path" && "$current_path" != *.git ]]; then
          has_worktree_map[$current_branch]=1
          worktree_by_branch[$current_branch]="$current_path"
        fi
        current_path=""
        current_branch=""
        ;;
    esac
  done <<< "$wt_list"
  # Handle last entry (no trailing blank line)
  if [[ -n "$current_branch" && -n "$current_path" && "$current_path" != *.git ]]; then
    has_worktree_map[$current_branch]=1
    worktree_by_branch[$current_branch]="$current_path"
  fi

  # Collect all branches (local + remote)
  local branches=()

  # Build associative array for local branches (for O(1) lookup when processing remotes)
  typeset -A local_branches_map

  # Declare loop variables outside loops to avoid zsh re-declaration output
  local has_worktree wt_path_for_branch sha last_commit

  # Local branches
  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    branch="${branch#\* }"  # Remove current branch marker
    branch="${branch## }"   # Trim leading space

    # Reset state-carrying variables to prevent bleed between iterations
    has_worktree=false
    wt_path_for_branch=""
    sha=""
    last_commit=""

    # Record this as a local branch for later lookup
    local_branches_map[$branch]=1

    # O(1) worktree lookup
    if [[ -n "${has_worktree_map[$branch]:-}" ]]; then
      has_worktree=true
      wt_path_for_branch="${worktree_by_branch[$branch]}"
    fi

    sha="$(git --git-dir="$git_dir" rev-parse --short "refs/heads/$branch" 2>/dev/null)" || sha=""
    last_commit="$(git --git-dir="$git_dir" log -1 --format=%ct "refs/heads/$branch" 2>/dev/null)" || last_commit=""

    branches+=("local|$branch|$has_worktree|$wt_path_for_branch|$sha|$last_commit")
  done < <(git --git-dir="$git_dir" branch --list --format='%(refname:short)' 2>/dev/null)

  # Remote branches (that don't have local tracking)
  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    branch="${branch#origin/}"

    # Skip HEAD
    [[ "$branch" == "HEAD" ]] && continue

    # O(1) check if we already have this as a local branch
    [[ -n "${local_branches_map[$branch]:-}" ]] && continue

    # Reset state-carrying variables to prevent bleed between iterations
    has_worktree=false
    wt_path_for_branch=""
    sha=""
    last_commit=""

    # O(1) worktree lookup
    if [[ -n "${has_worktree_map[$branch]:-}" ]]; then
      has_worktree=true
      wt_path_for_branch="${worktree_by_branch[$branch]}"
    fi

    sha="$(git --git-dir="$git_dir" rev-parse --short "origin/$branch" 2>/dev/null)" || sha=""
    last_commit="$(git --git-dir="$git_dir" log -1 --format=%ct "origin/$branch" 2>/dev/null)" || last_commit=""

    branches+=("remote|$branch|$has_worktree|$wt_path_for_branch|$sha|$last_commit")
  done < <(git --git-dir="$git_dir" branch -r --list --format='%(refname:short)' 2>/dev/null | grep '^origin/')

  # JSON output
  if [[ "$JSON_OUTPUT" == true ]]; then
    json_escape "$repo"; local _je_repo="$REPLY"
    local json="{"
    json+="\"repo\": \"$_je_repo\", "
    json+="\"branches\": ["

    # Declare loop variables outside to avoid zsh re-declaration output
    local first=true type rest name has_wt wt_path _je_name _je_wt _je_sha
    for entry in "${branches[@]}"; do
      type="${entry%%|*}"
      rest="${entry#*|}"
      name="${rest%%|*}"
      rest="${rest#*|}"
      has_wt="${rest%%|*}"
      rest="${rest#*|}"
      wt_path="${rest%%|*}"
      rest="${rest#*|}"
      sha="${rest%%|*}"
      last_commit="${rest#*|}"

      [[ "$first" == true ]] || json+=", "
      json_escape "$name"; _je_name="$REPLY"
      json+="{"
      json+="\"name\": \"$_je_name\", "
      json+="\"type\": \"$type\", "
      json+="\"has_worktree\": $has_wt, "
      if [[ "$has_wt" == true ]]; then
        json_escape "$wt_path"; _je_wt="$REPLY"
        json+="\"worktree_path\": \"$_je_wt\", "
      else
        json+="\"worktree_path\": null, "
      fi
      json_escape "$sha"; _je_sha="$REPLY"
      json+="\"sha\": \"$_je_sha\", "
      json+="\"last_commit_at\": ${last_commit:-null}"
      json+="}"
      first=false
    done

    json+="]}"
    format_json "$json"
    return 0
  fi

  # Text output
  print -r -- ""
  print -r -- "${C_BOLD}Branches: ${C_CYAN}$repo${C_RESET}"
  print -r -- ""
  printf "  ${C_DIM}%-40s %-8s %-10s %s${C_RESET}\n" "BRANCH" "TYPE" "WORKTREE" "SHA"
  print -r -- "  ${C_DIM}$(printf '%.0s─' {1..70})${C_RESET}"

  for entry in "${branches[@]}"; do
    local type="${entry%%|*}"
    local rest="${entry#*|}"
    local name="${rest%%|*}"
    rest="${rest#*|}"
    local has_wt="${rest%%|*}"
    rest="${rest#*|}"
    local wt_path="${rest%%|*}"
    rest="${rest#*|}"
    local sha="${rest%%|*}"

    local name_display="${name:0:38}"
    local type_display="$type"
    local wt_display="—"

    if [[ "$has_wt" == true ]]; then
      wt_display="${C_GREEN}✓${C_RESET}"
    fi

    if [[ "$type" == "local" ]]; then
      type_display="${C_GREEN}local${C_RESET}"
    else
      type_display="${C_DIM}remote${C_RESET}"
    fi

    printf "  %-40s %-8s %-10s ${C_DIM}%s${C_RESET}\n" \
      "${C_MAGENTA}$name_display${C_RESET}" "$type_display" "$wt_display" "$sha"
  done

  print -r -- ""
  print -r -- "  ${C_DIM}Total: ${#branches[@]} branches${C_RESET}"
  print -r -- ""
}

# cmd_report — Generate a markdown report for a repository's worktrees
#
# Arguments:
#   $1 - repository name
#   $2 - (optional) "--output"
#   $3 - (optional) output file path
#
# Returns:
#   0 on success, prints report to stdout or writes to file
cmd_report() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove report <repo> [--output <file>]" 2
  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  local output_file=""
  if [[ "${2:-}" == "--output" && -n "${3:-}" ]]; then
    output_file="$3"
  fi

  # Generate markdown report
  local report=""
  report+="# Worktree Report: $repo\n\n"
  report+="Generated: $(date '+%Y-%m-%d %H:%M:%S')\n\n"

  # Get worktree list
  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || true
  [[ -n "$out" ]] || { dim "No worktrees found."; return 0; }

  # Single pass - collect stats and table rows simultaneously
  local total=0 clean=0 dirty=0
  local table_rows=()
  local wt_path="" branch="" head=""
  # Declare loop variables outside to avoid zsh re-declaration output
  local status_st status_count status_icon ahead behind upstream last_commit

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == worktree\ * ]]; then
      wt_path="${line#worktree }"
    elif [[ "$line" == "branch refs/heads/"* ]]; then
      branch="${line#branch refs/heads/}"
    elif [[ "$line" == HEAD\ * ]]; then
      head="${line#HEAD }"
    elif [[ -z "$line" && -n "$wt_path" ]]; then
      [[ "$wt_path" == *.git ]] && { wt_path=""; branch=""; head=""; continue; }

      total=$((total + 1))

      status_st="$(git -C "$wt_path" status --porcelain 2>/dev/null)"
      status_count="$(count_lines "$status_st")"
      status_icon="clean"
      if (( status_count > 0 )); then
        status_icon="$status_count changes"
        dirty=$((dirty + 1))
      else
        clean=$((clean + 1))
      fi

      ahead=0
      behind=0
      upstream="$(git -C "$wt_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || upstream=""
      if [[ -n "$upstream" ]]; then
        ahead="$(git -C "$wt_path" rev-list --count '@{upstream}'..HEAD 2>/dev/null)" || ahead=0
        behind="$(git -C "$wt_path" rev-list --count HEAD..'@{upstream}' 2>/dev/null)" || behind=0
      fi

      last_commit="$(git -C "$wt_path" log -1 --format='%s' 2>/dev/null)" || last_commit=""
      # Truncate to 40 chars using pure Zsh
      if (( ${#last_commit} > 40 )); then
        last_commit="${last_commit:0:40}..."
      fi

      table_rows+=("| \`$branch\` | $status_icon | $ahead | $behind | $last_commit |")

      wt_path=""; branch=""; head=""
    fi
  done <<< "$out"

  # Handle last entry (no trailing blank line) - skip bare repo
  if [[ -n "$wt_path" && "$wt_path" != *.git ]]; then
    total=$((total + 1))

    status_st="$(git -C "$wt_path" status --porcelain 2>/dev/null)"
    status_count="$(count_lines "$status_st")"
    status_icon="clean"
    if (( status_count > 0 )); then
      status_icon="$status_count changes"
      dirty=$((dirty + 1))
    else
      clean=$((clean + 1))
    fi

    ahead=0
    behind=0
    upstream="$(git -C "$wt_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || upstream=""
    if [[ -n "$upstream" ]]; then
      ahead="$(git -C "$wt_path" rev-list --count '@{upstream}'..HEAD 2>/dev/null)" || ahead=0
      behind="$(git -C "$wt_path" rev-list --count HEAD..'@{upstream}' 2>/dev/null)" || behind=0
    fi

    last_commit="$(git -C "$wt_path" log -1 --format='%s' 2>/dev/null)" || last_commit=""
    if (( ${#last_commit} > 40 )); then
      last_commit="${last_commit:0:40}..."
    fi

    table_rows+=("| \`$branch\` | $status_icon | $ahead | $behind | $last_commit |")
  fi

  report+="## Summary\n\n"
  report+="| Metric | Count |\n"
  report+="|--------|-------|\n"
  report+="| Total worktrees | $total |\n"
  report+="| Clean | $clean |\n"
  report+="| With changes | $dirty |\n\n"

  report+="## Worktrees\n\n"
  report+="| Branch | Status | Ahead | Behind | Last Commit |\n"
  report+="|--------|--------|-------|--------|-------------|\n"

  local row
  for row in "${table_rows[@]}"; do
    report+="$row\n"
  done

  report+="\n## Hooks Available\n\n"
  if [[ -d "$GROVE_HOOKS_DIR" ]]; then
    for hook_type in pre-add post-add pre-rm post-rm post-pull post-sync; do
      if [[ -x "$GROVE_HOOKS_DIR/$hook_type" ]] || [[ -d "$GROVE_HOOKS_DIR/${hook_type}.d" ]]; then
        report+="- \`$hook_type\` (enabled)\n"
      else
        report+="- \`$hook_type\` (not configured)\n"
      fi
    done
  else
    report+="No hooks directory found at \`$GROVE_HOOKS_DIR\`\n"
  fi

  # Output report
  if [[ -n "$output_file" ]]; then
    print -r -- "$report" > "$output_file"
    ok "Report saved to: $output_file"
  else
    print -r -- "$report"
  fi
}

# Calculate health score for a worktree on an A-F grade scale
#
# Scoring deductions (max 100):
#   - Commits behind base: up to -30 (>50 behind: -30, >20: -20, >5: -10)
#   - Uncommitted changes: up to -20 (>20 changes: -20, >5: -10, else: -5)
#   - Days since last commit: up to -25 (>60d: -25, >30d: -15, >14d: -5)
#   - Unmerged into base: -10
#   - Untracked files >10: -5
#
# Arguments:
#   $1 - worktree path
#
# Output:
#   Prints "grade|score|issue1,issue2,..." to stdout
#   e.g. "B|82|behind:12,changes:3"
calculate_health_score() {
  local wt_path="$1"
  local score=100
  local issues=()

  # Check commits behind (max -30 points)
  local counts; counts="$(get_ahead_behind "$wt_path" "$DEFAULT_BASE")"
  local behind="${counts##* }"
  if (( behind > 50 )); then
    score=$((score - 30))
    issues+=("behind:$behind")
  elif (( behind > 20 )); then
    score=$((score - 20))
    issues+=("behind:$behind")
  elif (( behind > 5 )); then
    score=$((score - 10))
    issues+=("behind:$behind")
  fi

  # Check uncommitted changes (max -20 points)
  local st; st="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || st=""
  if [[ -n "$st" ]]; then
    local changes; changes="$(count_lines "$st")"
    if (( changes > 20 )); then
      score=$((score - 20))
      issues+=("changes:$changes")
    elif (( changes > 5 )); then
      score=$((score - 10))
      issues+=("changes:$changes")
    else
      score=$((score - 5))
      issues+=("changes:$changes")
    fi
  fi

  # Check days since last commit (max -25 points)
  local age_days; age_days="$(get_commit_age_days "$wt_path")"
  if (( age_days > 60 )); then
    score=$((score - 25))
    issues+=("age:${age_days}d")
  elif (( age_days > 30 )); then
    score=$((score - 15))
    issues+=("age:${age_days}d")
  elif (( age_days > 14 )); then
    score=$((score - 5))
    issues+=("age:${age_days}d")
  fi

  # Check merge status (max -10 points)
  if ! is_branch_merged "$wt_path" "$DEFAULT_BASE"; then
    score=$((score - 10))
    issues+=("unmerged")
  fi

  # Check untracked files (max -5 points)
  local untracked=0
  if [[ -n "$st" ]]; then
    untracked="$(count_matching "$st" '\?\?*')"
  fi
  if (( untracked > 10 )); then
    score=$((score - 5))
    issues+=("untracked:$untracked")
  fi

  # Ensure score is between 0-100
  (( score < 0 )) && score=0
  (( score > 100 )) && score=100

  # Calculate grade
  score_to_grade "$score"
  local grade="$REPLY"

  print -r -- "$grade|$score|${(j:,:)issues}"
}

# Convert a numeric score (0-100) to a letter grade
# Sets REPLY to one of: A, B, C, D, F
score_to_grade() {
  local score="$1"
  if (( score >= 90 )); then
    REPLY="A"
  elif (( score >= 80 )); then
    REPLY="B"
  elif (( score >= 70 )); then
    REPLY="C"
  elif (( score >= 60 )); then
    REPLY="D"
  else
    REPLY="F"
  fi
}

# Format health grade with colour - sets REPLY
format_grade() {
  local grade="$1"
  case "$grade" in
    A|B) REPLY="${C_GREEN}$grade${C_RESET}" ;;
    C|D) REPLY="${C_YELLOW}$grade${C_RESET}" ;;
    F)   REPLY="${C_RED}$grade${C_RESET}" ;;
    *)   REPLY="$grade" ;;
  esac
}

# Format health indicator as coloured dot - sets REPLY
format_health_indicator() {
  local grade="$1"
  case "$grade" in
    A|B) REPLY="${C_GREEN}●${C_RESET}" ;;
    C|D) REPLY="${C_YELLOW}●${C_RESET}" ;;
    F)   REPLY="${C_RED}●${C_RESET}" ;;
    *)   REPLY="${C_DIM}○${C_RESET}" ;;
  esac
}

# cmd_health — Run health check on all worktrees in a repository
#
# Aggregates individual worktree health scores into an overall grade,
# checks for stale references, orphaned databases, missing .env files,
# and branch/directory mismatches.
#
# Arguments:
#   $1 - repository name
#
# Globals:
#   JSON_OUTPUT - when true, outputs JSON health report
#
# Returns:
#   0 on success
cmd_health() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove health <repo>" 2
  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Collect worktrees once for reuse across all health checks
  local health_worktrees=()
  collect_worktrees "$git_dir" health_worktrees

  local wt_path="" branch=""
  local total_score=0 wt_count=0
  local healthy_count=0 warning_count=0 critical_count=0

  # Collect worktree health data
  local worktree_health=()
  local all_issues=()
  # Declare loop variables outside the loop to avoid zsh re-declaration issues
  local result grade rest score issues severity issue wt_entry

  for wt_entry in "${health_worktrees[@]}"; do
    wt_path="${wt_entry%%|*}"
    branch="${wt_entry##*|}"
    [[ -d "$wt_path" ]] || continue

    result="$(calculate_health_score "$wt_path")"
    grade="${result%%|*}"
    rest="${result#*|}"
    score="${rest%%|*}"
    issues="${rest#*|}"

    total_score=$((total_score + score))
    wt_count=$((wt_count + 1))

    # Categorise health
    if (( score >= 80 )); then
      healthy_count=$((healthy_count + 1))
    elif (( score >= 60 )); then
      warning_count=$((warning_count + 1))
    else
      critical_count=$((critical_count + 1))
    fi

    worktree_health+=("$branch|$grade|$score|$issues")

    # Collect issues for JSON output
    if [[ -n "$issues" && "$issues" != "" ]]; then
      severity="warning"
      (( score < 60 )) && severity="critical"
      local IFS=','
      for issue in $issues; do
        all_issues+=("$severity|$branch|$issue")
      done
    fi
  done

  # Calculate overall grade
  local avg_score=0 avg_grade="?"
  if (( wt_count > 0 )); then
    avg_score=$((total_score / wt_count))
    score_to_grade "$avg_score"
    avg_grade="$REPLY"
  fi

  # JSON output
  if [[ "$JSON_OUTPUT" == true ]]; then
    local json="{"
    json_escape "$repo"; local _je_repo="$REPLY"
    json+="\"repo\": \"$_je_repo\", "
    json+="\"overall_grade\": \"$avg_grade\", "
    json+="\"overall_score\": $avg_score, "
    json+="\"worktree_count\": $wt_count, "

    # Summary counts
    json+="\"summary\": {"
    json+="\"healthy\": $healthy_count, "
    json+="\"warning\": $warning_count, "
    json+="\"critical\": $critical_count"
    json+="}, "

    # Issues array
    json+="\"issues\": ["
    local first_issue=true
    for issue_entry in "${all_issues[@]}"; do
      local severity="${issue_entry%%|*}"
      local rest="${issue_entry#*|}"
      local wt_branch="${rest%%|*}"
      local message="${rest#*|}"

      [[ "$first_issue" == true ]] || json+=", "
      json_escape "$wt_branch"; local _je_wt="$REPLY"
      json_escape "$message"; local _je_msg="$REPLY"
      json+="{\"severity\": \"$severity\", \"worktree\": \"$_je_wt\", \"message\": \"$_je_msg\"}"
      first_issue=false
    done
    json+="], "

    # Worktrees array
    json+="\"worktrees\": ["
    local first_wt=true
    for wt_entry in "${worktree_health[@]}"; do
      local wt_branch="${wt_entry%%|*}"
      local rest="${wt_entry#*|}"
      local wt_grade="${rest%%|*}"
      rest="${rest#*|}"
      local wt_score="${rest%%|*}"
      local wt_issues="${rest#*|}"

      [[ "$first_wt" == true ]] || json+=", "
      json_escape "$wt_branch"; local _je_wt2="$REPLY"
      json+="{\"branch\": \"$_je_wt2\", \"grade\": \"$wt_grade\", \"score\": $wt_score, \"issues\": ["

      # Convert issues to array
      local first_wt_issue=true
      if [[ -n "$wt_issues" ]]; then
        local IFS=','
        for issue in $wt_issues; do
          [[ "$first_wt_issue" == true ]] || json+=", "
          json_escape "$issue"; json+="\"$REPLY\""
          first_wt_issue=false
        done
      fi
      json+="]}"
      first_wt=false
    done
    json+="]"

    json+="}"
    format_json "$json"
    return 0
  fi

  # Text output (original format)
  print -r -- ""
  print -r -- "${C_BOLD}Health Check: ${C_CYAN}$repo${C_RESET}"
  print -r -- ""

  # Show health scores for all worktrees
  print -r -- "${C_BOLD}Worktree Health Scores${C_RESET}"
  print -r -- ""
  printf "  ${C_DIM}%-5s %-30s %-6s %s${C_RESET}\n" "GRADE" "BRANCH" "SCORE" "ISSUES"
  print -r -- "  ${C_DIM}$(printf '%.0s─' {1..70})${C_RESET}"

  for wt_entry in "${worktree_health[@]}"; do
    local wt_branch="${wt_entry%%|*}"
    local rest="${wt_entry#*|}"
    local wt_grade="${rest%%|*}"
    rest="${rest#*|}"
    local wt_score="${rest%%|*}"
    local wt_issues="${rest#*|}"

    format_grade "$wt_grade"
    local grade_colored="$REPLY"
    local branch_display="${wt_branch:0:28}"
    local issues_display="${wt_issues//,/ }"

    printf "  %-5s %-30s %-6s ${C_DIM}%s${C_RESET}\n" \
      "$grade_colored" "$branch_display" "$wt_score" "$issues_display"
  done

  if (( wt_count > 0 )); then
    format_grade "$avg_grade"
    print -r -- ""
    print -r -- "  ${C_BOLD}Average:${C_RESET} $REPLY (${avg_score}/100)"
  fi
  print -r -- ""

  local issues=0 warnings=0

  # Check for stale worktrees (directories that no longer exist)
  print -r -- "${C_BOLD}Stale Worktrees${C_RESET}"
  local stale_paths=()
  local _stale_line="" _stale_wt_path=""
  local _stale_output=""
  _stale_output="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || _stale_output=""
  while IFS= read -r _stale_line; do
    if [[ "$_stale_line" == "worktree "* ]]; then
      _stale_wt_path="${_stale_line#worktree }"
    elif [[ -z "$_stale_line" ]]; then
      if [[ -n "$_stale_wt_path" && "$_stale_wt_path" != *.git && ! -d "$_stale_wt_path" ]]; then
        stale_paths+=("$_stale_wt_path")
      fi
      _stale_wt_path=""
    fi
  done <<< "$_stale_output"
  # Handle last entry
  if [[ -n "$_stale_wt_path" && "$_stale_wt_path" != *.git && ! -d "$_stale_wt_path" ]]; then
    stale_paths+=("$_stale_wt_path")
  fi
  if (( ${#stale_paths[@]} > 0 )); then
    warn "Found stale worktree references:"
    local _sp
    for _sp in "${stale_paths[@]}"; do
      print -r -- "  ${C_RED}x${C_RESET} $_sp"
    done
    issues=$((issues + ${#stale_paths[@]}))
    dim "  Fix: grove prune $repo"
  else
    ok "No stale worktrees"
  fi
  print -r -- ""

  # Check for orphaned databases
  print -r -- "${C_BOLD}Database Health${C_RESET}"
  if command -v mysql >/dev/null 2>&1; then
    local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER" -N -B)
    [[ -n "$DB_PASSWORD" ]] && mysql_cmd+=(-p"$DB_PASSWORD")

    local dbs; dbs="$("${mysql_cmd[@]}" -e "SHOW DATABASES LIKE '${repo}__%'" 2>/dev/null)" || dbs=""

    if [[ -n "$dbs" ]]; then
      local orphaned=0
      while read -r db; do
        local found=false
        # Reuse already-collected worktrees instead of calling git worktree list per database
        for wt_entry in "${health_worktrees[@]}"; do
          local hw_branch="${wt_entry##*|}"
          local wt_db; wt_db="$(db_name_for "$repo" "$hw_branch")"
          [[ "$wt_db" == "$db" ]] && found=true && break
        done

        if [[ "$found" == false ]]; then
          [[ $orphaned -eq 0 ]] && warn "Potentially orphaned databases:"
          print -r -- "  ${C_YELLOW}?${C_RESET} $db"
          orphaned=$((orphaned + 1))
        fi
      done <<< "$dbs"

      if [[ $orphaned -eq 0 ]]; then
        ok "No orphaned databases found"
      else
        warnings=$((warnings + orphaned))
        dim "  Verify and drop if not needed: mysql -e 'DROP DATABASE <name>'"
      fi
    else
      dim "  No databases found matching pattern ${repo}__*"
    fi
  else
    dim "  MySQL not available - skipping database checks"
  fi
  print -r -- ""

  # Check for missing .env files
  print -r -- "${C_BOLD}Environment Files${C_RESET}"
  local missing_env=0
  for wt_entry in "${health_worktrees[@]}"; do
    local env_path="${wt_entry%%|*}"
    if [[ -f "$env_path/.env.example" && ! -f "$env_path/.env" ]]; then
      [[ $missing_env -eq 0 ]] && warn "Worktrees missing .env file:"
      print -r -- "  ${C_YELLOW}!${C_RESET} ${env_path##*/}"
      missing_env=$((missing_env + 1))
    fi
  done
  if [[ $missing_env -eq 0 ]]; then
    ok "All worktrees have .env files"
  else
    warnings=$((warnings + missing_env))
    dim "  Fix: cd <worktree> && cp .env.example .env"
  fi
  print -r -- ""

  # Check for branch/directory mismatches
  print -r -- "${C_BOLD}Branch Consistency${C_RESET}"
  local mismatches=0
  check_worktree_mismatches "$git_dir"
  mismatches=$?
  if [[ $mismatches -eq 0 ]]; then
    ok "All worktrees match their expected branches"
  else
    issues=$((issues + mismatches))
  fi
  print -r -- ""

  # Summary
  print -r -- "${C_BOLD}Summary${C_RESET}"
  if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
    ok "No issues found - repository is healthy!"
  else
    [[ $issues -gt 0 ]] && warn "$issues issue(s) need attention"
    [[ $warnings -gt 0 ]] && dim "  $warnings warning(s) to review"
  fi
  print -r -- ""
}

# cmd_dashboard — Display a dashboard overview of all repositories and worktrees
#
# Shows per-repository health grades, dirty/stale counts, and up to
# 5 worktrees per repo with individual grades. Supports interactive
# mode via the INTERACTIVE global.
#
# Returns:
#   0 on success
cmd_dashboard() {
  # Interactive mode
  if [[ "${INTERACTIVE:-false}" == true ]]; then
    interactive_dashboard
    return $?
  fi

  print -r -- ""
  print -r -- "${C_BOLD}╔════════════════════════════════════════════════════════════════════╗${C_RESET}"
  print -r -- "${C_BOLD}║                          grove Dashboard                           ║${C_RESET}"
  print -r -- "${C_BOLD}╚════════════════════════════════════════════════════════════════════╝${C_RESET}"
  print -r -- ""

  local total_repos=0
  local total_worktrees=0
  local total_dirty=0
  local total_stale=0

  # Declare loop-scoped variables BEFORE the loop to avoid zsh local re-declaration bug
  local repo_name wt_path branch
  local repo_wt_count repo_dirty repo_stale repo_grade_sum
  local result grade rest score st age_days
  local avg_grade avg_score grade_colored
  local wt wt_branch wt_rest wt_grade wt_score wt_grade_colored
  local status_parts shown

  # Collect data for all repos
  for git_dir in "$HERD_ROOT"/*.git(N); do
    [[ -d "$git_dir" ]] || continue
    repo_name="${${git_dir:t}%.git}"
    total_repos=$((total_repos + 1))

    # Collect worktrees using shared helper
    local dash_worktrees=()
    collect_worktrees "$git_dir" dash_worktrees

    repo_wt_count=0
    repo_dirty=0
    repo_stale=0
    repo_grade_sum=0

    # Collect worktree info for this repo
    local wt_info=()
    local wt_entry
    for wt_entry in "${dash_worktrees[@]}"; do
      wt_path="${wt_entry%%|*}"
      branch="${wt_entry##*|}"
      [[ -d "$wt_path" ]] || continue

      # Process this worktree entry
      repo_wt_count=$((repo_wt_count + 1))
      total_worktrees=$((total_worktrees + 1))

      # Get health score
      result="$(calculate_health_score "$wt_path")"
      grade="${result%%|*}"
      rest="${result#*|}"
      score="${rest%%|*}"
      repo_grade_sum=$((repo_grade_sum + score))

      # Check dirty
      st="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || st=""
      if [[ -n "$st" ]]; then
        repo_dirty=$((repo_dirty + 1))
        total_dirty=$((total_dirty + 1))
      fi

      # Check stale
      age_days="$(get_commit_age_days "$wt_path")"
      if (( age_days > 30 )); then
        repo_stale=$((repo_stale + 1))
        total_stale=$((total_stale + 1))
      fi

      wt_info+=("$branch|$grade|$score")
    done

    # Calculate average grade for repo
    avg_grade="?"
    if (( repo_wt_count > 0 )); then
      avg_score=$((repo_grade_sum / repo_wt_count))
      score_to_grade "$avg_score"
      avg_grade="$REPLY"
    fi

    # Print repo summary
    format_grade "$avg_grade"
    grade_colored="$REPLY"
    print -r -- "${C_BOLD}${C_CYAN}$repo_name${C_RESET} ${C_DIM}($repo_wt_count worktrees)${C_RESET} $grade_colored"

    # Show status indicators
    status_parts=()
    if (( repo_dirty > 0 )); then
      status_parts+=("${C_YELLOW}$repo_dirty dirty${C_RESET}")
    fi
    if (( repo_stale > 0 )); then
      status_parts+=("${C_RED}$repo_stale stale${C_RESET}")
    fi
    if (( ${#status_parts[@]} > 0 )); then
      print -r -- "  ${(j: | :)status_parts}"
    fi

    # Show worktrees (limit to 5)
    shown=0
    for wt in "${wt_info[@]}"; do
      (( shown >= 5 )) && break
      wt_branch="${wt%%|*}"
      wt_rest="${wt#*|}"
      wt_grade="${wt_rest%%|*}"
      wt_score="${wt_rest#*|}"
      format_grade "$wt_grade"
      wt_grade_colored="$REPLY"
      print -r -- "  ${C_DIM}├─${C_RESET} ${C_MAGENTA}${wt_branch:0:35}${C_RESET} $wt_grade_colored"
      shown=$((shown + 1))
    done

    if (( ${#wt_info[@]} > 5 )); then
      print -r -- "  ${C_DIM}└─ ... and $((${#wt_info[@]} - 5)) more${C_RESET}"
    elif (( ${#wt_info[@]} > 0 )); then
      # Change last ├─ to └─ for visual consistency
      :
    fi
    print -r -- ""
  done

  # Print summary
  print -r -- "${C_DIM}────────────────────────────────────────────────────────────────────${C_RESET}"
  print -r -- ""
  print -r -- "${C_BOLD}Summary${C_RESET}"
  print -r -- "  Repositories:  ${C_GREEN}$total_repos${C_RESET}"
  print -r -- "  Worktrees:     ${C_GREEN}$total_worktrees${C_RESET}"
  if (( total_dirty > 0 )); then
    print -r -- "  With changes:  ${C_YELLOW}$total_dirty${C_RESET}"
  fi
  if (( total_stale > 0 )); then
    print -r -- "  Stale (>30d):  ${C_RED}$total_stale${C_RESET}"
  fi
  print -r -- ""

  dim "Commands: grove status <repo> | grove health <repo> | grove recent"
  print -r -- ""
}
