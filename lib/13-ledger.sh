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

# ledger_worktree_id — Set REPLY to a worktree's ledger id, or the empty string
#
# Must be called BEFORE removal. Once the folder has gone there is nowhere to
# stand and no sidecar to read, so the id is the only handle left on the record.
ledger_worktree_id() {
  REPLY=""

  ledger_enabled || return 0
  local way_bin=""
  way_bin="$(way_binary)" || return 0
  [[ -d "$1" ]] || return 0

  local output=""
  output="$(cd "$1" && "$way_bin" worktree resume --format json 2>/dev/null)" || return 0
  [[ -n "$output" ]] || return 0

  # One python pass rather than shell string-mangling: this is Waypoint's JSON,
  # and a half-parsed id would archive the wrong record.
  REPLY="$(print -r -- "$output" | python3 -c '
import json, sys

try:
    brief = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
print((brief.get("view") or {}).get("worktree_id") or "")
' 2>/dev/null)" || REPLY=""
  return 0
}

# ledger_archive — Record that a removed worktree is finished with
#
# Best effort, always, and deliberately so: by the time this runs the worktree
# is already gone. Turning a bookkeeping failure into a non-zero exit would
# report a successful removal as a failure.
#
# Without this the ledger keeps every removed worktree `active` for ever —
# `doctor` counts folders that do not exist, which is the same "record
# disagrees with the disk" problem the ledger exists to catch.
ledger_archive() {
  local worktree_id="$1"
  local reason="${2:-removed by grove}"

  # No id means the worktree was never registered, or `way` could not be asked
  # before removal. Guessing which record to close would be worse than leaving
  # it open.
  [[ -n "$worktree_id" ]] || return 0
  ledger_enabled || return 0
  local way_bin=""
  way_bin="$(way_binary)" || return 0

  local output="" exit_code=0
  output="$("$way_bin" worktree archive --worktree-id "$worktree_id" --reason "$reason" 2>&1)" \
    || exit_code=$?

  if (( exit_code == 0 )); then
    dim "  Archived in the worktree ledger"
  else
    dim "  Worktree ledger archive skipped: ${output%%$'\n'*}"
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

# ledger_overlay_json — Build the optional `ledger` object for a worktree
#
# Sets REPLY to a JSON object, or to the empty string when the integration is
# off or `way` is absent — in which case callers omit the key entirely and an
# older consumer sees exactly the document it always saw.
#
# `available: false` is NOT "nothing at risk". It carries `unavailable_reason`,
# and a consumer must render it as "unknown", never as safe. That distinction is
# the whole reason this is a nested object rather than a handful of flat fields
# that default to false.
#
# Grove never parses ledger Markdown: this is Waypoint's own JSON, relayed.
ledger_overlay_json() {
  REPLY=""

  ledger_enabled || return 0
  local way_bin=""
  way_bin="$(way_binary)" || return 0
  [[ -d "$1" ]] || return 0

  local output="" exit_code=0
  output="$(cd "$1" && "$way_bin" worktree resume --format json 2>&1)" || exit_code=$?

  if (( exit_code != 0 )); then
    json_escape "${output%%$'\n'*}"
    REPLY="{\"available\": false, \"unavailable_reason\": \"$REPLY\"}"
    return 0
  fi

  # Reshape Waypoint's brief into the published overlay. Done with a single
  # python pass rather than shell string-mangling because a malformed object
  # here would corrupt the whole status document.
  local overlay=""
  overlay="$(print -r -- "$output" | python3 -c '
import json, sys

try:
    brief = json.load(sys.stdin)
except Exception as error:
    print(json.dumps({"available": False, "unavailable_reason": f"unreadable resume JSON: {error}"}))
    raise SystemExit(0)

view = brief.get("view", {})
narrative = view.get("narrative") or {}
print(json.dumps({
    "available": True,
    "worktree_id": view.get("worktree_id"),
    "workstream_id": view.get("workstream_id"),
    # Slice 2 populates risk through `removal-check`; resume does not carry it,
    # so it is explicitly null here rather than guessed.
    "risk": None,
    "checkpoint_at": view.get("last_checkpoint_at"),
    "next_action": narrative.get("next_action"),
    "narrative_status": brief.get("narrative_status"),
    "drift": (brief.get("drift") or {}).get("since_checkpoint"),
    "unavailable_reason": None,
}))
' 2>/dev/null)" || overlay=""

  if [[ -z "$overlay" ]]; then
    REPLY="{\"available\": false, \"unavailable_reason\": \"could not read the ledger overlay\"}"
  else
    REPLY="$overlay"
  fi
  return 0
}
