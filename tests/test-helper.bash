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

# Slugify branch name (replace / with -)
slugify_branch() {
  local b="$1"
  echo "${b//\//-}"
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
db_name_for() {
  local repo="$1"
  local branch="$2"
  local slug
  slug="$(slugify_branch "$branch")"

  # Replace dashes with underscores for MySQL compatibility
  local db_name="${repo}__${slug}"
  db_name="${db_name//-/_}"

  # MySQL database name limit is 64 characters
  if (( ${#db_name} > 64 )); then
    # Truncate and add hash suffix for uniqueness
    local hash
    hash="$(echo -n "$slug" | md5sum | cut -c1-8)"
    local max_repo_len=$((64 - 11))  # Leave room for __<8-char-hash>
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
  local max_length="${3:-59}"

  local site_name

  # For main branches, use the repo name
  if [[ "$branch" == "staging" || "$branch" == "main" || "$branch" == "master" ]]; then
    site_name="$repo"
  else
    # Extract just the feature name (last segment after /)
    local feature_name
    if [[ "$branch" == */* ]]; then
      feature_name="${branch##*/}"
    else
      feature_name="$branch"
    fi
    site_name="$(slugify_branch "$feature_name")"
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

# Validate name (repo or branch)
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

  # Block reserved git references (only for branches)
  if [[ "$type" == "branch" ]]; then
    if [[ "$input" =~ ^(HEAD|refs/|@) ]]; then
      echo "Invalid $type name: '$input' (reserved git reference)" >&2
      return 1
    fi
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
