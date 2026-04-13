#!/usr/bin/env zsh
# 11-resilience.sh - Retry logic, transactions, disk checks, lock cleanup

# with_retry — Retry a command with exponential backoff (1s, 2s, 4s, ...)
with_retry() {
  local max_attempts="$1"
  shift

  local attempt=1
  local delay=1

  while (( attempt <= max_attempts )); do
    if "$@"; then
      return 0
    fi

    if (( attempt < max_attempts )); then
      dim "  Attempt $attempt failed, retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))
    fi

    attempt=$((attempt + 1))
  done

  return 1
}

# check_index_locks — Find (and optionally remove) stale git index.lock files
check_index_locks() {
  local git_dir="$1"
  local auto_clean="${2:-}"
  local locks_found=0

  local worktrees_dir="$git_dir/worktrees"
  [[ -d "$worktrees_dir" ]] || return 0

  for lock_file in "$worktrees_dir"/*/index.lock(N); do
    [[ -f "$lock_file" ]] || continue

    # Check if lock is stale (older than 5 minutes and no git process)
    local lock_age=$(($(_get_now) - $(stat -f %m "$lock_file" 2>/dev/null || stat -c %Y "$lock_file" 2>/dev/null || echo 0)))
    if (( lock_age > 300 )); then
      if [[ "$auto_clean" == "--auto-clean" ]]; then
        rm -f "$lock_file"
        dim "  Removed stale lock: ${lock_file##*/worktrees/}"
      else
        warn "Stale lock found: ${lock_file##*/worktrees/}"
        locks_found=$((locks_found + 1))
      fi
    fi
  done

  return $locks_found
}

# check_disk_space — Exit with error if available disk space is below threshold
check_disk_space() {
  local path="$1"
  local min_mb="${2:-1024}"  # Default 1GB

  local available_kb
  available_kb=$(df -k "$path" 2>/dev/null | tail -1 | awk '{print $4}')
  local available_mb=$((available_kb / 1024))

  if (( available_mb < min_mb )); then
    die "Insufficient disk space: ${available_mb}MB available, ${min_mb}MB required"
  fi
}

# Transaction state
typeset -g GROVE_TRANSACTION_ACTIVE=false
typeset -g GROVE_ROLLBACK_STEPS=()

# transaction_start — Begin a transaction with automatic rollback on failure
transaction_start() {
  GROVE_TRANSACTION_ACTIVE=true
  GROVE_ROLLBACK_STEPS=()
  # Chain spinner cleanup before transaction rollback on EXIT.
  # INT/TERM spinner cleanup is handled separately in 08-spinner.sh.
  trap 'spinner_stop 2>/dev/null; transaction_rollback' EXIT INT TERM
}

# transaction_register — Add a rollback function (with args) to the active transaction
transaction_register() {
  local func_name="$1"
  shift
  local args=("$@")
  local US=$'\x1F'  # ASCII Unit Separator - safe delimiter that won't appear in arguments

  # Validate it's an actual function
  if ! typeset -f "$func_name" >/dev/null 2>&1; then
    die "Invalid rollback function: $func_name (not a defined function)"
  fi

  # Store function name and args joined by Unit Separator
  # Format: "func_name\x1Farg1\x1Farg2\x1F..."
  local step="$func_name"
  if (( $# > 0 )); then
    step="${func_name}${US}${(pj:$US:)args}"
  fi
  GROVE_ROLLBACK_STEPS+=("$step")
}

# transaction_commit — Complete a transaction successfully, disabling rollback traps
transaction_commit() {
  GROVE_TRANSACTION_ACTIVE=false
  GROVE_ROLLBACK_STEPS=()
  trap - EXIT INT TERM
}

# transaction_rollback — Execute registered rollback steps in reverse order
transaction_rollback() {
  [[ "$GROVE_TRANSACTION_ACTIVE" == true ]] || return 0

  warn "Rolling back failed operation..."

  # Execute rollback steps in reverse order
  local i
  local US=$'\x1F'  # ASCII Unit Separator - matches delimiter used in transaction_register
  for ((i=${#GROVE_ROLLBACK_STEPS[@]}; i>=1; i--)); do
    local step="${GROVE_ROLLBACK_STEPS[$i]}"

    # Parse function name and args (split on Unit Separator)
    local func_name="${step%%$US*}"
    local remaining="${step#*$US}"

    # Call function directly (no eval!)
    if [[ "$step" == *"$US"* ]]; then
      # Has args - split on Unit Separator using IFS
      local old_ifs="$IFS"
      IFS="$US"
      local args=(${=remaining})
      IFS="$old_ifs"
      "$func_name" "${args[@]}" 2>/dev/null || true
    else
      # No args
      "$func_name" 2>/dev/null || true
    fi
  done

  GROVE_TRANSACTION_ACTIVE=false
}
