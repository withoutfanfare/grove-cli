#!/usr/bin/env zsh
# 11-resilience.sh - Retry logic, transactions, disk checks, lock cleanup
#
# ============================================================================
# PUBLIC API (for lifecycle commands: cmd_add, cmd_clone, cmd_move)
# ============================================================================
#
# Retry:
#   with_retry <max_attempts> <cmd> [args...]
#     Run <cmd> up to <max_attempts> times with exponential backoff
#     (1s, 2s, 4s, ...). Returns the command's status on success, 1 if all
#     attempts fail. Example: with_retry 3 git fetch origin
#
# Disk space:
#   check_disk_space <path> [min_mb]
#     die() if free space at <path> is below <min_mb> megabytes (default 1024).
#     Call BEFORE creating a worktree. Example: check_disk_space "$dest" 500
#
# Transactions (automatic rollback on failure / Ctrl-C):
#   transaction_start
#     Begin a transaction (sets the active flag, clears any steps). A module-
#     level TRAPEXIT runs registered rollback steps if the shell exits while the
#     transaction is still active.
#   transaction_register <func_name> [args...]
#     Register a rollback step. <func_name> MUST be a defined function; it is
#     called with [args...] (no eval). Steps run in REVERSE registration order.
#   transaction_commit
#     Mark the transaction successful: clears the active flag and steps so the
#     TRAPEXIT becomes a no-op. Call this on the success path so rollback does
#     NOT run.
#   transaction_rollback
#     Run registered rollback steps in reverse order. Invoked automatically by
#     TRAPEXIT on shell exit; re-entrant calls are no-ops (guarded). Rarely
#     called directly.
#
# Typical usage:
#   transaction_start
#   mkdir "$worktree" && transaction_register rmdir "$worktree"
#   git worktree add ... && transaction_register git_worktree_remove "$worktree"
#   ... more steps ...
#   transaction_commit   # success: keep everything, drop the trap
# ============================================================================

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

# _lock_file_in_use — Return 0 if a process currently holds the given lock file.
# Tries lsof first, then fuser, so an in-progress git operation (fetch, checkout,
# rebase, CI clone) is never mistaken for a stale lock. If neither tool exists we
# fail closed (treat the lock as in use) to protect the index from corruption.
_lock_file_in_use() {
  local lock_file="$1"

  if command -v lsof >/dev/null 2>&1; then
    lsof -- "$lock_file" >/dev/null 2>&1 && return 0
    return 1
  fi

  if command -v fuser >/dev/null 2>&1; then
    fuser -- "$lock_file" >/dev/null 2>&1 && return 0
    return 1
  fi

  # No process-inspection tool available: fail closed (assume in use).
  return 0
}

# check_index_locks — Find (and optionally remove) stale git index.lock files.
#
# Output contract:
#   STDOUT — the number of stale locks found (one integer, always printed)
#   exit   — 0 on success, 1 on failure (NOT a count)
#
# A lock is only removed under --auto-clean when it is BOTH older than 5 minutes
# AND not held by any running process (see _lock_file_in_use). A lock that is
# still held is reported via warn() and left in place, never deleted.
check_index_locks() {
  local git_dir="$1"
  local auto_clean="${2:-}"
  local locks_found=0

  local worktrees_dir="$git_dir/worktrees"
  if [[ ! -d "$worktrees_dir" ]]; then
    print -r -- 0
    return 0
  fi

  local lock_file lock_age
  for lock_file in "$worktrees_dir"/*/index.lock(N); do
    [[ -f "$lock_file" ]] || continue

    # Only stale locks (older than 5 minutes) are candidates for cleanup.
    lock_age=$(($(_get_now) - $(stat -f %m "$lock_file" 2>/dev/null || stat -c %Y "$lock_file" 2>/dev/null || echo 0)))
    (( lock_age > 300 )) || continue

    # A live git process may legitimately hold a lock for longer than 5 minutes
    # (large fetch, checkout, rebase, CI clone). Never delete an in-use lock.
    if _lock_file_in_use "$lock_file"; then
      warn "Lock still in use, not removing: ${lock_file##*/worktrees/}"
      continue
    fi

    if [[ "$auto_clean" == "--auto-clean" ]]; then
      rm -f "$lock_file"
      dim "  Removed stale lock: ${lock_file##*/worktrees/}"
    else
      warn "Stale lock found: ${lock_file##*/worktrees/}"
    fi
    # Count every stale lock (found or auto-cleaned) so callers report it accurately.
    locks_found=$((locks_found + 1))
  done

  print -r -- "$locks_found"
  return 0
}

# check_disk_space — Exit with error if available disk space is below threshold
check_disk_space() {
  # NB: do not name this 'path' — in zsh `path` is the special array tied to
  # $PATH, so `local path=...` clobbers PATH inside the function and breaks
  # external commands (tail/awk below) in shells where they aren't pre-hashed.
  local target_path="$1"
  local min_mb="${2:-1024}"  # Default 1GB

  local available_kb
  available_kb=$(df -k "$target_path" 2>/dev/null | tail -1 | awk '{print $4}')
  local available_mb=$((available_kb / 1024))

  if (( available_mb < min_mb )); then
    die "Insufficient disk space: ${available_mb}MB available, ${min_mb}MB required"
  fi
}

# Transaction state
typeset -g GROVE_TRANSACTION_ACTIVE=false
typeset -g GROVE_ROLLBACK_STEPS=()

# TRAPEXIT — zsh's shell-exit handler, installed once at module load.
#
# We deliberately do NOT call `trap '...' EXIT` from inside transaction_start:
# in zsh a trap set with the `trap` builtin inside a function is FUNCTION-LOCAL
# and fires when that function returns, which would roll back instantly. A
# top-level TRAPEXIT() fires only on real shell exit and persists across calls.
#
# It fires once on shell exit (including after an unhandled INT/TERM, since zsh
# runs EXIT last), so transaction_rollback runs at most once. The re-entrancy
# guard in transaction_rollback covers any manual call followed by EXIT.
# INT/TERM spinner cleanup is handled separately in 08-spinner.sh.
TRAPEXIT() {
  if [[ "$GROVE_TRANSACTION_ACTIVE" == true ]]; then
    spinner_stop 2>/dev/null
    transaction_rollback
  fi
}

# transaction_start — Begin a transaction with automatic rollback on failure
transaction_start() {
  GROVE_TRANSACTION_ACTIVE=true
  GROVE_ROLLBACK_STEPS=()
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

# transaction_commit — Complete a transaction successfully.
# Clears the active flag and steps so the module-level TRAPEXIT becomes a no-op
# (no rollback runs on shell exit after a successful commit).
transaction_commit() {
  GROVE_TRANSACTION_ACTIVE=false
  GROVE_ROLLBACK_STEPS=()
}

# transaction_rollback — Execute registered rollback steps in reverse order.
# Re-entrant calls are no-ops: GROVE_TRANSACTION_ACTIVE is cleared up front, so a
# second invocation (e.g. EXIT firing after a handled signal) does nothing.
transaction_rollback() {
  [[ "$GROVE_TRANSACTION_ACTIVE" == true ]] || return 0
  # Clear the active flag FIRST so any re-entry returns immediately above.
  GROVE_TRANSACTION_ACTIVE=false

  warn "Rolling back failed operation..."

  # Execute rollback steps in reverse order.
  local i step func_name remaining
  local US=$'\x1F'  # ASCII Unit Separator - matches delimiter used in transaction_register
  local -a args
  for ((i=${#GROVE_ROLLBACK_STEPS[@]}; i>=1; i--)); do
    step="${GROVE_ROLLBACK_STEPS[$i]}"

    # Parse function name and args (split on Unit Separator).
    func_name="${step%%$US*}"

    # Call function directly (no eval!).
    if [[ "$step" == *"$US"* ]]; then
      # Has args. Split on Unit Separator with (@ps:...) which, unlike ${=...}
      # word-splitting, preserves empty arguments (e.g. an empty string arg).
      remaining="${step#*$US}"
      args=("${(@ps:$US:)remaining}")
      "$func_name" "${args[@]}" 2>/dev/null || true
    else
      # No args.
      "$func_name" 2>/dev/null || true
    fi
  done

  GROVE_ROLLBACK_STEPS=()
}
