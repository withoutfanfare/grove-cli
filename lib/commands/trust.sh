#!/usr/bin/env zsh
# Read-only previews share the removal authority used immediately before rm.
cmd_prune_plan() {
  local repo="$1" git_dir
  validate_name "$repo" repository
  git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"
  load_repo_config "$git_dir"
  bundled_prune_plan plan "$repo" "$git_dir" "$DEFAULT_BASE" "$PROTECTED_BRANCHES"
}

cmd_prune_execute() {
  local repo="$1" plan_file="$2" git_dir
  validate_name "$repo" repository
  [[ -f "$plan_file" ]] || error_exit INVALID_INPUT 'Confirmed plan is missing' 2
  git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"
  load_repo_config "$git_dir"
  bundled_prune_plan execute "$repo" "$git_dir" "$DEFAULT_BASE" "$PROTECTED_BRANCHES" "$plan_file"
}

cmd_removal_check() {
  local repo="${1:-}" branch="${2:-}" wt_path git_dir verdict=clear message='' current_link db_name=''
  validate_name "$repo" repository
  [[ -n "${RM_PATH:-}" ]] || validate_name "$branch" branch
  git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"
  load_repo_config "$git_dir"
  if [[ -n "${RM_PATH:-}" ]]; then
    wt_path="$(resolve_detached_worktree_path "$repo" "$RM_PATH")" || error_exit WORKTREE_NOT_FOUND "No detached worktree registered at '$RM_PATH'" 3
  else
    wt_path="$(resolve_worktree_path "$repo" "$branch")" || error_exit WORKTREE_NOT_FOUND "no matching worktree registered for '$repo' branch '$branch'" 3
  fi
  local -a check_rows=()
  if ! removal_gate "$wt_path"; then
    verdict=blocked; message="$REPLY"
    [[ "$message" == *Unknown* || "$message" == *'cannot be ruled out'* ]] && verdict=unknown
  fi
  json_escape "$message"; local gate_message="$REPLY"
  check_rows+=("{\"id\":\"removal_gate\",\"label\":\"Removal gate\",\"state\":\"$verdict\",\"message\":\"$gate_message\"}")
  local selected_gate helper_json detail_rows
  selected_gate="$(removal_check_binary)" || selected_gate=''
  if [[ "$selected_gate" == bundled_removal_check ]]; then
    helper_json="$(bundled_removal_check "$wt_path" --json)" || true
    detail_rows="$(print -r -- "$helper_json" | python3 -I -c 'import json,sys;print(",".join(json.dumps(c) for c in json.load(sys.stdin)["checks"]))')" || detail_rows=''
    if [[ -n "$detail_rows" ]]; then
      check_rows+=("$detail_rows")
      local detailed_verdict
      detailed_verdict="$(print -r -- "$helper_json" | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["verdict"])')" || detailed_verdict=unknown
      [[ "$detailed_verdict" != clear ]] && verdict="$detailed_verdict"
    else
      verdict=unknown
    fi
  fi
  local site_state=clear protection_state=clear database_state=clear
  local site_message="No current-site link selects this worktree"
  local protection_message="Branch protection permits this request"
  local database_message="Database will be kept"
  if current_link="$(worktree_current_link_for "$wt_path")"; then verdict=blocked; site_state=blocked; site_message="Current site selects this worktree; switch it first"; message+=$'\n'"Worktree is selected by '$current_link'; switch the live site first"; fi
  if is_protected_branch "$branch" && [[ "${FORCE:-false}" != true && "${ALLOW_PROTECTED:-false}" != true ]]; then verdict=blocked; protection_state=blocked; protection_message="Protected branch requires typed confirmation"; message+=$'\n'"Protected branch requires individual typed confirmation"; fi
  # An unidentified database only matters when a drop is asked for: a forced removal never touches it.
  if ! db_name="$(db_name_for "$repo" "$branch" "$wt_path")"; then
    if [[ "${DROP_DB:-false}" == true ]]; then [[ "$verdict" == blocked ]] || verdict=unknown; database_state=unknown; database_message="Database identity is unknown"; message+=$'\n'"Database identity is unknown; removal cannot be approved"
    else database_message="Database could not be identified; none will be backed up or dropped"; fi
  fi
  if [[ "${DROP_DB:-false}" == true && "$database_state" == clear ]] && ! worktree_database_is_private "$repo" "$wt_path" "$db_name"; then verdict=blocked; database_state=blocked; database_message="$REPLY"; message+=$'\n'"$REPLY"; fi
  [[ -n "$message" ]] || message='Removal gate completed; local remote-tracking refs were checked, no live fetch was performed. Execution rechecks before removal.'
  json_escape "$repo"; local jr="$REPLY"
  json_escape "$branch"; local jb="$REPLY"
  json_escape "$wt_path"; local jp="$REPLY"
  json_escape "$message"; local jm="$REPLY"
  json_escape "$db_name"; local jd="$REPLY"
  if [[ "${DROP_DB:-false}" == true && "$database_state" == clear ]]; then database_message="Database '$db_name' has verified ownership; post-removal hooks will be asked to drop it"; fi
  json_escape "$site_message"; local js="$REPLY"
  json_escape "$protection_message"; local jprotection="$REPLY"
  json_escape "$database_message"; local jdatabase="$REPLY"
  check_rows+=("{\"id\":\"current_site\",\"label\":\"Current site selection\",\"state\":\"$site_state\",\"message\":\"$js\"}")
  check_rows+=("{\"id\":\"protected_branch\",\"label\":\"Branch protection\",\"state\":\"$protection_state\",\"message\":\"$jprotection\"}")
  check_rows+=("{\"id\":\"database\",\"label\":\"Database identity and consequences\",\"state\":\"$database_state\",\"message\":\"$jdatabase\"}")
  local checks_json="[${(j:,:)check_rows}]"
  local checked_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  print -r -- "{\"success\":true,\"data\":{\"repo\":\"$jr\",\"branch\":\"$jb\",\"path\":\"$jp\",\"verdict\":\"$verdict\",\"checked_at\":\"$checked_at\",\"checks\":$checks_json,\"database\":{\"name\":\"$jd\",\"will_drop\":${DROP_DB:-false}}}}"
}
