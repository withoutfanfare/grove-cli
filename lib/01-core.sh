#!/usr/bin/env zsh
# 01-core.sh - Configuration loading, colours, output helpers

# Cached timestamp for current command execution
# Call _cache_now() at command start, then use $_GROVE_NOW
typeset -g _GROVE_NOW=""

# Cache current timestamp (call once at command start)
_cache_now() {
  local ts
  ts="$(date +%s)"
  # Validate it's a positive integer before storing
  [[ "$ts" =~ ^[0-9]+$ ]] && _GROVE_NOW="$ts"
}

# Get cached timestamp (falls back to fresh if not cached)
_get_now() {
  if [[ -z "$_GROVE_NOW" || ! "$_GROVE_NOW" =~ ^[0-9]+$ ]]; then
    local ts
    ts="$(date +%s)"
    [[ "$ts" =~ ^[0-9]+$ ]] && _GROVE_NOW="$ts" || _GROVE_NOW="0"
  fi
  print -r -- "$_GROVE_NOW"
}

# Read a config file and call a handler function for each valid key/value pair
# Usage: _read_config_pairs <file> <handler_function>
# The handler receives two arguments: clean key and clean value
_read_config_pairs() {
  local file="$1"
  local handler="$2"
  [[ -f "$file" ]] || return 0

  local key value was_quoted
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Skip lines with null bytes (potential injection attempt)
    [[ "$key" == *$'\0'* || "$value" == *$'\0'* ]] && continue

    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" || "$key" =~ ^[[:space:]]*$ ]] && continue

    # Trim whitespace from key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    # Clean value inline (avoid subprocess from function call)
    was_quoted=false
    if [[ "$value" == \"*\" ]] || [[ "$value" == \'*\' ]]; then
      was_quoted=true
    fi
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    # Only strip inline comments if value was not quoted
    # (quoted values like "my#password" should keep the #)
    if [[ "$was_quoted" == false ]]; then
      value="${value%%#*}"
    fi
    value="${value%"${value##*[![:space:]]}"}"

    # Pass to handler
    "$handler" "$key" "$value"
  done < "$file"
}

# load_config — Load global config from ~/.groverc and HERD_ROOT/.groveconfig
load_config() {
  # Handler for global config - only allows whitelisted variables (security)
  _apply_global_config() {
    local key="$1" value="$2"
    case "$key" in
      HERD_ROOT) HERD_ROOT="$value" ;;
      HERD_CONFIG) HERD_CONFIG="$value" ;;
      DEFAULT_BASE) DEFAULT_BASE="$value" ;;
      DEFAULT_EDITOR) DEFAULT_EDITOR="$value" ;;
      GROVE_URL_SUBDOMAIN) GROVE_URL_SUBDOMAIN="$value" ;;
      GROVE_MAX_PARALLEL) GROVE_MAX_PARALLEL="$value" ;;
      DB_HOST) DB_HOST="$value" ;;
      DB_USER) DB_USER="$value" ;;
      DB_PASSWORD) DB_PASSWORD="$value" ;;
      DB_CREATE) DB_CREATE="$value" ;;
      DB_BACKUP_DIR) DB_BACKUP_DIR="$value" ;;
      DB_BACKUP) DB_BACKUP="$value" ;;
      GROVE_HOOKS_DIR) GROVE_HOOKS_DIR="$value" ;;
      GROVE_TEMPLATES_DIR) GROVE_TEMPLATES_DIR="$value" ;;
      PROTECTED_BRANCHES) PROTECTED_BRANCHES="$value" ;;
      BRANCH_PATTERN) BRANCH_PATTERN="$value" ;;
      BRANCH_EXAMPLES) BRANCH_EXAMPLES="$value" ;;
      REPO_GROUPS) REPO_GROUPS="$value" ;;
      GROVE_SHARED_DEPS_DIR) GROVE_SHARED_DEPS_DIR="$value" ;;
      GROVE_STALE_THRESHOLD) GROVE_STALE_THRESHOLD="$value" ;;
    esac
  }

  local config_file="${GROVE_CONFIG:-$HOME/.groverc}"
  _read_config_pairs "$config_file" _apply_global_config
  # Also check HERD_ROOT/.groveconfig
  _read_config_pairs "$HERD_ROOT/.groveconfig" _apply_global_config
}

# load_repo_config — Load repo-specific config overrides from bare repo directory
load_repo_config() {
  local git_dir="$1"
  local repo_config="$git_dir/.groveconfig"

  # Handler for repo-specific config - restricted whitelist (security)
  _apply_repo_config() {
    local key="$1" value="$2"
    case "$key" in
      DEFAULT_BASE) DEFAULT_BASE="$value" ;;
      GROVE_URL_SUBDOMAIN) GROVE_URL_SUBDOMAIN="$value" ;;
      PROTECTED_BRANCHES) PROTECTED_BRANCHES="$value" ;;
      GROVE_STALE_THRESHOLD) GROVE_STALE_THRESHOLD="$value" ;;
    esac
  }

  _read_config_pairs "$repo_config" _apply_repo_config
}

# setup_colors — Initialise colour escape codes (disabled for non-TTY and JSON output)
setup_colors() {
  if [[ -t 1 ]] && [[ "$JSON_OUTPUT" == false ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
  fi
}

# Output helpers — die/info/ok/warn/dim for consistent terminal messaging
# Error Message Standards:
# - Capitalise first word
# - Quote user-provided values in single quotes: '$value'
# - Use consistent terminology: "repository" not "repo", "branch" not "br"
# - No trailing periods for die() messages (programme terminates)
# - Include periods for multi-sentence warn() messages
# - Be specific and actionable when possible

# die — Print error message to stderr and exit (uses JSON in --json mode)
die() {
  if [[ "${JSON_OUTPUT:-}" == "true" ]]; then
    die_json "ERROR" "$*" 1
  fi
  print -r -- "${C_RED}✖ ERROR:${C_RESET} $*" >&2
  exit 1
}
# info — Print informational message (suppressed in quiet mode)
info() { [[ "$QUIET" == true ]] || print -r -- "${C_BLUE}→${C_RESET} $*"; }
# ok — Print success message (suppressed in quiet mode)
ok()   { [[ "$QUIET" == true ]] || print -r -- "${C_GREEN}✔${C_RESET} $*"; }
# warn — Print warning message (always shown, even in quiet mode)
warn() { print -r -- "${C_YELLOW}⚠${C_RESET} $*"; }
# dim — Print dimmed/secondary message (suppressed in quiet mode)
dim()  { [[ "$QUIET" == true ]] || print -r -- "${C_DIM}$*${C_RESET}"; }

# Output structured error JSON and exit
# Usage: die_json "ERROR_CODE" "Human readable message" [exit_code]
# Error codes: INVALID_INPUT, INVALID_BRANCH, INVALID_REPO (exit 2)
#              REPO_NOT_FOUND, BRANCH_NOT_FOUND, WORKTREE_NOT_FOUND (exit 3)
#              GIT_ERROR, WORKTREE_EXISTS, PROTECTED_BRANCH (exit 4)
#              DB_ERROR, HOOK_FAILED, IO_ERROR (exit 5)
die_json() {
  local code="$1"
  local message="$2"
  local exit_code="${3:-1}"

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    # Escape JSON special characters using pure Zsh (no subprocess spawns)
    local escaped_msg="$message"
    escaped_msg="${escaped_msg//\\/\\\\}"   # Backslash -> \\
    escaped_msg="${escaped_msg//\"/\\\"}"   # Double quote -> \"
    escaped_msg="${escaped_msg//$'\t'/\\t}" # Tab -> \t
    escaped_msg="${escaped_msg//$'\n'/}"    # Remove newlines
    escaped_msg="${escaped_msg//$'\r'/}"    # Remove carriage returns
    print -r -- "{\"success\": false, \"error\": {\"code\": \"$code\", \"message\": \"$escaped_msg\"}}"
  else
    print -r -- "${C_RED}✖ ERROR:${C_RESET} $message" >&2
  fi
  exit "$exit_code"
}

# error_exit — JSON-aware error exit; use this instead of die() in commands
error_exit() {
  die_json "$1" "$2" "${3:-1}"
}

# die_wt_not_found — Display worktree-not-found error with usage hint and exit
die_wt_not_found() {
  local repo="$1" wt_path="$2"
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    error_exit "WORKTREE_NOT_FOUND" "Worktree not found at '$wt_path'" 3
  else
    print -r -- "${C_RED}✖ ERROR:${C_RESET} Worktree not found at ${C_CYAN}$wt_path${C_RESET}" >&2
    print -r -- "" >&2
    print -r -- "  ${C_DIM}To see available worktrees, run:${C_RESET}" >&2
    print -r -- "    grove ls $repo" >&2
    print -r -- "" >&2
    exit 3
  fi
}

# Send a macOS desktop notification via osascript
#
# Arguments:
#   $1 - notification title
#   $2 - notification message
notify() {
  local title="$1" message="$2"
  if command -v osascript >/dev/null 2>&1; then
    # Escape double quotes and backslashes to prevent osascript injection
    title="${title//\\/\\\\}"
    title="${title//\"/\\\"}"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
  fi
}

# Restart Herd service with nginx reload
# Uses AppleScript to gracefully restart Herd with delays for stability
restart_herd_service() {
  # Only run if herd is installed
  command -v herd >/dev/null 2>&1 || return 0

  info "Restarting Herd services..."

  # First restart nginx to pick up any config changes
  herd restart >/dev/null 2>&1 || true

  # Use AppleScript to restart Herd app with delays for stability
  if command -v osascript >/dev/null 2>&1; then
    dim "  Restarting Herd application..."
    osascript <<'EOF' 2>/dev/null || true
      -- Short delay before closing
      delay 0.5

      -- Quit Herd gracefully
      tell application "Herd"
        quit
      end tell

      -- Wait for Herd to fully close
      delay 1.5

      -- Reopen Herd
      tell application "Herd"
        activate
      end tell

      -- Wait for Herd to initialise
      delay 1.0
EOF
    ok "Herd services restarted"
  else
    dim "  AppleScript not available - nginx restarted only"
  fi
}

# Prompt the user for yes/no confirmation
#
# Skips the prompt and returns 0 if FORCE is true.
#
# Arguments:
#   $1 - prompt message to display
#
# Returns:
#   0 if confirmed, 1 if denied
confirm() {
  local msg="$1"
  [[ "$FORCE" == true ]] && return 0

  print -n "${C_YELLOW}$msg [y/N]${C_RESET} "
  local response
  read -r response
  [[ "$response" =~ ^[Yy]$ ]]
}

# ===== Size Utilities (pure Zsh for human-readable conversion) =====

# Convert kilobytes to human-readable format (K, M, G, T)
# Input: size in KB (from du -sk)
# Usage: bytes_to_human 1234567 -> "1.2G"
bytes_to_human() {
  local bytes="$1"

  # Handle invalid/empty input
  [[ -z "$bytes" || "$bytes" == "0" ]] && { print -r -- "0K"; return; }

  # Validate it's a positive integer (security: prevent shell injection via arithmetic)
  [[ "$bytes" =~ ^[0-9]+$ ]] || { print -r -- "0K"; return; }

  local units=("K" "M" "G" "T")
  local unit_idx=1
  local size="$bytes"

  # Input is in KB (from du -sk), so start with K (index 1)
  # Convert to float-ish by keeping one decimal
  while (( size >= 1024 && unit_idx < 4 )); do
    # Integer division with remainder for decimal
    local whole=$((size / 1024))
    local frac=$(( (size % 1024) * 10 / 1024 ))
    size="$whole"
    unit_idx=$((unit_idx + 1))

    # If we have a meaningful fraction and we're stopping here
    if (( size < 1024 )); then
      if (( frac > 0 )); then
        print -r -- "${size}.${frac}${units[$unit_idx]}"
        return
      fi
    fi
  done

  print -r -- "${size}${units[$unit_idx]}"
}

# Get directory size in KB (single du call)
# Usage: get_dir_size_kb "/path/to/dir"
# Returns: size in KB or 0 on error
get_dir_size_kb() {
  local dir="$1"
  local output
  output="$(du -sk "$dir" 2>/dev/null)" || { print -r -- "0"; return; }
  print -r -- "${output%%$'\t'*}"
}

# ===== String Utilities (pure Zsh, zero subprocess spawns) =====

# Trim whitespace from both ends
# Usage: str="$(trim "  hello  ")" -> "hello"
trim() {
  local str="$1"
  str="${str#"${str%%[![:space:]]*}"}"
  str="${str%"${str##*[![:space:]]}"}"
  print -r -- "$str"
}

# Count lines in a string without subprocess
# Usage: n="$(count_lines "$multiline")"
count_lines() {
  local str="$1"
  [[ -z "$str" ]] && { print -r -- 0; return; }
  local -a lines
  lines=("${(@f)str}")
  print -r -- "${#lines}"
}

# Get first N lines without head subprocess
# Usage: result="$(first_n_lines "$str" 5)"
first_n_lines() {
  local str="$1" n="${2:-10}"
  [[ -z "$str" ]] && return
  local -a lines
  lines=("${(@f)str}")
  print -r -- "${(F)lines[1,$n]}"
}

# ===== Git Status Utilities (pure Zsh, zero subprocess spawns) =====

# Count lines matching a Zsh pattern
# Usage: count_matching "$multiline_string" "^[MADRC]"
# Note: Pattern is a Zsh extended glob pattern, not regex
count_matching() {
  local str="$1"
  local pattern="$2"
  local count=0

  [[ -z "$str" ]] && { print -r -- "0"; return; }

  local line
  while IFS= read -r line; do
    # Use if/else instead of case to avoid $~ pattern expansion issues with set -e
    if [[ "$line" == $~pattern ]]; then
      count=$((count + 1))
    fi
  done <<< "$str"

  print -r -- "$count"
}

# Count git status lines by type (optimized for git status --short output)
# Usage: count_git_status_types "$status_output"
# Returns: "staged modified untracked" (space-separated)
count_git_status_types() {
  local st="$1"
  local staged=0 modified=0 untracked=0

  [[ -z "$st" ]] && { print -r -- "0 0 0"; return; }

  local line char1 char2
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    char1="${line:0:1}"
    char2="${line:1:1}"

    # Staged: first char is M, A, D, R, or C
    # Use safe arithmetic assignment instead of ((++var)) which can still fail
    case "$char1" in
      [MADRC]) staged=$((staged + 1)) ;;
    esac

    # Modified: second char is M, A, D, R, or C
    case "$char2" in
      [MADRC]) modified=$((modified + 1)) ;;
    esac

    # Untracked: starts with ??
    if [[ "$line" == "??"* ]]; then
      untracked=$((untracked + 1))
    fi
  done <<< "$st"

  print -r -- "$staged $modified $untracked"
}

# ===== JSON Parsing (pure Zsh, zero subprocess spawns) =====

# Extract a string field from simple JSON
# Usage: json_get_string '{"key":"value"}' "key" -> "value"
json_get_string() {
  local json="$1" key="$2"
  local pattern="\"$key\":\"([^\"]*)\""

  if [[ "$json" =~ $pattern ]]; then
    print -r -- "${match[1]}"
    return 0
  fi
  return 1
}

# Extract a number/boolean field from simple JSON
# Usage: json_get_value '{"key":123}' "key" -> "123"
#        json_get_value '{"key":true}' "key" -> "true"
json_get_value() {
  local json="$1" key="$2"
  local pattern="\"$key\":([^,\"}]+)"

  if [[ "$json" =~ $pattern ]]; then
    local val="${match[1]}"
    # Trim whitespace
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    print -r -- "$val"
    return 0
  fi
  return 1
}
