#!/usr/bin/env zsh
# 03-paths.sh - Path resolution, worktree detection, URL generation

# slugify_branch — Convert branch name to filesystem-safe slug (sets REPLY)
slugify_branch() {
  REPLY="${1//\//-}"
}

# site_name_for — Generate SSL-safe site name (≤59 chars) for a worktree domain
site_name_for() {
  local repo="$1"
  local branch="$2"
  local max_length="${3:-59}"  # Default 59 for SSL compatibility

  local site_name

  # For main branches, use the repo name
  if [[ "$branch" == "staging" || "$branch" == "main" || "$branch" == "master" ]]; then
    site_name="$repo"
  else
    # Extract just the feature name (strips prefixes like feature/, bugfix/, etc.)
    local feature_name
    # Inline extract_feature_name: extract last segment after /
    if [[ "$branch" == */* ]]; then
      feature_name="${branch##*/}"
    else
      feature_name="$branch"
    fi
    slugify_branch "$feature_name"
    site_name="$REPLY"
  fi

  # If within limit, return as-is
  if (( ${#site_name} <= max_length )); then
    print -r -- "$site_name"
    return 0
  fi

  # Need to truncate - append hash for uniqueness
  # Hash is 6 chars, separator is 1 char = 7 chars reserved
  slugify_branch "$branch"
  local full_slug="$REPLY"
  local hash_suffix; hash_suffix="$(print -r -- "$full_slug" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-6)"
  local suffix_len=7  # "-" + 6-char hash
  local available=$(( max_length - suffix_len ))

  local truncated="${site_name:0:$available}"
  # Remove trailing dash if present
  truncated="${truncated%-}"
  print -r -- "${truncated}-${hash_suffix}"
}

# extract_feature_name — Return last path segment of a branch name
extract_feature_name() {
  local branch="$1"
  local result="$branch"

  # If branch contains a slash, extract the last segment
  if [[ "$branch" == */* ]]; then
    result="${branch##*/}"
  fi

  print -r -- "$result"
}

# check_branch_directory_match — Compare worktree dir name against branch slug
check_branch_directory_match() {
  local wt_path="$1"
  local actual_branch="$2"
  local repo="$3"

  # Skip bare repo and main worktree (e.g., scooda for staging)
  local folder="${wt_path:t}"
  if [[ "$folder" != *"--"* ]]; then
    print -r -- "skip"
    return 0
  fi

  # Extract the slug from directory name (part after repo--)
  local dir_slug="${folder#*--}"

  # Slugify the actual branch
  slugify_branch "$actual_branch"
  local branch_slug="$REPLY"

  if [[ "$dir_slug" != "$branch_slug" ]]; then
    print -r -- "mismatch|$branch_slug"
  else
    print -r -- "ok"
  fi
}

# lookup_worktree_path — Find actual worktree path for a branch from git records
lookup_worktree_path() {
  local repo="$1"
  local branch="$2"
  local git_dir; git_dir="$(git_dir_for "$repo")"

  [[ -d "$git_dir" ]] || return 0

  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || return 0

  local path="" current_branch="" line=""
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      if [[ "$current_branch" == "$branch" && -n "$path" ]]; then
        print -r -- "$path"
        return 0
      fi
      path=""
      current_branch=""
      continue
    fi
    [[ "$line" == worktree\ * ]] && path="${line#worktree }"
    [[ "$line" == branch\ refs/heads/* ]] && current_branch="${line#branch refs/heads/}"
  done <<< "$out"

  # Handle last entry (no trailing blank line)
  if [[ "$current_branch" == "$branch" && -n "$path" ]]; then
    print -r -- "$path"
    return 0
  fi

  return 0
}

# resolve_worktree_path — Get worktree path via git lookup, falling back to computed path
resolve_worktree_path() {
  local repo="$1"
  local branch="$2"

  # First try to look up actual path from git
  local actual_path; actual_path="$(lookup_worktree_path "$repo" "$branch")"
  if [[ -n "$actual_path" ]]; then
    print -r -- "$actual_path"
    return 0
  fi

  # Fall back to computed path (for new worktrees)
  worktree_path_for "$repo" "$branch"
}

# detect_current_worktree — Auto-detect repo and branch from cwd (sets DETECTED_REPO/BRANCH)
detect_current_worktree() {
  DETECTED_REPO=""
  DETECTED_BRANCH=""

  # Check if we're in a git directory
  local git_dir; git_dir="$(git rev-parse --git-dir 2>/dev/null)" || return 1

  # Get the worktree root
  local wt_root; wt_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1

  # Check if the worktree is under HERD_ROOT
  [[ "$wt_root" == "$HERD_ROOT"/* ]] || return 1

  # Get the folder name and parent
  local folder="${wt_root:t}"
  local parent="${wt_root:h}"
  local parent_name="${parent:t}"

  # Try to find the bare repo by checking the git-dir path
  # For worktrees, git-dir is like: /path/to/repo.git/worktrees/worktree-name
  if [[ "$git_dir" == *"/worktrees/"* ]]; then
    # Extract bare repo path
    local bare_repo="${git_dir%/worktrees/*}"
    DETECTED_REPO="${${bare_repo:t}%.git}"
  # New structure: {repo}-worktrees/{folder}
  elif [[ "$parent_name" == *"-worktrees" ]]; then
    DETECTED_REPO="${parent_name%-worktrees}"
  # Legacy: folder matches repo name (main worktree)
  elif [[ -d "$HERD_ROOT/${folder}.git" ]]; then
    DETECTED_REPO="$folder"
  # Legacy: extract repo from folder name (repo--slug pattern)
  elif [[ "$folder" == *"--"* ]]; then
    DETECTED_REPO="${folder%%--*}"
  else
    return 1
  fi

  # Verify the bare repo exists
  [[ -d "$HERD_ROOT/${DETECTED_REPO}.git" ]] || return 1

  # Get the current branch
  DETECTED_BRANCH="$(git branch --show-current 2>/dev/null)" || return 1
  [[ -n "$DETECTED_BRANCH" ]] || return 1

  return 0
}

# require_repo — Return repo name from argument or auto-detection
require_repo() {
  local repo="$1"
  if [[ -z "$repo" ]]; then
    if detect_current_worktree; then
      print -r -- "$DETECTED_REPO"
      return 0
    fi
    return 1
  fi
  print -r -- "$repo"
}

# require_repo_branch — Return "repo branch" from arguments or auto-detection
require_repo_branch() {
  local repo="$1"
  local branch="$2"

  if [[ -z "$repo" ]]; then
    if detect_current_worktree; then
      print -r -- "$DETECTED_REPO $DETECTED_BRANCH"
      return 0
    fi
    return 1
  fi

  if [[ -z "$branch" ]]; then
    # Repo provided but no branch - use fzf or fail
    return 1
  fi

  print -r -- "$repo $branch"
}

# git_dir_for — Return absolute path to the bare repo directory for a repository
git_dir_for() {
  local repo="$1"
  print -r -- "$HERD_ROOT/${repo}.git"
}

# worktree_path_for — Compute expected worktree directory path for a repo/branch pair
worktree_path_for() {
  local repo="$1"
  local branch="$2"
  local site_name; site_name="$(site_name_for "$repo" "$branch")"
  print -r -- "$HERD_ROOT/${repo}-worktrees/${site_name}"
}

# url_for — Generate the local development URL for a worktree
url_for() {
  local repo="$1"
  local branch="$2"
  local site_name; site_name="$(site_name_for "$repo" "$branch")"

  # Build URL: [subdomain.]site-name.test
  # Site name is the folder name under {repo}-worktrees/
  if [[ -n "$GROVE_URL_SUBDOMAIN" ]]; then
    print -r -- "https://${GROVE_URL_SUBDOMAIN}.${site_name}.test"
  else
    print -r -- "https://${site_name}.test"
  fi
}

# resolve_recent_shortcut — Resolve @N shortcut to branch name by modification time
resolve_recent_shortcut() {
  local repo="$1"
  local shortcut="$2"
  local git_dir; git_dir="$(git_dir_for "$repo")"

  [[ -d "$git_dir" ]] || return 1

  # Extract index from shortcut (e.g., @1 -> 1)
  local idx="${shortcut#@}"
  [[ "$idx" =~ ^[0-9]+$ ]] || return 1
  (( idx > 0 )) || return 1

  # Collect worktrees with their modification times
  local entries=()
  local out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || return 1

  # Declare loop variables outside to avoid zsh re-declaration output
  local wt_path="" branch="" line="" mtime=""
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      if [[ -n "$wt_path" && -n "$branch" && "$wt_path" != *.git && -d "$wt_path" ]]; then
        mtime="$(stat -f '%m' "$wt_path" 2>/dev/null || stat -c '%Y' "$wt_path" 2>/dev/null || echo 0)"
        entries+=("$mtime|$branch")
      fi
      wt_path=""
      branch=""
      continue
    fi
    [[ "$line" == worktree\ * ]] && wt_path="${line#worktree }"
    [[ "$line" == branch\ refs/heads/* ]] && branch="${line#branch refs/heads/}"
  done <<< "$out"

  # Handle last entry
  if [[ -n "$wt_path" && -n "$branch" && "$wt_path" != *.git && -d "$wt_path" ]]; then
    mtime="$(stat -f '%m' "$wt_path" 2>/dev/null || stat -c '%Y' "$wt_path" 2>/dev/null || echo 0)"
    entries+=("$mtime|$branch")
  fi

  # Sort by mtime descending and get the Nth entry
  if (( ${#entries[@]} == 0 )); then
    return 1
  fi

  local sorted; sorted="$(printf '%s\n' "${entries[@]}" | sort -t'|' -k1 -nr)"
  local result; result="$(print -r -- "$sorted" | sed -n "${idx}p")"

  if [[ -z "$result" ]]; then
    return 1
  fi

  # Extract branch from result
  print -r -- "${result#*|}"
  return 0
}

# fuzzy_match_branch — Find best matching worktree branch for a query string
fuzzy_match_branch() {
  local repo="$1"
  local query="$2"
  local git_dir; git_dir="$(git_dir_for "$repo")"

  [[ -d "$git_dir" ]] || return 1

  # Get all branches with worktrees
  local branches=()
  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || return 1

  local line="" branch=""
  while IFS= read -r line; do
    if [[ "$line" == branch\ refs/heads/* ]]; then
      branch="${line#branch refs/heads/}"
      branches+=("$branch")
    fi
  done <<< "$out"

  (( ${#branches[@]} == 0 )) && return 1

  # 1. Try exact match
  for b in "${branches[@]}"; do
    [[ "$b" == "$query" ]] && { print -r -- "$b"; return 0; }
  done

  # 2. Try slug match (query might be slugified)
  # Declare loop variables outside to avoid zsh re-declaration output
  slugify_branch "$query"
  local query_slug="$REPLY"
  local b_slug b_lower score
  for b in "${branches[@]}"; do
    slugify_branch "$b"
    b_slug="$REPLY"
    [[ "$b_slug" == "$query_slug" ]] && { print -r -- "$b"; return 0; }
  done

  # 3. Try substring match (case-insensitive)
  local query_lower="${query:l}"
  for b in "${branches[@]}"; do
    b_lower="${b:l}"
    [[ "$b_lower" == *"$query_lower"* ]] && { print -r -- "$b"; return 0; }
  done

  # 4. Try word boundary match (e.g., "feat-auth" matches "feature/auth-improvements")
  local best_match="" best_score=0
  for b in "${branches[@]}"; do
    _fuzzy_score "$query" "$b"
    score="$REPLY"
    if (( score > best_score )); then
      best_score=$score
      best_match="$b"
    fi
  done

  if [[ -n "$best_match" && best_score -gt 0 ]]; then
    print -r -- "$best_match"
    return 0
  fi

  return 1
}

# Calculate fuzzy match score between a query and candidate string
#
# Scores character matches with bonuses for word boundary positions
# (after '/' or '-'). Returns 0 if not all query characters matched.
#
# Arguments:
#   $1 - query string
#   $2 - candidate string
#
# Output:
#   Integer score (higher is better, 0 means no match)
_fuzzy_score() {
  local query="$1"
  local candidate="$2"
  local score=0

  # Lowercase for comparison
  local q="${query:l}"
  local c="${candidate:l}"

  # Score for consecutive character matches at word boundaries
  local q_idx=0
  local q_len=${#q}

  for (( i=0; i<${#c}; i++ )); do
    if (( q_idx >= q_len )); then
      break
    fi
    if [[ "${c:$i:1}" == "${q:$q_idx:1}" ]]; then
      # Check if at word boundary (start, after /, after -)
      if (( i == 0 )) || [[ "${c:$((i-1)):1}" == "/" ]] || [[ "${c:$((i-1)):1}" == "-" ]]; then
        score=$((score + 10))  # Word boundary match
      else
        score=$((score + 1))   # Mid-word match
      fi
      q_idx=$((q_idx + 1))
    fi
  done

  # Only count if all query chars were matched
  if (( q_idx < q_len )); then
    score=0
  fi

  REPLY="$score"
}

# resolve_branch_ref — Resolve branch ref from @N shortcut, fuzzy query, or exact name
resolve_branch_ref() {
  local repo="$1"
  local ref="$2"

  # Check for @N shortcut
  if [[ "$ref" == @[0-9]* ]]; then
    local resolved; resolved="$(resolve_recent_shortcut "$repo" "$ref")"
    if [[ -n "$resolved" ]]; then
      print -r -- "$resolved"
      return 0
    fi
    return 1
  fi

  # Try direct lookup first
  local wt_path; wt_path="$(lookup_worktree_path "$repo" "$ref")"
  if [[ -n "$wt_path" ]]; then
    print -r -- "$ref"
    return 0
  fi

  # Try fuzzy match
  local matched; matched="$(fuzzy_match_branch "$repo" "$ref")"
  if [[ -n "$matched" ]]; then
    print -r -- "$matched"
    return 0
  fi

  # Return original (might be a new branch)
  print -r -- "$ref"
  return 0
}
