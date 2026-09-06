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
removal_check_binary() {
  local candidate
  for candidate in "${GROVE_REMOVAL_CHECK_BIN:-}" wt-removal-check \
    "$HOME/.local/bin/wt-removal-check" "$HOME/.claude/bin/wt-removal-check"; do
    [[ -n "$candidate" ]] || continue
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
    REPLY="the worktree removal gate (wt-removal-check) was not found, so unsaved work cannot be ruled out"
    return 1
  fi

  local verdict=""
  verdict="$("$gate" "$wt_path" 2>&1)" && return 0
  REPLY="$verdict"
  return 1
}
