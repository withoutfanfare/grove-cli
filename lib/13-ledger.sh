#!/usr/bin/env zsh
# 13-ledger.sh - Optional Worktree Ledger integration (Waypoint's `way` CLI)
#
# Grove owns the worktree lifecycle; Waypoint owns whether a worktree still
# holds work nobody has recorded. This module is the seam between them, and it
# has three rules:
#
#   1. Optional. No `way` on PATH, or LEDGER_INTEGRATION=off, and grove behaves
#      exactly as it always has. The degraded mode is announced on stderr, never
#      silent, because "no gate ran" and "the gate passed" must never look alike.
#   2. Fails closed on risk, open on absence. A `way` that says "blocked" stops
#      the removal. A `way` that cannot answer at all does not.
#   3. `-f` is not consent. Forcing git and accepting the loss of uncommitted
#      work are different decisions. Only a one-use token from
#      `way worktree removal-check --acknowledge` opens this gate.
#
# Grove never parses the ledger's Markdown, and never decides what is risky. It
# asks, relays the answer verbatim, and obeys the exit code.

# way_binary — Print the `way` binary to use, or return 1 when unavailable
#
# A GUI-launched process does not inherit the shell PATH, so the usual install
# locations are probed as well.
way_binary() {
  local candidate
  for candidate in "${GROVE_WAY_BIN:-}" way "$HOME/.local/bin/way" "$HOME/.cargo/bin/way" \
    /opt/homebrew/bin/way /usr/local/bin/way; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" >/dev/null 2>&1; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

# ledger_enabled — Whether the ledger gate should run at all
#
# LEDGER_INTEGRATION (config or environment):
#   auto     - use the ledger when `way` is available (default)
#   off      - never use it
#   required - use it, and treat an unavailable `way` as a failure
ledger_enabled() {
  local mode="${LEDGER_INTEGRATION:-auto}"
  [[ "$mode" == "off" ]] && return 1
  return 0
}

# ledger_check_removal — Ask the ledger whether a worktree may be removed
#
# Arguments:
#   $1 - worktree path
#   $2 - acknowledgement token, or empty
#
# Returns:
#   0 - removal may proceed (clear, acknowledged, or the ledger is unavailable
#       in `auto` mode)
#   1 - removal is blocked; the reason has already been printed to stderr
#
# Human-readable output from `way` is relayed verbatim rather than summarised:
# it carries the remedy for each risk, and a gate that blocks without saying how
# to proceed is exactly what teaches people to reach for -f.
ledger_check_removal() {
  local wt_path="$1"
  local token="${2:-}"
  local mode="${LEDGER_INTEGRATION:-auto}"

  ledger_enabled || return 0

  local way_bin=""
  if ! way_bin="$(way_binary)"; then
    if [[ "$mode" == "required" ]]; then
      warn "LEDGER_INTEGRATION=required but the 'way' binary was not found"
      return 1
    fi
    dim "  Worktree ledger unavailable ('way' not found) - removal not checked"
    return 0
  fi

  [[ -d "$wt_path" ]] || return 0

  local -a args
  args=(worktree removal-check)
  [[ -n "$token" ]] && args+=(--override-token "$token")

  # Run from inside the worktree: `way` detects which worktree it is from cwd.
  local output="" exit_code=0
  output="$(cd "$wt_path" && "$way_bin" "${args[@]}" 2>&1)" || exit_code=$?

  case $exit_code in
    0)
      [[ -n "$token" ]] && ok "Ledger acknowledgement accepted"
      return 0
      ;;
    1)
      # Blocked, or the token was refused. Either way `way` has explained it.
      print -r -- "$output" >&2
      return 1
      ;;
    *)
      # Usage errors, an unregistered worktree, or no ledger root configured.
      # None of these is evidence that the worktree is unsafe, so in `auto` mode
      # grove carries on — but says so, so the gap is visible.
      if [[ "$mode" == "required" ]]; then
        warn "Worktree ledger could not answer (exit $exit_code):"
        print -r -- "$output" >&2
        return 1
      fi
      dim "  Worktree ledger not consulted: ${output%%$'\n'*}"
      return 0
      ;;
  esac
}

# ledger_register — Register a newly created worktree, best effort
#
# Never fails the caller: a worktree that exists but is unregistered is a gap to
# report, not a reason to undo a successful `grove add`.
ledger_register() {
  local wt_path="$1"

  ledger_enabled || return 0
  local way_bin=""
  way_bin="$(way_binary)" || return 0
  [[ -d "$wt_path" ]] || return 0

  local output="" exit_code=0
  output="$(cd "$wt_path" && "$way_bin" worktree register 2>&1)" || exit_code=$?
  if (( exit_code == 0 )); then
    dim "  Registered in the worktree ledger"
  else
    dim "  Worktree ledger registration skipped: ${output%%$'\n'*}"
  fi
  return 0
}

# ledger_moved — Reconcile a worktree's recorded path after a move, best effort
ledger_moved() {
  local wt_path="$1"

  ledger_enabled || return 0
  local way_bin=""
  way_bin="$(way_binary)" || return 0
  [[ -d "$wt_path" ]] || return 0

  (cd "$wt_path" && "$way_bin" worktree moved >/dev/null 2>&1) || true
  return 0
}
