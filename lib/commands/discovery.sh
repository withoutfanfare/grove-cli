#!/usr/bin/env zsh
# discovery.sh - Worktree discovery and filtering commands

# cmd_info — Show detailed information about a specific worktree
cmd_info() {
  local repo="${1:-}"
  local branch="${2:-}"

  # Auto-detect from current directory
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
    [[ "$JSON_OUTPUT" != true ]] && dim "  Detected: $repo / $branch"
  fi

  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove info <repo> [branch]" 2
  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"
  load_repo_config "$git_dir"

  # If no branch specified, use fzf or error
  if [[ -z "$branch" ]]; then
    if command -v fzf >/dev/null 2>&1; then
      branch="$(select_worktree "$git_dir")" || return 1
    else
      error_exit "INVALID_INPUT" "branch required, usage: grove info <repo> <branch>" 2
    fi
  fi

  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"

  if [[ ! -d "$wt_path" ]]; then
    error_exit "WORKTREE_NOT_FOUND" "worktree not found at '$wt_path'" 3
  fi

  # Collect all data first (shared between JSON and text output)
  local url; url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"
  local sha; sha="$(git -C "$wt_path" rev-parse HEAD 2>/dev/null)" || sha=""
  local short_sha; short_sha="$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null)" || short_sha=""
  local last_msg; last_msg="$(git -C "$wt_path" log -1 --format='%s' 2>/dev/null)" || last_msg=""
  # Truncate to 60 chars using pure Zsh
  (( ${#last_msg} > 60 )) && last_msg="${last_msg:0:60}"
  local last_date; last_date="$(git -C "$wt_path" log -1 --format='%ar' 2>/dev/null)" || last_date=""
  local author; author="$(git -C "$wt_path" log -1 --format='%an' 2>/dev/null)" || author=""
  local tracking; tracking="$(git -C "$wt_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || tracking=""

  # Sync status
  local counts; counts="$(get_ahead_behind "$wt_path" "$DEFAULT_BASE")"
  local ahead="${counts%% *}" behind="${counts##* }"

  # Working tree status
  local st; st="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || st=""
  local dirty=false changes=0 staged=0 modified=0 untracked=0
  if [[ -n "$st" ]]; then
    dirty=true
    changes="$(count_lines "$st")"
    local status_counts
    status_counts="$(count_git_status_types "$st")"
    staged="${status_counts%% *}"
    local rest="${status_counts#* }"
    modified="${rest%% *}"
    untracked="${rest##* }"
  fi

  # Disk usage - single du call per path, convert to human-readable in Zsh
  local total_kb total_size total_bytes
  total_kb="$(get_dir_size_kb "$wt_path")"
  total_bytes=$((total_kb * 1024))
  total_size="$(bytes_to_human "$total_kb")"

  local nm_size="" nm_bytes=0
  if [[ -d "$wt_path/node_modules" ]]; then
    local nm_kb
    nm_kb="$(get_dir_size_kb "$wt_path/node_modules")"
    nm_bytes=$((nm_kb * 1024))
    nm_size="$(bytes_to_human "$nm_kb")"
  fi

  local vendor_size="" vendor_bytes=0
  if [[ -d "$wt_path/vendor" ]]; then
    local vendor_kb
    vendor_kb="$(get_dir_size_kb "$wt_path/vendor")"
    vendor_bytes=$((vendor_kb * 1024))
    vendor_size="$(bytes_to_human "$vendor_kb")"
  fi

  # Framework detection
  local framework="" framework_version="" php_version=""
  if [[ -f "$wt_path/artisan" ]]; then
    framework="laravel"
    # Extract Laravel version from composer.lock using pure Zsh regex
    if [[ -f "$wt_path/composer.lock" ]]; then
      local lock_line
      while IFS= read -r lock_line; do
        if [[ "$lock_line" == *"laravel/framework"* ]]; then
          # Read next few lines to find version
          while IFS= read -r lock_line; do
            if [[ "$lock_line" =~ \"version\":[[:space:]]*\"([^\"]+)\" ]]; then
              framework_version="${match[1]}"
              break 2
            fi
          done
        fi
      done < "$wt_path/composer.lock"
    fi
    php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null)" || php_version=""
  fi

  local node_deps=0
  if [[ -f "$wt_path/package.json" ]]; then
    node_deps="$(jq '.dependencies | length' "$wt_path/package.json" 2>/dev/null || echo 0)"
  fi

  # Database check
  local db_exists=false
  if command -v mysql >/dev/null 2>&1; then
    local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER" -N -B)
    [[ -n "$DB_PASSWORD" ]] && mysql_cmd+=(-p"$DB_PASSWORD")
    if "${mysql_cmd[@]}" -e "SELECT 1 FROM information_schema.schemata WHERE schema_name='$db_name'" 2>/dev/null | grep -q 1; then
      db_exists=true
    fi
  fi

  # Timestamps
  local created_at="" accessed_at="" last_commit_at=""
  accessed_at="$(stat -f '%m' "$wt_path" 2>/dev/null || stat -c '%Y' "$wt_path" 2>/dev/null || echo "")"
  last_commit_at="$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null)" || last_commit_at=""

  # Health score
  local health_result; health_result="$(calculate_health_score "$wt_path")"
  local health_grade="${health_result%%|*}"
  local health_rest="${health_result#*|}"
  local health_score="${health_rest%%|*}"
  local health_issues="${health_rest#*|}"

  # JSON output
  if [[ "$JSON_OUTPUT" == true ]]; then
    # Pre-escape all values for JSON
    json_escape "$repo"; local _je_repo="$REPLY"
    json_escape "$branch"; local _je_branch="$REPLY"
    json_escape "$wt_path"; local _je_path="$REPLY"
    json_escape "$url"; local _je_url="$REPLY"
    json_escape "$git_dir"; local _je_gitdir="$REPLY"
    json_escape "$db_name"; local _je_db="$REPLY"
    json_escape "$sha"; local _je_sha="$REPLY"
    json_escape "$short_sha"; local _je_ssha="$REPLY"
    json_escape "$tracking"; local _je_track="$REPLY"
    json_escape "$last_msg"; local _je_msg="$REPLY"
    json_escape "$author"; local _je_auth="$REPLY"
    json_escape "$last_date"; local _je_date="$REPLY"
    json_escape "$total_size"; local _je_size="$REPLY"
    json_escape "$framework"; local _je_fw="$REPLY"
    json_escape "$framework_version"; local _je_fwv="$REPLY"
    json_escape "$php_version"; local _je_php="$REPLY"

    local json="{"
    json+="\"repo\": \"$_je_repo\", "
    json+="\"branch\": \"$_je_branch\", "
    json+="\"path\": \"$_je_path\", "
    json+="\"url\": \"$_je_url\", "
    json+="\"bare_repo\": \"$_je_gitdir\", "

    # Database
    json+="\"database\": {"
    json+="\"name\": \"$_je_db\", "
    json+="\"exists\": $db_exists"
    json+="}, "

    # Git
    json+="\"git\": {"
    json+="\"sha\": \"$_je_sha\", "
    json+="\"sha_short\": \"$_je_ssha\", "
    json+="\"branch\": \"$_je_branch\", "
    json+="\"tracking\": \"$_je_track\", "
    json+="\"ahead\": $ahead, "
    json+="\"behind\": $behind, "
    json+="\"dirty\": $dirty, "
    json+="\"changes\": $changes, "
    json+="\"last_message\": \"$_je_msg\", "
    json+="\"last_author\": \"$_je_auth\", "
    json+="\"last_date\": \"$_je_date\""
    json+="}, "

    # Uncommitted
    json+="\"uncommitted\": {"
    json+="\"total\": $changes, "
    json+="\"staged\": $staged, "
    json+="\"modified\": $modified, "
    json+="\"untracked\": $untracked"
    json+="}, "

    # Disk
    json+="\"disk\": {"
    json+="\"size_bytes\": $total_bytes, "
    json+="\"size_human\": \"$_je_size\", "
    json+="\"node_modules_bytes\": $nm_bytes, "
    json+="\"vendor_bytes\": $vendor_bytes"
    json+="}, "

    # Framework
    json+="\"framework\": {"
    json+="\"detected\": \"$_je_fw\", "
    json+="\"version\": \"$_je_fwv\", "
    json+="\"php_version\": \"$_je_php\", "
    json+="\"node_deps\": $node_deps"
    json+="}, "

    # Timestamps
    json+="\"timestamps\": {"
    json+="\"accessed_at\": ${accessed_at:-null}, "
    json+="\"last_commit_at\": ${last_commit_at:-null}"
    json+="}, "

    # Health
    json+="\"health\": {"
    json+="\"grade\": \"$health_grade\", "
    json+="\"score\": $health_score, "
    # Convert comma-separated issues to JSON array
    local issues_json="["
    if [[ -n "$health_issues" ]]; then
      local first=true
      local IFS=','
      for issue in $health_issues; do
        [[ "$first" == true ]] || issues_json+=", "
        json_escape "$issue"; issues_json+="\"$REPLY\""
        first=false
      done
    fi
    issues_json+="]"
    json+="\"issues\": $issues_json"
    json+="}"

    json+="}"
    format_json "$json"
    return 0
  fi

  # Text output (original format)
  print -r -- ""
  print -r -- "${C_BOLD}Worktree Info: ${C_CYAN}$repo${C_RESET} / ${C_MAGENTA}$branch${C_RESET}"
  print -r -- ""

  # Basic info
  print -r -- "${C_BOLD}Location${C_RESET}"
  print -r -- "  Path:     ${C_CYAN}$wt_path${C_RESET}"
  print -r -- "  URL:      ${C_BLUE}$url${C_RESET}"
  print -r -- "  Database: ${C_YELLOW}$db_name${C_RESET}"
  print -r -- ""

  # Git info
  print -r -- "${C_BOLD}Git${C_RESET}"
  print -r -- "  Commit:   ${C_DIM}$short_sha${C_RESET}"
  print -r -- "  Message:  ${C_DIM}$last_msg${C_RESET}"
  print -r -- "  Date:     ${C_DIM}$last_date${C_RESET}"
  print -r -- "  Author:   ${C_DIM}$author${C_RESET}"
  print -r -- "  Sync:     ${C_GREEN}↑$ahead${C_RESET} ${C_RED}↓$behind${C_RESET} vs $DEFAULT_BASE"
  print -r -- ""

  # Working tree status
  print -r -- "${C_BOLD}Status${C_RESET}"
  if [[ "$dirty" == true ]]; then
    print -r -- "  Changes:  ${C_YELLOW}$changes${C_RESET} total"
    print -r -- "  Staged:   ${C_GREEN}$staged${C_RESET}"
    print -r -- "  Modified: ${C_YELLOW}$modified${C_RESET}"
    print -r -- "  Untracked: ${C_DIM}$untracked${C_RESET}"
  else
    print -r -- "  Status:   ${C_GREEN}● Clean${C_RESET}"
  fi
  print -r -- ""

  # Disk usage
  print -r -- "${C_BOLD}Disk Usage${C_RESET}"
  print -r -- "  Total:        ${C_YELLOW}$total_size${C_RESET}"
  [[ -n "$nm_size" ]] && print -r -- "  node_modules: ${C_DIM}$nm_size${C_RESET}"
  [[ -n "$vendor_size" ]] && print -r -- "  vendor:       ${C_DIM}$vendor_size${C_RESET}"
  print -r -- ""

  # Framework detection
  print -r -- "${C_BOLD}Framework${C_RESET}"
  [[ -n "$framework_version" ]] && print -r -- "  Laravel:  ${C_GREEN}$framework_version${C_RESET}"
  [[ -f "$wt_path/package.json" ]] && print -r -- "  Node:     ${C_DIM}$node_deps dependencies${C_RESET}"
  print -r -- ""
}


# cmd_recent — List recently accessed worktrees sorted by access time
cmd_recent() {
  local limit="${1:-5}"

  # Find all worktrees and sort by access time
  local worktrees=()

  # Declare loop-scoped variables BEFORE the loop to avoid zsh local re-declaration bug
  local repo_name wt_path wt_branch atime
  local entry rest repo branch now age age_str

  local repo_wts wt_entry
  for git_dir in "$HERD_ROOT"/*.git(N); do
    [[ -d "$git_dir" ]] || continue
    repo_name="${${git_dir:t}%.git}"
    load_repo_config "$git_dir"

    # Collect worktrees using shared helper
    repo_wts=()
    collect_worktrees "$git_dir" repo_wts

    for wt_entry in "${repo_wts[@]}"; do
      wt_path="${wt_entry%%|*}"
      wt_branch="${wt_entry##*|}"
      [[ -d "$wt_path" ]] || continue
      atime="$(stat -f '%m' "$wt_path" 2>/dev/null || stat -c '%Y' "$wt_path" 2>/dev/null || echo 0)"
      worktrees+=("$atime|$repo_name|$wt_path|$wt_branch")
    done
  done

  if (( ${#worktrees[@]} == 0 )); then
    if [[ "$JSON_OUTPUT" == true ]]; then
      format_json "[]"
    else
      dim "No worktrees found."
    fi
    return 0
  fi

  # Sort by access time (newest first) using Zsh
  # We still need sort for numerical sorting, but avoid head subprocess
  local sorted_all
  sorted_all=($(printf '%s\n' "${worktrees[@]}" | sort -t'|' -k1 -rn))
  # Take first N entries using Zsh array slicing
  local sorted=("${sorted_all[@]:0:$limit}")

  # JSON output
  if [[ "$JSON_OUTPUT" == true ]]; then
    local json_items=()

    for entry in "${sorted[@]}"; do
      atime="${entry%%|*}"
      rest="${entry#*|}"
      repo="${rest%%|*}"
      rest="${rest#*|}"
      wt_path="${rest%%|*}"
      branch="${rest##*|}"

      # Get URL
      local url="$(url_for "$repo" "$branch")"

      # Check dirty status
      local dirty=false
      local st="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
      [[ -n "$st" ]] && dirty=true

      # Format age string
      now="$(_get_now)"
      age=$((now - atime))
      if (( age < 3600 )); then
        age_str="$((age / 60))m ago"
      elif (( age < 86400 )); then
        age_str="$((age / 3600))h ago"
      else
        age_str="$((age / 86400))d ago"
      fi

      json_escape "$repo"; local _je_repo="$REPLY"
      json_escape "$branch"; local _je_branch="$REPLY"
      json_escape "$wt_path"; local _je_path="$REPLY"
      json_escape "$url"; local _je_url="$REPLY"
      json_escape "$age_str"; local _je_age="$REPLY"
      json_items+=("{\"repo\": \"$_je_repo\", \"branch\": \"$_je_branch\", \"path\": \"$_je_path\", \"url\": \"$_je_url\", \"accessed_at\": $atime, \"accessed_ago\": \"$_je_age\", \"dirty\": $dirty}")
    done

    format_json "[${(j:, :)json_items}]"
    return 0
  fi

  # Text output
  print -r -- ""
  print -r -- "${C_BOLD}Recently Accessed Worktrees${C_RESET}"
  print -r -- ""

  local idx=0
  for entry in "${sorted[@]}"; do
    idx=$((idx + 1))
    atime="${entry%%|*}"
    rest="${entry#*|}"
    repo="${rest%%|*}"
    rest="${rest#*|}"
    wt_path="${rest%%|*}"
    branch="${rest##*|}"

    # Format time
    now="$(_get_now)"
    age=$((now - atime))
    if (( age < 3600 )); then
      age_str="$((age / 60))m ago"
    elif (( age < 86400 )); then
      age_str="$((age / 3600))h ago"
    else
      age_str="$((age / 86400))d ago"
    fi

    print -r -- "  ${C_BOLD}[$idx]${C_RESET} ${C_CYAN}$repo${C_RESET} / ${C_MAGENTA}$branch${C_RESET}"
    print -r -- "      ${C_DIM}$age_str${C_RESET}"
  done

  print -r -- ""
  dim "Usage: cd \"\$(grove cd <repo> <branch>)\""
  print -r -- ""
}


# Format bytes to human-readable size string
#
# Arguments:
#   $1 - byte count
#
# Output:
#   Prints formatted size string (e.g. "1.2M", "500B")
_format_size_bytes() {
  local bytes="$1"
  if (( bytes < 1024 )); then
    print -r -- "${bytes}B"
  else
    local kb=$((bytes / 1024))
    bytes_to_human "$kb"
  fi
}

# Process a single repository for the clean command, removing node_modules
# and vendor directories from inactive worktrees
#
# Arguments:
#   $1 - repository name
#   $2 - inactive_days threshold
#   $3 - dry_run flag (true/false)
#
# Output:
#   Sets REPLY to "saved|cleaned" with cumulative totals
_clean_process_repo() {
  local repo_name="$1"
  local inactive_days="$2"
  local dry_run="$3"
  local git_dir; git_dir="$(git_dir_for "$repo_name")"

  local repo_saved=0
  local repo_cleaned=0

  local clean_worktrees=()
  collect_worktrees "$git_dir" clean_worktrees
  (( ${#clean_worktrees[@]} > 0 )) || { REPLY="0|0"; return; }

  local wt_path="" entry=""
  local age_days nm_size vendor_size wt_saved folder nm_human v_human du_out

  for entry in "${clean_worktrees[@]}"; do
    wt_path="${entry%%|*}"
    [[ -d "$wt_path" ]] || continue

    age_days="$(get_commit_age_days "$wt_path")"

    if (( age_days > inactive_days )); then
      nm_size=0
      vendor_size=0
      wt_saved=0

      # Check node_modules - extract first field using Zsh
      if [[ -d "$wt_path/node_modules" ]]; then
        du_out="$(du -sk "$wt_path/node_modules" 2>/dev/null)" || du_out="0"
        nm_size="${du_out%%$'\t'*}"
        nm_size=$((nm_size * 1024))  # Convert to bytes
      fi

      # Check vendor - extract first field using Zsh
      if [[ -d "$wt_path/vendor" ]]; then
        du_out="$(du -sk "$wt_path/vendor" 2>/dev/null)" || du_out="0"
        vendor_size="${du_out%%$'\t'*}"
        vendor_size=$((vendor_size * 1024))
      fi

      wt_saved=$((nm_size + vendor_size))

      if (( wt_saved > 0 )); then
        folder="${wt_path:t}"
        print -r -- "  ${C_CYAN}$repo_name${C_RESET} / ${C_MAGENTA}${folder#*--}${C_RESET}"
        print -r -- "    ${C_DIM}Inactive: ${age_days}d${C_RESET}"

        if (( nm_size > 0 )); then
          nm_human="$(_format_size_bytes $nm_size)"
          print -r -- "    ${C_DIM}node_modules:${C_RESET} ${C_YELLOW}$nm_human${C_RESET}"
        fi
        if (( vendor_size > 0 )); then
          v_human="$(_format_size_bytes $vendor_size)"
          print -r -- "    ${C_DIM}vendor:${C_RESET}       ${C_YELLOW}$v_human${C_RESET}"
        fi

        if [[ "$dry_run" != true ]]; then
          [[ -d "$wt_path/node_modules" ]] && rm -rf "$wt_path/node_modules"
          [[ -d "$wt_path/vendor" ]] && rm -rf "$wt_path/vendor"
        fi

        repo_saved=$((repo_saved + wt_saved))
        repo_cleaned=$((repo_cleaned + 1))
        print -r -- ""
      fi
    fi
  done

  REPLY="${repo_saved}|${repo_cleaned}"
}

# cmd_clean — Remove node_modules and vendor directories from inactive worktrees
cmd_clean() {
  local repo="${1:-}"
  local dry_run="${DRY_RUN:-false}"

  print -r -- ""
  print -r -- "${C_BOLD}Clean Inactive Worktrees${C_RESET}"
  print -r -- ""

  local inactive_days=30
  local total_saved=0
  local cleaned=0

  # Declare loop-scoped variables
  local repo_name total_human

  if [[ -n "$repo" ]]; then
    validate_name "$repo" "repository"
    _clean_process_repo "$repo" "$inactive_days" "$dry_run"
    total_saved="${REPLY%%|*}"
    cleaned="${REPLY##*|}"
  else
    # Process all repos
    for git_dir in "$HERD_ROOT"/*.git(N); do
      [[ -d "$git_dir" ]] || continue
      repo_name="${${git_dir:t}%.git}"
      _clean_process_repo "$repo_name" "$inactive_days" "$dry_run"
      total_saved=$((total_saved + ${REPLY%%|*}))
      cleaned=$((cleaned + ${REPLY##*|}))
    done
  fi

  if (( cleaned == 0 )); then
    ok "No inactive worktrees with cleanable dependencies found"
  else
    total_human="$(_format_size_bytes $total_saved)"
    if [[ "$dry_run" == true ]]; then
      info "Would clean ${C_BOLD}$cleaned${C_RESET} worktree(s), saving ${C_GREEN}$total_human${C_RESET}"
      dim "  Run without --dry-run to clean"
    else
      ok "Cleaned ${C_BOLD}$cleaned${C_RESET} worktree(s), saved ${C_GREEN}$total_human${C_RESET}"
      dim "  Reinstall with: npm ci / composer install"
    fi
  fi
  print -r -- ""
}

# Alias management
readonly GROVE_ALIASES_FILE="$HOME/.grove/aliases"


