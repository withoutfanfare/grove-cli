#!/usr/bin/env bash
# test-helper.bash - Shared test utilities for grove-cli BATS tests

# Get the directory containing the grove script
GROVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GROVE_ROOT

# Create a temp directory for test isolation
setup_test_environment() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  export HERD_ROOT="$TEST_TEMP_DIR/Herd"
  mkdir -p "$HERD_ROOT"

  # Keep tests hermetic from the developer's real ~/.groverc: point GROVE_CONFIG
  # at an empty config so the user's HERD_ROOT (etc.) can never override the
  # test environment. Without this, any test that execs the compiled grove
  # picks up ~/.groverc and looks for repos in the wrong HERD_ROOT.
  export GROVE_CONFIG="$TEST_TEMP_DIR/test.groverc"
  : > "$GROVE_CONFIG"

  # Create a minimal test hooks directory
  export GROVE_HOOKS_DIR="$TEST_TEMP_DIR/.grove/hooks"
  mkdir -p "$GROVE_HOOKS_DIR"

  # Disable colours for testing
  export NO_COLOR=1

  # Set test defaults
  export DEFAULT_BASE="origin/main"
  export QUIET=true
}

teardown_test_environment() {
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Source specific functions from the grove script without running main()
# This extracts just the functions we need for unit testing
source_grove_functions() {
  # We need to carefully extract functions without executing the script
  # Create a modified version that doesn't call main()
  local temp_grove="$TEST_TEMP_DIR/grove-functions.zsh"

  # Extract everything except the main() call at the end
  sed '/^main "\$@"$/d' "$GROVE_ROOT/grove" > "$temp_grove"

  # Source it in a subshell to get the functions
  # Note: For BATS (bash), we'll reimplement the functions in bash
}

# ============================================================================
# Reimplemented functions for bash testing
# These mirror the zsh implementations but work in bash
# ============================================================================

# Slugify a string (shared transform — mirrors slugify_string in lib/03-paths.sh)
#
# Lowercase, replace every run of non-[a-z0-9] with a single dash, collapse
# repeated dashes, then trim leading/trailing dashes. This must stay faithful to
# the real zsh source so the bash mirror and the real code never diverge.
slugify_string() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"  # Lowercase
  # Replace every non-[a-z0-9] character with a dash (C locale so multi-byte
  # unicode bytes are each treated as non-[a-z0-9], matching the zsh source).
  s="$(LC_ALL=C printf '%s' "$s" | LC_ALL=C sed 's/[^a-z0-9]/-/g')"
  # Collapse runs of dashes
  while [[ "$s" == *"--"* ]]; do
    s="${s//--/-}"
  done
  s="${s#-}"  # Trim leading dash
  s="${s%-}"  # Trim trailing dash
  echo "$s"
}

# Slugify branch name (mirrors slugify_branch in lib/03-paths.sh)
slugify_branch() {
  slugify_string "$1"
}

# Extract feature name (last segment after /)
extract_feature_name() {
  local branch="$1"
  if [[ "$branch" == */* ]]; then
    echo "${branch##*/}"
  else
    echo "$branch"
  fi
}

# Generate database name from repo and branch
# Mirrors the real db_name_for() from lib/05-database.sh
db_name_for() {
  local repo="$1"
  local branch="$2"
  # Defence-in-depth: strip backticks so the name can never break out of a
  # `quoted` MySQL identifier even if a caller bypasses upstream validation.
  repo="${repo//\`/}"
  branch="${branch//\`/}"
  local slug
  slug="$(slugify_branch "$branch")"

  # Replace dashes with underscores for MySQL compatibility
  local db_name="${repo}__${slug}"
  db_name="${db_name//-/_}"

  # MySQL database name limit is 64 characters
  if (( ${#db_name} > 64 )); then
    # Truncate and add hash suffix for uniqueness
    local hash
    hash="$(echo -n "$slug" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-8)"
    # Guard against an empty hash (no md5sum/md5 available): fall back to a
    # length-based suffix so distinct long names cannot collapse to the same name.
    if [[ -z "$hash" ]]; then
      hash="${#slug}"
    fi
    # Reserve space: 10 chars for "__" + 8-char hash (2 + 8 = 10)
    local max_repo_len=$((64 - 10))

    # Ensure at least 5 chars of repo name preserved
    if (( ${#repo} < max_repo_len )); then
      max_repo_len=${#repo}
    fi
    if (( max_repo_len < 5 )); then
      max_repo_len=5
    fi

    local truncated_repo="${repo:0:$max_repo_len}"
    db_name="${truncated_repo}__${hash}"
    db_name="${db_name//-/_}"
  fi

  echo "$db_name"
}

# Generate SSL-safe site name for a worktree's domain
# Mirrors the real site_name_for() from lib/03-paths.sh
site_name_for() {
  local repo="$1"
  local branch="$2"

  # Budget = full-hostname ceiling minus the parts that are NOT the label
  # (".test", a safety buffer, and "<subdomain>." when set). Mirrors lib/03-paths.sh.
  local max_hostname="${GROVE_MAX_HOSTNAME:-60}"
  local safety_buffer=4
  local reserved=$(( 5 + safety_buffer ))
  if [[ -n "${GROVE_URL_SUBDOMAIN:-}" ]]; then
    reserved=$(( reserved + ${#GROVE_URL_SUBDOMAIN} + 1 ))
  fi
  local computed_max=$(( max_hostname - reserved ))
  (( computed_max < 10 )) && computed_max=10
  local max_length="${3:-$computed_max}"

  local site_name

  # For main branches, use the repo name
  if [[ "$branch" == "staging" || "$branch" == "main" || "$branch" == "master" ]]; then
    site_name="$repo"
  else
    # Use the FULL slugified branch so distinct branches that share a final
    # segment (e.g. alice/dashboard and bob/dashboard) get distinct site names
    # and never collide on directory, URL, or database.
    site_name="$(slugify_branch "$branch")"
  fi

  # Guard against an empty or all-separator slug producing https://.test or the
  # worktrees root. Fall back to a deterministic hash of the original branch.
  if [[ -z "$site_name" ]]; then
    local fallback_hash
    fallback_hash="$(printf '%s' "$branch" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-8)"
    site_name="wt-${fallback_hash}"
  fi

  # If within limit, return as-is
  if (( ${#site_name} <= max_length )); then
    echo "$site_name"
    return 0
  fi

  # Need to truncate - append hash for uniqueness
  local full_slug
  full_slug="$(slugify_branch "$branch")"
  local hash_suffix
  hash_suffix="$(echo -n "$full_slug" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-6)"
  local suffix_len=7  # "-" + 6-char hash
  local available=$(( max_length - suffix_len ))

  local truncated="${site_name:0:$available}"
  # Remove trailing dash if present
  truncated="${truncated%-}"
  echo "${truncated}-${hash_suffix}"
}

# Generate worktree path
# Mirrors the real worktree_path_for() from lib/03-paths.sh
worktree_path_for() {
  local repo="$1"
  local branch="$2"
  local site_name
  site_name="$(site_name_for "$repo" "$branch")"
  echo "${HERD_ROOT}/${repo}-worktrees/${site_name}"
}

# Keep grove_path_for as an alias for backward compatibility in tests
grove_path_for() {
  worktree_path_for "$@"
}

# Generate URL for worktree
# Mirrors the real url_for() from lib/03-paths.sh
url_for() {
  local repo="$1"
  local branch="$2"
  local site_name
  site_name="$(site_name_for "$repo" "$branch")"

  if [[ -n "${GROVE_URL_SUBDOMAIN:-}" ]]; then
    echo "https://${GROVE_URL_SUBDOMAIN}.${site_name}.test"
  else
    echo "https://${site_name}.test"
  fi
}

# JSON escape function
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"       # Backslash must be first
  s="${s//\"/\\\"}"       # Double quote
  s="${s//$'\n'/\\n}"     # Newline
  s="${s//$'\t'/\\t}"     # Tab
  s="${s//$'\r'/\\r}"     # Carriage return
  s="${s//$'\f'/\\f}"     # Form feed
  s="${s//$'\b'/\\b}"     # Backspace
  echo "$s"
}

# Validate identifier (common checks for all name types)
# Returns 0 if valid, 1 if invalid with error message to stderr
validate_identifier_common() {
  local input="$1"
  local type="$2"

  # Block empty or whitespace-only
  if [[ -z "$input" || "$input" =~ ^[[:space:]]*$ ]]; then
    echo "Invalid $type: name cannot be empty" >&2
    return 1
  fi

  # Block path traversal
  if [[ "$input" == *".."* ]]; then
    echo "Invalid $type: '$input' (path traversal not allowed)" >&2
    return 1
  fi

  # Block names starting with dash (flag injection)
  if [[ "$input" == -* ]]; then
    echo "Invalid $type: '$input' (cannot start with dash)" >&2
    return 1
  fi

  return 0
}

# Validate directory name (for move command new_name parameter)
# More restrictive than validate_name - no slashes allowed
validate_directory_name() {
  local input="$1"

  validate_identifier_common "$input" "directory name" || return 1

  # Directory names must not contain slashes
  if [[ "$input" == */* ]]; then
    echo "Invalid directory name: '$input' (slashes not allowed)" >&2
    return 1
  fi

  return 0
}

# is_reserved_ref_segment — mirrors lib/02-validation.sh
# Returns 0 if any slash-separated segment is a reserved git ref token. HEAD,
# refs and @ are reserved as WHOLE segments anywhere in the path (so feature/HEAD
# and feature/heads/HEAD are caught), and a trailing .lock on any segment is
# reserved by git. Bare @ is the reflog/upstream shorthand.
is_reserved_ref_segment() {
  local ref="$1"
  local segment=""
  # Note: declare `rest` on its own line — assigning `rest="$ref"` on the same
  # `local` line as `ref="$1"` reads the OUTER (empty) ref in bash 5.x.
  local rest="$ref"
  # Bare @ is reserved (reflog/HEAD shorthand)
  [[ "$ref" == "@" ]] && return 0
  # Split on '/' and inspect each segment
  while [[ "$rest" == */* ]]; do
    segment="${rest%%/*}"
    rest="${rest#*/}"
    case "$segment" in
      HEAD|refs|@) return 0 ;;
    esac
    [[ "$segment" == *.lock ]] && return 0
  done
  segment="$rest"
  case "$segment" in
    HEAD|refs|@) return 0 ;;
  esac
  [[ "$segment" == *.lock ]] && return 0
  return 1
}

# is_valid_ref_format — mirrors lib/02-validation.sh
# Delegates to `git check-ref-format` when git is available (it owns the
# canonical rules), with a pure-shell fallback covering the high-value cases.
is_valid_ref_format() {
  local ref="$1"

  if command -v git >/dev/null 2>&1; then
    git check-ref-format "refs/heads/$ref" 2>/dev/null && return 0
    return 1
  fi

  # Pure-shell fallback (git unavailable)
  [[ "$ref" == .* || "$ref" == *. ]] && return 1               # leading/trailing dot
  [[ "$ref" == *"/."* ]] && return 1                            # hidden segment
  [[ "$ref" == *".lock" || "$ref" == *".lock/"* ]] && return 1  # trailing .lock on any segment
  [[ "$ref" == *"//"* || "$ref" == */ ]] && return 1            # empty segments
  return 0
}

# Validate name (repo or branch)
# Mirrors the real validate_name() from lib/02-validation.sh
# Returns 0 if valid, 1 if invalid with error message to stderr
validate_name() {
  local input="$1"
  local type="$2"

  # Block absolute paths
  if [[ "$input" == /* ]]; then
    echo "Invalid $type name: '$input' (absolute paths not allowed)" >&2
    return 1
  fi

  # Block path traversal in various forms
  if [[ "$input" == *".."* || "$input" == *"/."* || "$input" == *"/./"* ]]; then
    echo "Invalid $type name: '$input' (path traversal not allowed)" >&2
    return 1
  fi

  # Block branches starting with dash (git flag injection)
  if [[ "$input" == -* ]]; then
    echo "Invalid $type name: '$input' (cannot start with dash)" >&2
    return 1
  fi

  # Block leading dots (hidden files/directories)
  if [[ "$input" == .* ]]; then
    echo "Invalid $type name: '$input' (leading dot not allowed)" >&2
    return 1
  fi

  # Block trailing dots
  if [[ "$input" == *. ]]; then
    echo "Invalid $type name: '$input' (trailing dot not allowed)" >&2
    return 1
  fi

  # Allow alphanumeric, dash, underscore, forward slash, dot
  if [[ ! "$input" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    echo "Invalid $type name: '$input' (only alphanumeric, dash, underscore, slash, dot allowed)" >&2
    return 1
  fi

  # Block empty segments in paths
  if [[ "$input" =~ // || "$input" =~ /$ ]]; then
    echo "Invalid $type name: '$input' (malformed path)" >&2
    return 1
  fi

  # Branch-only: reserved git references and ref-format rules. The cheap
  # charset/traversal pre-checks above run first; git owns the authoritative
  # decision (trailing .lock, etc.), and we layer the stricter whole-segment
  # HEAD/refs/@ rule on top.
  if [[ "$type" == "branch" ]]; then
    if is_reserved_ref_segment "$input"; then
      echo "Invalid $type name: '$input' (reserved git reference)" >&2
      return 1
    fi
    if ! is_valid_ref_format "$input"; then
      echo "Invalid $type name: '$input' (invalid git ref format)" >&2
      return 1
    fi
  fi

  return 0
}

# Validate git ref (mirrors validate_git_ref() from lib/02-validation.sh)
# Returns 0 if valid, 1 if invalid with error message to stderr
validate_git_ref() {
  local ref="$1"
  local type="${2:-git ref}"

  # Empty is sometimes okay (will use default)
  [[ -z "$ref" ]] && return 0

  # Block command injection characters
  if [[ "$ref" == *";"* ]] || [[ "$ref" == *"|"* ]] || [[ "$ref" == *"&"* ]] || \
     [[ "$ref" == *'$'* ]] || [[ "$ref" == *'`'* ]] || [[ "$ref" == *'\'* ]]; then
    echo "Invalid $type: '$ref' (contains forbidden characters)" >&2
    return 1
  fi

  # Validate format (alphanumeric, forward slash, dash, dot, underscore)
  if [[ ! "$ref" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    echo "Invalid $type format: '$ref'" >&2
    return 1
  fi

  # Block suspicious patterns (path traversal, flag injection, trailing slash)
  if [[ "$ref" == *".."* ]] || [[ "$ref" == -* ]] || [[ "$ref" == */ ]]; then
    echo "Invalid $type: '$ref' (suspicious pattern)" >&2
    return 1
  fi

  # Parity with validate_name: hidden segments and leading/trailing dots
  if [[ "$ref" == *"/."* || "$ref" == .* || "$ref" == *. ]]; then
    echo "Invalid $type: '$ref' (suspicious pattern)" >&2
    return 1
  fi

  # Parity with validate_name: empty path segments
  if [[ "$ref" == *"//"* ]]; then
    echo "Invalid $type: '$ref' (malformed path)" >&2
    return 1
  fi

  # Parity with validate_name: reserved git references and ref-format rules.
  if is_reserved_ref_segment "$ref"; then
    echo "Invalid $type: '$ref' (reserved git reference)" >&2
    return 1
  fi
  if ! is_valid_ref_format "$ref"; then
    echo "Invalid $type: '$ref' (invalid git ref format)" >&2
    return 1
  fi

  return 0
}

# Check if branch is protected
is_protected_branch() {
  local branch="$1"
  local protected_branches="${PROTECTED_BRANCHES:-staging main master}"

  for protected in $protected_branches; do
    if [[ "$branch" == "$protected" ]]; then
      return 0
    fi
  done
  return 1
}

# ============================================================================
# Config parsing (simplified for testing)
# ============================================================================

# Parse a config file and set variables
# Only whitelisted variables are set (security)
parse_config_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" || "$key" =~ ^[[:space:]]*$ ]] && continue

    # Trim whitespace from key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    # Remove quotes and trailing comments from value
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    value="${value%%#*}"
    value="${value%"${value##*[![:space:]]}"}"

    # Only set whitelisted variables (security)
    case "$key" in
      HERD_ROOT) export HERD_ROOT="$value" ;;
      DEFAULT_BASE) export DEFAULT_BASE="$value" ;;
      DEFAULT_EDITOR) export DEFAULT_EDITOR="$value" ;;
      GROVE_URL_SUBDOMAIN) export GROVE_URL_SUBDOMAIN="$value" ;;
      DB_HOST) export DB_HOST="$value" ;;
      DB_PORT) export DB_PORT="$value" ;;
      DB_USER) export DB_USER="$value" ;;
      DB_PASSWORD) export DB_PASSWORD="$value" ;;
      DB_CREATE) export DB_CREATE="$value" ;;
      DB_BACKUP_DIR) export DB_BACKUP_DIR="$value" ;;
      DB_BACKUP) export DB_BACKUP="$value" ;;
      GROVE_HOOKS_DIR) export GROVE_HOOKS_DIR="$value" ;;
      PROTECTED_BRANCHES) export PROTECTED_BRANCHES="$value" ;;
      # Non-whitelisted variables are silently ignored (security)
    esac
  done < "$file"
}

# ============================================================================
# Test assertion helpers
# ============================================================================

# Assert that two values are equal
assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should be equal}"

  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: $message"
    echo "  Expected: '$expected'"
    echo "  Actual:   '$actual'"
    return 1
  fi
}

# Assert that a command succeeds
assert_success() {
  if [[ $? -ne 0 ]]; then
    echo "Assertion failed: Command should have succeeded"
    return 1
  fi
}

# Assert that a command fails
assert_failure() {
  if [[ $? -eq 0 ]]; then
    echo "Assertion failed: Command should have failed"
    return 1
  fi
}

# Assert output contains string
assert_output_contains() {
  local expected="$1"
  local output="$2"

  if [[ "$output" != *"$expected"* ]]; then
    echo "Assertion failed: Output should contain '$expected'"
    echo "  Actual output: '$output'"
    return 1
  fi
}

# ============================================================================
# Template functions (for template security tests)
# ============================================================================

# Die function (simplified for testing)
die() {
  echo "Error: $1" >&2
  return 1
}

# Warn function (simplified for testing)
warn() {
  echo "Warning: $1" >&2
}

# Dim function (simplified for testing)
dim() {
  echo "$1" >&2
}

# Validate template name (security: prevent path traversal)
validate_template_name() {
  local name="$1"

  # Block empty or whitespace-only names first
  if [[ -z "$name" || "$name" =~ ^[[:space:]]*$ ]]; then
    die "Template name cannot be empty"
    return 1
  fi

  # Block path traversal
  if [[ "$name" == *".."* || "$name" == *"/"* || "$name" == *"\\"* ]]; then
    die "Invalid template name: '$name' (path traversal not allowed)"
    return 1
  fi

  # Only allow alphanumeric, dash, underscore
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    die "Invalid template name: '$name' (only alphanumeric, dash, underscore allowed)"
    return 1
  fi

  return 0
}

# Load a template file and export its GROVE_SKIP_* variables
load_template() {
  local template_name="$1"

  # Validate template name first (security: prevent path traversal)
  validate_template_name "$template_name" || return 1

  local template_file="${GROVE_TEMPLATES_DIR:-$HOME/.grove/templates}/${template_name}.conf"

  # Check if template exists
  if [[ ! -f "$template_file" ]]; then
    die "Template not found: $template_name"
    return 1
  fi

  # Parse template file (only allow GROVE_SKIP_* and TEMPLATE_DESC)
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" || "$key" =~ ^[[:space:]]*$ ]] && continue

    # Trim whitespace from key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    # Remove quotes and trailing comments from value
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    value="${value%%#*}"
    value="${value%"${value##*[![:space:]]}"}"

    # Only allow GROVE_SKIP_* variables with true/false values (security)
    case "$key" in
      GROVE_SKIP_*)
        # Security: Only allow true/false values to prevent command injection
        if [[ "$value" != "true" && "$value" != "false" ]]; then
          warn "Invalid value for $key: '$value' (must be true or false) - skipping"
          continue
        fi
        export "$key"="$value"
        ;;
      TEMPLATE_DESC) ;; # Ignore, used for display only
      *) ;; # Ignore other variables (security)
    esac
  done < "$template_file"

  dim "  Applied template: $template_name"
  return 0
}
