#!/usr/bin/env zsh
# 10-interactive.sh - Interactive worktree creation wizard

# Interactive worktree creation
# Usage: interactive_add [repo]
interactive_add() {
  local initial_repo="${1:-}"

  # Ensure fzf is available
  if ! command -v fzf >/dev/null 2>&1; then
    die "Interactive mode requires fzf. Install with: brew install fzf"
  fi

  print -r -- ""
  print -r -- "${C_BOLD}🌳 Interactive Worktree Creation${C_RESET}"
  print -r -- ""

  # Step 1: Repository selection
  local repo="$initial_repo"
  if [[ -z "$repo" ]]; then
    print -r -- "${C_BOLD}Step 1/5:${C_RESET} Select repository"
    local repos; repos="$(list_repos)"
    [[ -n "$repos" ]] || die "No repositories found in $HERD_ROOT"

    repo="$(echo "$repos" | fzf --prompt="Repository: " --height=40% --reverse)"
    [[ -n "$repo" ]] || die "No repository selected"
  fi

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"
  load_repo_config "$git_dir"

  ok "Repository: ${C_CYAN}$repo${C_RESET}"
  print -r -- ""

  # Step 2: Base branch selection
  print -r -- "${C_BOLD}Step 2/5:${C_RESET} Select base branch"

  # Fetch first
  with_spinner "Fetching branches" git --git-dir="$git_dir" fetch --all --prune --quiet

  # Get remote branches for selection
  local branches; branches="$(git --git-dir="$git_dir" branch -r --format='%(refname:short)' 2>/dev/null | grep -v HEAD)"

  local base
  base="$(echo "$branches" | fzf --prompt="Base branch: " --height=40% --reverse --query="origin/staging")"
  [[ -n "$base" ]] || base="$DEFAULT_BASE"

  ok "Base: ${C_DIM}$base${C_RESET}"
  print -r -- ""

  # Step 3: Branch name input with live preview
  print -r -- "${C_BOLD}Step 3/5:${C_RESET} Enter new branch name"
  print -r -- "${C_DIM}  (e.g., feature/my-feature, bugfix/fix-123)${C_RESET}"
  print -r -- ""

  local branch=""
  while [[ -z "$branch" ]]; do
    print -n "  Branch name: "
    read -r branch

    if [[ -z "$branch" ]]; then
      warn "Branch name required"
      continue
    fi

    # Validate
    if ! validate_name "$branch" "branch" 2>/dev/null; then
      warn "Invalid branch name"
      branch=""
      continue
    fi

    # Check if already exists
    if git --git-dir="$git_dir" show-ref --quiet "refs/heads/$branch" 2>/dev/null; then
      warn "Branch already exists: $branch"
      branch=""
      continue
    fi
  done

  # Show preview
  local wt_path; wt_path="$(worktree_path_for "$repo" "$branch")"
  local app_url; app_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"

  print -r -- ""
  print -r -- "  ${C_DIM}Preview:${C_RESET}"
  print -r -- "    Path:     ${C_CYAN}$wt_path${C_RESET}"
  print -r -- "    URL:      ${C_BLUE}$app_url${C_RESET}"
  print -r -- "    Database: ${C_CYAN}$db_name${C_RESET}"
  print -r -- ""

  # Step 4: Template selection (optional)
  print -r -- "${C_BOLD}Step 4/5:${C_RESET} Select template ${C_DIM}(optional)${C_RESET}"

  local template=""
  local templates; templates="$(get_template_names)"

  if [[ -n "$templates" ]]; then
    # Add "none" option
    templates="(none)
$templates"

    template="$(echo "$templates" | fzf --prompt="Template: " --height=40% --reverse)"

    if [[ "$template" != "(none)" && -n "$template" ]]; then
      GROVE_TEMPLATE="$template"
      ok "Template: ${C_CYAN}$template${C_RESET}"
    else
      dim "  No template selected"
    fi
  else
    dim "  No templates available"
  fi
  print -r -- ""

  # Step 5: Confirmation
  print -r -- "${C_BOLD}Step 5/5:${C_RESET} Confirm"
  print -r -- ""
  print -r -- "  ${C_BOLD}Summary:${C_RESET}"
  print -r -- "    Repository: ${C_CYAN}$repo${C_RESET}"
  print -r -- "    Branch:     ${C_MAGENTA}$branch${C_RESET}"
  print -r -- "    Base:       ${C_DIM}$base${C_RESET}"
  print -r -- "    Path:       $wt_path"
  print -r -- "    URL:        ${C_BLUE}$app_url${C_RESET}"
  [[ -n "$GROVE_TEMPLATE" ]] && print -r -- "    Template:   ${C_CYAN}$GROVE_TEMPLATE${C_RESET}"
  print -r -- ""

  print -n "  ${C_GREEN}Create worktree? [Y/n]${C_RESET} "
  local response; read -r response

  if [[ "$response" =~ ^[Nn]$ ]]; then
    dim "Aborted"
    return 0
  fi

  print -r -- ""

  # Execute creation (call cmd_add with collected params)
  INTERACTIVE=false  # Disable interactive mode for actual creation
  cmd_add "$repo" "$branch" "$base"
}

# Interactive dashboard with quick actions
# Usage: interactive_dashboard
interactive_dashboard() {
  # Ensure fzf is available
  if ! command -v fzf >/dev/null 2>&1; then
    die "Interactive dashboard requires fzf. Install with: brew install fzf"
  fi

  print -r -- ""
  print -r -- "${C_BOLD}🌳 Interactive Dashboard${C_RESET}"
  print -r -- "${C_DIM}Select a worktree and press a key to perform an action${C_RESET}"
  print -r -- ""

  # Collect all worktrees across all repos
  local entries=()

  # Declare loop-scoped variables BEFORE the loop to avoid zsh local re-declaration bug
  local repo_name out wt_path branch line
  local result grade dirty_icon st age display_line

  for git_dir in "$HERD_ROOT"/*.git(N); do
    [[ -d "$git_dir" ]] || continue
    repo_name="${${git_dir:t}%.git}"

    out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || continue
    wt_path=""
    branch=""

    while IFS= read -r line; do
      if [[ "$line" == worktree\ * ]]; then
        wt_path="${line#worktree }"
      elif [[ "$line" == branch\ refs/heads/* ]]; then
        branch="${line#branch refs/heads/}"
      elif [[ -z "$line" && -n "$wt_path" && "$wt_path" != *.git && -n "$branch" && -d "$wt_path" ]]; then
        # Get health score
        result="$(calculate_health_score "$wt_path")" || result="F|0|error"
        grade="${result%%|*}"

        # Check dirty status
        dirty_icon=" "
        st="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || st=""
        [[ -n "$st" ]] && dirty_icon="◐"

        # Get age
        age="$(get_last_commit_age "$wt_path")" || age="?"

        # Format entry for fzf display
        # Format: repo | branch | grade | dirty | age | path
        display_line="$(printf "%-15s │ %-30s │ %s │ %s │ %-6s" \
          "${repo_name:0:15}" "${branch:0:30}" "$grade" "$dirty_icon" "$age")"

        entries+=("${display_line}|${repo_name}|${branch}|${wt_path}")
        wt_path=""
        branch=""
      fi
    done <<< "$out"

    # Handle last entry
    if [[ -n "$wt_path" && "$wt_path" != *.git && -n "$branch" && -d "$wt_path" ]]; then
      result="$(calculate_health_score "$wt_path")" || result="F|0|error"
      grade="${result%%|*}"
      dirty_icon=" "
      st="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || st=""
      [[ -n "$st" ]] && dirty_icon="◐"
      age="$(get_last_commit_age "$wt_path")" || age="?"
      display_line="$(printf "%-15s │ %-30s │ %s │ %s │ %-6s" \
        "${repo_name:0:15}" "${branch:0:30}" "$grade" "$dirty_icon" "$age")"
      entries+=("${display_line}|${repo_name}|${branch}|${wt_path}")
    fi
  done

  if (( ${#entries[@]} == 0 )); then
    dim "No worktrees found."
    dim "  Checked: $HERD_ROOT/*.git directories"
    return 0
  fi

  # Build header
  local header="REPO            │ BRANCH                         │ ⚕ │ Δ │ AGE
────────────────┼────────────────────────────────┼───┼───┼───────
Actions: [p]ull [s]ync [o]pen [c]ode [r]emove [i]nfo [Enter]=cd"

  # Run fzf with key bindings
  local selection
  local fzf_opts=(
    --header="$header"
    --prompt="Select worktree: "
    --reverse
    --ansi
    --expect='p,s,o,c,r,i,enter'
    --preview-window=hidden
    --bind='ctrl-r:reload(echo "REFRESH")'
  )

  # Only use --height if we have a proper terminal
  if [[ -t 0 && -t 1 ]]; then
    fzf_opts+=(--height=80%)
  fi

  selection="$(printf '%s\n' "${entries[@]%%|*}" | fzf "${fzf_opts[@]}")"

  [[ -n "$selection" ]] || { dim "No selection made"; return 0; }

  # Parse selection - first line is the key pressed, second is the item
  local key_pressed; key_pressed="$(print -r -- "$selection" | head -1)"
  local selected_display; selected_display="$(print -r -- "$selection" | tail -1)"

  [[ -n "$selected_display" ]] || { dim "No selection made"; return 0; }

  # Find the full entry to get repo, branch, path
  local full_entry=""
  for entry in "${entries[@]}"; do
    if [[ "${entry%%|*}" == "$selected_display" ]]; then
      full_entry="$entry"
      break
    fi
  done

  [[ -n "$full_entry" ]] || { dim "Selection not found"; return 0; }

  # Parse the entry: display|repo|branch|path
  local rest="${full_entry#*|}"
  local repo="${rest%%|*}"
  rest="${rest#*|}"
  local branch="${rest%%|*}"
  local wt_path="${rest#*|}"

  print -r -- ""
  info "Selected: ${C_CYAN}$repo${C_RESET} / ${C_MAGENTA}$branch${C_RESET}"

  # Execute action based on key pressed
  case "$key_pressed" in
    p)
      print -r -- ""
      info "Pulling ${C_MAGENTA}$branch${C_RESET}..."
      cmd_pull "$repo" "$branch"
      ;;
    s)
      print -r -- ""
      info "Syncing ${C_MAGENTA}$branch${C_RESET} with $DEFAULT_BASE..."
      cmd_sync "$repo" "$branch"
      ;;
    o)
      info "Opening ${C_MAGENTA}$branch${C_RESET} in browser..."
      cmd_open "$repo" "$branch"
      ;;
    c)
      info "Opening ${C_MAGENTA}$branch${C_RESET} in editor..."
      cmd_code "$repo" "$branch"
      ;;
    r)
      print -r -- ""
      warn "Remove worktree ${C_MAGENTA}$branch${C_RESET}?"
      print -n "${C_YELLOW}Confirm [y/N]:${C_RESET} "
      local confirm
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        cmd_rm "$repo" "$branch"
      else
        dim "Cancelled"
      fi
      ;;
    i)
      print -r -- ""
      cmd_info "$repo" "$branch"
      ;;
    enter|"")
      # Print path for cd
      print -r -- ""
      print -r -- "Path: ${C_CYAN}$wt_path${C_RESET}"
      print -r -- ""
      dim "To change directory, run:"
      print -r -- "  cd \"$wt_path\""
      ;;
    *)
      dim "Unknown action: $key_pressed"
      ;;
  esac
}

# Select a worktree from a repo using fzf
select_worktree() {
  local git_dir="$1"
  local prompt="${2:-Select worktree: }"

  if ! command -v fzf >/dev/null 2>&1; then
    return 1
  fi

  local entries=()
  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || return 1
  local wt_path="" branch=""

  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      wt_path="${line#worktree }"
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      branch="${line#branch refs/heads/}"
    elif [[ -z "$line" && -n "$wt_path" && "$wt_path" != *.git && -n "$branch" ]]; then
      entries+=("$branch")
      wt_path=""
      branch=""
    fi
  done <<< "$out"

  # Handle last entry
  if [[ -n "$wt_path" && "$wt_path" != *.git && -n "$branch" ]]; then
    entries+=("$branch")
  fi

  (( ${#entries[@]} == 0 )) && return 1

  printf '%s\n' "${entries[@]}" | fzf --prompt="$prompt" --height=40% --reverse
}
