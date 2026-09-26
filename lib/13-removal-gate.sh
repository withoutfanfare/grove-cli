#!/usr/bin/env zsh
# 13-removal-gate.sh - The worktree removal gate (`wt-removal-check`)
#
# One script answers "would removing this worktree lose anything?": uncommitted
# changes, commits no remote has, or a live agent session working there. Grove
# asks it before every removal and relays the answer verbatim. Two rules:
#
#   1. `-f` is not consent. Forcing git and accepting the loss of unsaved work
#      are different decisions, so the gate runs regardless of $FORCE. Past a
#      block there is only the interactive confirmation; --json has no bypass.
#   2. A missing gate is a failure, not a pass. The gate IS grove's check for
#      unsaved work, so when it cannot run the removal stops and says why —
#      "no gate ran" and "the gate passed" must never look alike.

# removal_check_binary — Print the `wt-removal-check` to use, or return 1
#
# A GUI-launched process does not inherit the shell PATH, so the install
# locations are probed as well.
#
# An explicit GROVE_REMOVAL_CHECK_BIN is used alone: when it names nothing
# runnable, falling back to another gate would silently drop the one the user
# chose, so it fails instead.
removal_check_binary() {
  if [[ -n "${GROVE_REMOVAL_CHECK_BIN:-}" ]]; then
    command -v "$GROVE_REMOVAL_CHECK_BIN" >/dev/null 2>&1 || return 1
    print -r -- "$GROVE_REMOVAL_CHECK_BIN"
    return 0
  fi

  local candidate
  for candidate in wt-removal-check \
    "$HOME/.local/bin/wt-removal-check" "$HOME/.claude/bin/wt-removal-check"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

# removal_gate — Ask the gate whether a worktree may be removed
#
# Arguments:
#   $1 - worktree path
#
# Returns:
#   0 - nothing would be lost (REPLY is empty)
#   1 - blocked; REPLY holds the gate's account of what would be lost, or why
#       it could not answer
#
# The gate's output is relayed rather than summarised: it names each file and
# commit that would go, and a gate that blocks without saying what it is
# protecting is exactly what teaches people to reach for -f.
removal_gate() {
  local wt_path="$1"
  REPLY=""

  local gate=""
  if ! gate="$(removal_check_binary)"; then
    if [[ -n "${GROVE_REMOVAL_CHECK_BIN:-}" ]]; then
      REPLY="GROVE_REMOVAL_CHECK_BIN ($GROVE_REMOVAL_CHECK_BIN) is not an executable, so unsaved work cannot be ruled out"
    else
      REPLY="the worktree removal gate (wt-removal-check) was not found, so unsaved work cannot be ruled out"
    fi
    return 1
  fi

  local verdict=""
  verdict="$("$gate" "$wt_path" 2>&1)" && return 0
  REPLY="$verdict"
  return 1
}

# removal_can_prompt — True when a person at a terminal can answer the prompt
#
# The "Remove anyway?" confirmation is the only way past a block, so it must
# come from a person: piped or redirected stdin (`echo y | grove rm …`) is a
# script accepting a loss on someone's behalf, and is refused like --json.
removal_can_prompt() {
  [[ -t 0 ]]
}
