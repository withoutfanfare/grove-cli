#!/usr/bin/env zsh
# 04-git.sh - Git operations and repository helpers

# Git result cache (cleared between commands)
typeset -gA _GROVE_GIT_CACHE
typeset -gA _GROVE_STATUS_CACHE

# Fetch cache configuration
GROVE_FETCH_CACHE_TTL="${GROVE_FETCH_CACHE_TTL:-30}"  # 30 seconds default
GROVE_FETCH_CACHE_DIR="${TMPDIR:-/tmp}/grove-fetch-cache"

# Get fetch cache file path for a repo
_fetch_cache_file() {
  local git_dir="$1"
  # Create hash of git dir path for unique cache file
  local hash="${git_dir:t}"  # Use basename for simplicity
  hash="${hash//[^a-zA-Z0-9_-]/_}"
  print -r -- "$GROVE_FETCH_CACHE_DIR/$hash"
}

# Last computed fetch cache age (set by _fetch_cache_valid for reuse)
typeset -g _FETCH_CACHE_AGE=0

# Check if fetch cache is valid (not expired)
_fetch_cache_valid() {
  local cache_file="$1"
  [[ -f "$cache_file" ]] || return 1

  local cache_time now
  cache_time="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)" || return 1
  now="$(_get_now)"
  _FETCH_CACHE_AGE=$((now - cache_time))

  (( _FETCH_CACHE_AGE < GROVE_FETCH_CACHE_TTL ))
}

# cached_fetch — Run git fetch, skipping if recently fetched within TTL window
cached_fetch() {
  local git_dir="$1"
  shift
  local fetch_args=("$@")

  # Skip caching if TTL is 0
  if (( GROVE_FETCH_CACHE_TTL <= 0 )); then
    git --git-dir="$git_dir" fetch "${fetch_args[@]}" 2>/dev/null
    return
  fi

  mkdir -p "$GROVE_FETCH_CACHE_DIR" 2>/dev/null

  local cache_file
  cache_file="$(_fetch_cache_file "$git_dir")"

  if _fetch_cache_valid "$cache_file"; then
    dim "(using cached fetch, ${_FETCH_CACHE_AGE}s old)"
    return 0
  fi

  if git --git-dir="$git_dir" fetch "${fetch_args[@]}" 2>/dev/null; then
    touch "$cache_file"
    return 0
  fi
  return 1
}

# force_fetch — Run git fetch, bypassing the TTL cache
force_fetch() {
  local git_dir="$1"
  shift

  local cache_file
  cache_file="$(_fetch_cache_file "$git_dir")"
  rm -f "$cache_file" 2>/dev/null

  git --git-dir="$git_dir" fetch "$@"
}

# clear_fetch_cache — Remove all fetch cache files and recreate the directory
clear_fetch_cache() {
  rm -rf "$GROVE_FETCH_CACHE_DIR" 2>/dev/null
  mkdir -p "$GROVE_FETCH_CACHE_DIR" 2>/dev/null
}

# clear_git_cache — Reset in-memory git and status caches (call at command start)
clear_git_cache() {
  _GROVE_GIT_CACHE=()
  _GROVE_STATUS_CACHE=()
}

# iterate_worktrees — Call a callback(path, branch) for each worktree in a repo
iterate_worktrees() {
  local git_dir="$1" callback="$2"
  local wt_path="" wt_branch="" line=""

  local output=""
  output="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || return 1

  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        wt_path="${line#worktree }"
        ;;
      "branch "*)
        wt_branch="${line#branch refs/heads/}"
        ;;
      "")
        if [[ -n "$wt_path" && -n "$wt_branch" && "$wt_path" != *.git ]]; then
          "$callback" "$wt_path" "$wt_branch"
        fi
        wt_path=""
        wt_branch=""
        ;;
    esac
  done <<< "$output"

  # Handle last entry (if output doesn't end with blank line)
  if [[ -n "$wt_path" && -n "$wt_branch" && "$wt_path" != *.git ]]; then
    "$callback" "$wt_path" "$wt_branch"
  fi
}

# collect_worktree_statuses — Gather SHA, dirty, ahead/behind for all worktrees into cache
collect_worktree_statuses() {
  local git_dir="$1"
  _GROVE_STATUS_CACHE=()

  # Callback that gathers status for a single worktree
  _collect_status_cb() {
    local wt_path="$1"
    # Verify the worktree has a .git reference (file or directory)
    [[ -d "$wt_path/.git" || -f "$wt_path/.git" ]] || return 0

    local wt_sha wt_dirty wt_ahead wt_behind wt_timestamp wt_counts
    wt_sha="$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null)" || wt_sha="unknown"

    if git -C "$wt_path" diff --quiet HEAD 2>/dev/null && \
       git -C "$wt_path" diff --cached --quiet HEAD 2>/dev/null; then
      wt_dirty="clean"
    else
      wt_dirty="dirty"
    fi

    wt_counts="$(git -C "$wt_path" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)" || wt_counts="0	0"
    wt_ahead="${wt_counts%%	*}"
    wt_behind="${wt_counts##*	}"

    wt_timestamp="$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null)" || wt_timestamp="0"

    _GROVE_STATUS_CACHE[$wt_path]="$wt_sha|$wt_dirty|$wt_ahead|$wt_behind|$wt_timestamp"
  }

  iterate_worktrees "$git_dir" _collect_status_cb
}

# get_cached_status — Retrieve a single status field from the worktree cache
get_cached_status() {
  local wt_path="$1"
  local field="$2"

  local cached="${_GROVE_STATUS_CACHE[$wt_path]:-}"
  [[ -z "$cached" ]] && return 1

  # Parse using parameter expansion (more reliable than IFS splitting)
  local rest="$cached"
  local f_sha="${rest%%|*}"; rest="${rest#*|}"
  local f_dirty="${rest%%|*}"; rest="${rest#*|}"
  local f_ahead="${rest%%|*}"; rest="${rest#*|}"
  local f_behind="${rest%%|*}"; rest="${rest#*|}"
  local f_timestamp="$rest"

  case "$field" in
    sha)       print -r -- "$f_sha" ;;
    dirty)     print -r -- "$f_dirty" ;;
    ahead)     print -r -- "$f_ahead" ;;
    behind)    print -r -- "$f_behind" ;;
    timestamp) print -r -- "$f_timestamp" ;;
    all)       print -r -- "$cached" ;;
  esac
}

# has_cached_status — Return 0 if worktree status cache has data for the given path
has_cached_status() {
  local wt_path="$1"
  [[ -n "${_GROVE_STATUS_CACHE[$wt_path]:-}" ]]
}

# ensure_bare_repo — Exit with REPO_NOT_FOUND error if bare repo directory is missing
ensure_bare_repo() {
  local git_dir="$1"
  [[ -d "$git_dir" ]] || error_exit "REPO_NOT_FOUND" "Bare repo not found at '$git_dir'" 3
}

# ensure_worktree_config — Create config.worktree with core.bare=false if extensions.worktreeConfig is enabled
ensure_worktree_config() {
  local git_dir="$1"
  local wt_path="$2"

  # Only needed when extensions.worktreeConfig is enabled
  local worktree_config
  worktree_config="$(git --git-dir="$git_dir" config --get extensions.worktreeConfig 2>/dev/null || true)"
  [[ "$worktree_config" == "true" ]] || return 0

  # Resolve the worktree metadata directory inside the bare repo
  local wt_name="${wt_path:t}"
  local wt_config_file="$git_dir/worktrees/$wt_name/config.worktree"

  # Don't overwrite if it already exists
  if [[ -f "$wt_config_file" ]]; then
    return 0
  fi

  # Create config.worktree with core.bare=false so git recognises the worktree
  printf '[core]\n\tbare = false\n' > "$wt_config_file"
  dim "  Created config.worktree for worktree extensions support"
}

# ensure_fetch_refspec — Add wildcard fetch refspec if missing from remote.origin.fetch
ensure_fetch_refspec() {
  local git_dir="$1"
  local has_wildcard=false

  # Check if wildcard refspec exists
  while IFS= read -r refspec; do
    if [[ "$refspec" == "+refs/heads/*:refs/remotes/origin/*" ]]; then
      has_wildcard=true
      break
    fi
  done < <(git --git-dir="$git_dir" config --get-all remote.origin.fetch 2>/dev/null)

  if [[ "$has_wildcard" == false ]]; then
    dim "  Fixing fetch refspec to include all branches..."
    git --git-dir="$git_dir" config --add remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  fi
}

# remote_branch_exists — Return 0 if branch exists on the remote origin
remote_branch_exists() {
  local git_dir="$1"
  local branch="$2"

  # Strip origin/ prefix if present
  branch="${branch#origin/}"

  # Validate branch name for security
  validate_git_ref "$branch" "branch"

  # Use ls-remote to check directly on remote (most reliable)
  GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git --git-dir="$git_dir" ls-remote --heads origin "$branch" 2>/dev/null | grep -q "refs/heads/$branch"
}

# list_repos — Print all repository names found in HERD_ROOT (one per line)
list_repos() {
  for dir in "$HERD_ROOT"/*.git(N); do
    [[ -d "$dir" ]] && print -r -- "${${dir:t}%.git}"
  done
}

# list_worktree_branches — Print active worktree branch names for a repo (one per line)
list_worktree_branches() {
  local repo="$1"
  local git_dir; git_dir="$(git_dir_for "$repo")"
  [[ -d "$git_dir" ]] || return 0

  # Callback that prints just the branch name
  _list_branches_cb() { print -r -- "$2"; }

  iterate_worktrees "$git_dir" _list_branches_cb
}

# select_branch_fzf — Interactively select a worktree branch using fzf
select_branch_fzf() {
  local repo="$1" prompt="${2:-Select branch}"
  local git_dir; git_dir="$(git_dir_for "$repo")"

  if ! command -v fzf >/dev/null 2>&1; then
    die "fzf not installed. Install with: brew install fzf"
  fi

  local branches; branches="$(list_worktree_branches "$repo")"
  [[ -n "$branches" ]] || die "No worktrees found for $repo"

  print -r -- "$branches" | fzf --prompt="$prompt: " --height=40% --reverse
}

# select_repo_fzf — Interactively select a repository using fzf
select_repo_fzf() {
  local prompt="${1:-Select repository}"

  if ! command -v fzf >/dev/null 2>&1; then
    die "fzf not installed. Install with: brew install fzf"
  fi

  local repos; repos="$(list_repos)"
  [[ -n "$repos" ]] || die "No repositories found in $HERD_ROOT"

  print -r -- "$repos" | fzf --prompt="$prompt: " --height=40% --reverse
}

# get_ahead_behind — Print "ahead behind" commit counts relative to a base ref
get_ahead_behind() {
  local wt_path="$1" base="${2:-origin/staging}"
  local ahead=0 behind=0

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  if git -C "$wt_path" rev-parse --verify "$base" >/dev/null 2>&1; then
    local counts; counts="$(git -C "$wt_path" rev-list --left-right --count HEAD..."$base" 2>/dev/null)" || counts="0	0"
    ahead="${counts%%	*}"
    behind="${counts##*	}"
  fi

  print -r -- "$ahead $behind"
}

# worktree_base_for — Read worktree-local base ref (grove.base config), with fallback
worktree_base_for() {
  local wt_path="$1"
  local fallback="${2:-$DEFAULT_BASE}"

  local base=""
  base="$(git -C "$wt_path" config --local --get grove.base 2>/dev/null || true)"
  [[ -n "$base" ]] || base="$fallback"

  print -r -- "$base"
}

# set_worktree_base — Save base ref in worktree-local git config (grove.base)
set_worktree_base() {
  local wt_path="$1"
  local base="$2"

  [[ -n "$base" ]] || return 0

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  git -C "$wt_path" config --local grove.base "$base" 2>/dev/null || true
}

# get_last_commit_age — Return human-readable age of latest commit (e.g. "3d", "2w")
get_last_commit_age() {
  local wt_path="$1"
  local now epoch_seconds age_seconds age_days

  now="$(_get_now)"
  epoch_seconds="$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null)" || { print -r -- "?"; return 0; }

  # Handle future timestamps (clock skew, timezone issues)
  if (( epoch_seconds > now )); then
    print -r -- "<1h"
    return 0
  fi

  (( age_seconds = now - epoch_seconds ))

  # Bounds check to prevent overflow (max ~68 years for safety)
  # If age exceeds 2^31 seconds (~68 years), cap it
  if (( age_seconds > 2147483647 )); then
    print -r -- ">68y"
    return 0
  fi

  (( age_days = age_seconds / 86400 ))

  # Additional sanity check on days (max 100 years)
  if (( age_days > 36500 )); then
    print -r -- ">100y"
    return 0
  fi

  if (( age_days == 0 )); then
    local hours=$(( age_seconds / 3600 ))
    if (( hours == 0 )); then
      print -r -- "<1h"
    else
      print -r -- "${hours}h"
    fi
  elif (( age_days < 7 )); then
    print -r -- "${age_days}d"
  elif (( age_days < 30 )); then
    print -r -- "$(( age_days / 7 ))w"
  elif (( age_days < 365 )); then
    print -r -- "$(( age_days / 30 ))mo"
  else
    print -r -- "$(( age_days / 365 ))y"
  fi
}

# get_commit_age_days — Return age of latest commit in integer days (capped at 36500)
get_commit_age_days() {
  local wt_path="$1"
  local now epoch_seconds age_seconds

  now="$(_get_now)"
  epoch_seconds="$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null)" || { print -r -- "0"; return 0; }

  # Handle future timestamps (clock skew, timezone issues)
  if (( epoch_seconds > now )); then
    print -r -- "0"
    return 0
  fi

  (( age_seconds = now - epoch_seconds ))

  # Bounds check to prevent overflow (max 100 years = 36500 days)
  local age_days=$(( age_seconds / 86400 ))
  if (( age_days > 36500 )); then
    print -r -- "36500"  # Cap at 100 years
    return 0
  fi

  print -r -- "$age_days"
}

# is_branch_merged — Return 0 if worktree HEAD is an ancestor of the base ref
is_branch_merged() {
  local wt_path="$1" base="${2:-origin/staging}"
  local branch_head base_head

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  branch_head="$(git -C "$wt_path" rev-parse HEAD 2>/dev/null)" || return 1

  # Check if the base branch contains this commit
  if git -C "$wt_path" merge-base --is-ancestor "$branch_head" "$base" 2>/dev/null; then
    return 0
  fi
  return 1
}

# get_last_accessed_iso — Return filesystem mtime as ISO 8601 timestamp
get_last_accessed_iso() {
  local wt_path="$1"
  local mtime

  # Get modification time (epoch seconds) using OS-specific stat format
  case "$GROVE_OS" in
    Darwin)
      mtime="$(stat -f '%m' "$wt_path" 2>/dev/null || echo "")"
      ;;
    *)
      mtime="$(stat -c '%Y' "$wt_path" 2>/dev/null || echo "")"
      ;;
  esac

  if [[ -z "$mtime" || ! "$mtime" =~ ^[0-9]+$ ]]; then
    print -r -- ""
    return 0
  fi

  # Convert epoch to ISO 8601 using OS-specific date format
  local iso_date
  case "$GROVE_OS" in
    Darwin)
      iso_date="$(date -r "$mtime" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || iso_date=""
      ;;
    *)
      iso_date="$(date -d "@$mtime" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || iso_date=""
      ;;
  esac

  print -r -- "$iso_date"
}

# get_commits_behind — Return number of commits HEAD is behind a base ref
get_commits_behind() {
  local wt_path="$1" base="${2:-origin/staging}"
  local behind=0

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  if git -C "$wt_path" rev-parse --verify "$base" >/dev/null 2>&1; then
    behind="$(git -C "$wt_path" rev-list --count HEAD.."$base" 2>/dev/null)" || behind=0
  fi

  print -r -- "$behind"
}

# is_branch_stale — Print "true" if branch is more than threshold commits behind base
is_branch_stale() {
  local wt_path="$1" base="${2:-origin/staging}" threshold="${3:-$GROVE_STALE_THRESHOLD}"
  local behind

  behind="$(get_commits_behind "$wt_path" "$base")"

  if (( behind > threshold )); then
    print -r -- "true"
  else
    print -r -- "false"
  fi
}

# collect_worktrees — Populate a named array with "path|branch" entries for all worktrees
collect_worktrees() {
  local git_dir="$1"
  local _cw_target="$2"

  # Validate target is a safe variable name (alphanumeric and underscores only)
  if [[ ! "$_cw_target" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    warn "collect_worktrees: invalid target variable name: '$_cw_target'"
    return 1
  fi

  eval "${_cw_target}=()"

  # Callback that appends "path|branch" to the target array
  _collect_wt_cb() { eval "${_cw_target}+=(\"\$1|\$2\")"; }

  iterate_worktrees "$git_dir" _collect_wt_cb
}

# check_worktree_mismatches — Warn about worktrees whose dir names don't match branch slugs
check_worktree_mismatches() {
  local git_dir="$1"
  # Derive repo name from git_dir (strip trailing .git and get basename)
  local repo="${${git_dir:t}%.git}"
  local mismatch_count=0
  local _cwm_worktrees=()
  collect_worktrees "$git_dir" _cwm_worktrees

  local wt_entry wt_path branch match_result expected_slug
  for wt_entry in "${_cwm_worktrees[@]}"; do
    wt_path="${wt_entry%%|*}"
    branch="${wt_entry##*|}"

    match_result="$(check_branch_directory_match "$wt_path" "$branch" "$repo")"
    if [[ "$match_result" == mismatch\|* ]]; then
      expected_slug="${match_result#mismatch|}"
      if [[ $mismatch_count -eq 0 ]]; then
        warn "Branch/directory mismatches found:"
      fi
      print -r -- "  ${C_YELLOW}!${C_RESET} ${wt_path:t} (branch: $branch, expected dir slug: $expected_slug)"
      mismatch_count=$((mismatch_count + 1))
    fi
  done

  # Cap at 254 to stay within valid exit code range (255 is reserved)
  (( mismatch_count > 254 )) && mismatch_count=254
  return $mismatch_count
}
