#!/usr/bin/env zsh
# 08-spinner.sh - Progress indicators for long operations

# Spinner characters (Braille pattern for smooth animation)
readonly SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
readonly SPINNER_DELAY=0.08

# Spinner state
typeset -g SPINNER_PID=""
typeset -g SPINNER_MSG=""

# Start a background spinner animation with a message.
# The spinner renders Braille pattern characters to stderr.
# No-op if stdout is not a TTY or QUIET mode is enabled.
# Stops any existing spinner before starting a new one.
#
# Arguments:
#   $1 - msg: status message to display alongside the spinner
#
# Side effects:
#   Sets SPINNER_PID and SPINNER_MSG globals.
#   Spawns a background subshell (disowned).
#
# Example:
#   spinner_start "Installing dependencies..."
spinner_start() {
  local msg="$1"
  SPINNER_MSG="$msg"

  # Don't show spinner if not a TTY or in quiet mode
  [[ -t 1 && "$QUIET" != true ]] || return 0

  # Kill any existing spinner
  spinner_stop 2>/dev/null || true

  (
    local i=0
    local chars_len=${#SPINNER_CHARS}
    while true; do
      local char="${SPINNER_CHARS:$i:1}"
      printf "\r${C_CYAN}%s${C_RESET} %s" "$char" "$msg" >&2
      i=$(( (i + 1) % chars_len ))
      sleep "$SPINNER_DELAY"
    done
  ) &
  SPINNER_PID=$!
  disown $SPINNER_PID 2>/dev/null || true
}

# Stop the active spinner and display a result indicator.
# Kills the background spinner process and shows a status symbol.
#
# Arguments:
#   $1 - result: "ok" (green tick), "fail" (red cross), or "skip" (dim circle)
#                (default: "ok")
#
# Side effects:
#   Kills SPINNER_PID, clears SPINNER_PID and SPINNER_MSG globals.
spinner_stop() {
  local result="${1:-ok}"

  # Kill spinner process
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi

  [[ -t 1 && "$QUIET" != true ]] || return 0

  # Clear spinner line
  printf "\r\033[K" >&2

  # Show result
  case "$result" in
    ok)   print -r -- "${C_GREEN}✔${C_RESET} $SPINNER_MSG" ;;
    fail) print -r -- "${C_RED}✖${C_RESET} $SPINNER_MSG" ;;
    skip) print -r -- "${C_DIM}○${C_RESET} $SPINNER_MSG ${C_DIM}(skipped)${C_RESET}" ;;
  esac

  SPINNER_MSG=""
}

# Run a command with an animated spinner, showing ok/fail on completion.
# Captures all command output (stdout and stderr are suppressed).
#
# Arguments:
#   $1 - msg: status message to display alongside the spinner
#   $@ - command and arguments to execute
#
# Returns:
#   The exit code of the executed command
#
# Example:
#   with_spinner "Installing npm packages" npm install
with_spinner() {
  local msg="$1"
  shift

  spinner_start "$msg"

  local exit_code=0
  if "$@" >/dev/null 2>&1; then
    spinner_stop "ok"
  else
    exit_code=$?
    spinner_stop "fail"
  fi

  return $exit_code
}

# Display a step progress indicator for multi-step operations.
# Renders "[current/total] message" on stderr, overwriting the current line.
# No-op if stdout is not a TTY or QUIET mode is enabled.
#
# Arguments:
#   $1 - current: current step number
#   $2 - total: total number of steps
#   $3 - msg: description of the current step
step_progress() {
  local current="$1" total="$2" msg="$3"
  [[ -t 1 && "$QUIET" != true ]] || return 0
  printf "\r${C_DIM}[%d/%d]${C_RESET} %s" "$current" "$total" "$msg" >&2
}

# Clear step progress line
step_complete() {
  [[ -t 1 && "$QUIET" != true ]] || return 0
  printf "\r\033[K" >&2
}

# Ensure spinner is stopped on interrupts (INT/TERM only).
# We intentionally avoid trapping EXIT here because the transaction system
# in 11-resilience.sh uses EXIT for rollback, and Zsh's trap replacement
# would cause the spinner cleanup to overwrite transaction rollback.
# The spinner is always explicitly stopped via spinner_stop or with_spinner,
# so EXIT coverage is not needed for normal operation.
trap 'spinner_stop 2>/dev/null' INT TERM
