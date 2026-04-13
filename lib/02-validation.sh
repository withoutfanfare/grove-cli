#!/usr/bin/env zsh
# 02-validation.sh - Input validation and security checks

# is_protected_branch — Return 0 if branch is in the PROTECTED_BRANCHES list
is_protected_branch() {
  local branch="$1"
  local protected
  for protected in ${=PROTECTED_BRANCHES}; do
    [[ "$branch" == "$protected" ]] && return 0
  done
  return 1
}

# validate_identifier_common — Shared validation for empty, path traversal, and flag injection
validate_identifier_common() {
  local input="$1" type="$2"

  # Map type to error code
  local error_code="INVALID_INPUT"
  case "$type" in
    repository) error_code="INVALID_REPO" ;;
    branch) error_code="INVALID_BRANCH" ;;
  esac

  # Block empty or whitespace-only
  if [[ -z "$input" || "$input" =~ ^[[:space:]]*$ ]]; then
    error_exit "$error_code" "Invalid $type: name cannot be empty" 2
  fi

  # Block path traversal
  if [[ "$input" == *".."* ]]; then
    error_exit "$error_code" "Invalid $type: '$input' (path traversal not allowed)" 2
  fi

  # Block names starting with dash (flag injection)
  if [[ "$input" == -* ]]; then
    error_exit "$error_code" "Invalid $type: '$input' (cannot start with dash)" 2
  fi
}

# validate_name — Full security validation for repository or branch names
validate_name() {
  local input="$1" type="$2"

  validate_identifier_common "$input" "$type"

  # Map type to error code
  local error_code="INVALID_INPUT"
  case "$type" in
    repository) error_code="INVALID_REPO" ;;
    branch) error_code="INVALID_BRANCH" ;;
  esac

  # Block absolute paths
  if [[ "$input" == /* ]]; then
    error_exit "$error_code" "Invalid $type name: '$input' (absolute paths not allowed)" 2
  fi

  # Block hidden path segments and dot-based attacks
  if [[ "$input" == *"/."* || "$input" == *"/./"* ]]; then
    error_exit "$error_code" "Invalid $type name: '$input' (path traversal not allowed)" 2
  fi

  # Block leading dots (hidden files/directories)
  if [[ "$input" == .* ]]; then
    error_exit "$error_code" "Invalid $type name: '$input' (leading dot not allowed)" 2
  fi

  # Block trailing dots
  if [[ "$input" == *. ]]; then
    error_exit "$error_code" "Invalid $type name: '$input' (trailing dot not allowed)" 2
  fi

  # Block reserved git references
  if [[ "$type" == "branch" && "$input" =~ ^(HEAD|refs/|@).*$ ]]; then
    error_exit "$error_code" "Invalid $type name: '$input' (reserved git reference)" 2
  fi

  # Allow alphanumeric, dash, underscore, forward slash, dot
  if [[ ! "$input" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    error_exit "$error_code" "Invalid $type name: '$input' (only alphanumeric, dash, underscore, slash, dot allowed)" 2
  fi

  # Block empty segments in paths
  if [[ "$input" =~ // || "$input" =~ /$ ]]; then
    error_exit "$error_code" "Invalid $type name: '$input' (malformed path)" 2
  fi
}

# validate_branch_pattern — Check branch name against BRANCH_PATTERN regex (if configured)
validate_branch_pattern() {
  local branch="$1"

  # Skip if no pattern configured
  [[ -z "${BRANCH_PATTERN:-}" ]] && return 0

  # Check against pattern
  if [[ ! "$branch" =~ $BRANCH_PATTERN ]]; then
    local suggestion=""

    # Try to suggest a fix
    local clean_branch="${branch//[^a-z0-9\/\-]/-}"  # Replace invalid chars
    clean_branch="${clean_branch:l}"  # Lowercase
    clean_branch="${clean_branch//--/-}"  # Remove double dashes

    # Try common prefixes
    if [[ ! "$branch" =~ ^(feature|bugfix|hotfix|release)/ ]]; then
      suggestion="feature/${clean_branch##*/}"
    else
      suggestion="$clean_branch"
    fi

    local error_msg="Branch name '${C_RED}$branch${C_RESET}' doesn't match required pattern"
    error_msg+="\n\n${C_DIM}Pattern:${C_RESET} $BRANCH_PATTERN"
    error_msg+="\n${C_DIM}Examples:${C_RESET} ${BRANCH_EXAMPLES:-feature/my-feature, bugfix/fix-login}"

    if [[ "$suggestion" != "$branch" ]]; then
      error_msg+="\n\n${C_YELLOW}Suggestion:${C_RESET} $suggestion"
    fi

    error_msg+="\n\n${C_DIM}Use --force to bypass this check${C_RESET}"

    if [[ "${FORCE:-false}" != true ]]; then
      die "$error_msg"
    else
      warn "Branch name doesn't match pattern (bypassed with --force)"
    fi
  fi
}

# normalize_branch_name — Clean up a branch name (lowercase, replace spaces, deduplicate dashes)
normalize_branch_name() {
  local branch="$1"

  # Replace spaces with dashes
  branch="${branch// /-}"

  # Lowercase
  branch="${branch:l}"

  # Remove consecutive dashes
  while [[ "$branch" == *"--"* ]]; do
    branch="${branch//--/-}"
  done

  # Remove leading/trailing dashes from segments
  branch="${branch#-}"
  branch="${branch%-}"

  print -r -- "$branch"
}

# validate_git_ref — Validate git ref format and block injection characters
validate_git_ref() {
  local ref="$1" type="${2:-git ref}"

  # Empty is sometimes okay (will use default)
  [[ -z "$ref" ]] && return 0

  # Block command injection characters
  if [[ "$ref" == *";"* ]] || [[ "$ref" == *"|"* ]] || [[ "$ref" == *"&"* ]] || \
     [[ "$ref" == *'$'* ]] || [[ "$ref" == *'`'* ]] || [[ "$ref" == *'\'* ]]; then
    error_exit "INVALID_INPUT" "Invalid $type: '$ref' (contains forbidden characters)" 2
  fi

  # Validate format (alphanumeric, forward slash, dash, dot, underscore)
  if [[ ! "$ref" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    error_exit "INVALID_INPUT" "Invalid $type format: '$ref'" 2
  fi

  # Block suspicious patterns (path traversal, flag injection, trailing slash)
  if [[ "$ref" == *".."* ]] || [[ "$ref" == -* ]] || [[ "$ref" == */ ]]; then
    error_exit "INVALID_INPUT" "Invalid $type: '$ref' (suspicious pattern)" 2
  fi
}

# validate_max_parallel — Validate GROVE_MAX_PARALLEL and reset to 4 if invalid
validate_max_parallel() {
  if [[ ! "$GROVE_MAX_PARALLEL" =~ ^[0-9]+$ ]] || (( GROVE_MAX_PARALLEL < 1 )); then
    warn "Invalid GROVE_MAX_PARALLEL='$GROVE_MAX_PARALLEL', using default: 4."
    GROVE_MAX_PARALLEL=4
  fi
  if (( GROVE_MAX_PARALLEL > 20 )); then
    warn "GROVE_MAX_PARALLEL='$GROVE_MAX_PARALLEL' exceeds recommended limit (20)."
  fi
}
