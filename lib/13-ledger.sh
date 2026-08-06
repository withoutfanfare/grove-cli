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

# ── Batch overlay ────────────────────────────────────────────────────────────
#
# `way worktree overlay --json` (Waypoint's way-worktree-overlay-v1 contract)
# answers for EVERY worktree of a repository in one process. A listing primes
# the batch once, each row looks itself up by path, and the per-row
# three-process path below survives only as the fallback for an older `way`
# without the subcommand. The batch lands in a temp file, not a variable,
# because parallel_collect renders rows in subshells.

typeset -g _LEDGER_BATCH_FILE=""

# ledger_overlay_prime — Fetch the whole repository's overlay in one `way` call
#
# $1 is any directory inside the repository — the bare git dir works. On ANY
# failure (older `way`, no ledger root, integration off) the batch file is
# absent and every row falls back to ledger_overlay_json_legacy, so behaviour
# degrades to exactly what shipped before this function existed.
ledger_overlay_prime() {
  local git_dir="$1"
  _LEDGER_BATCH_FILE=""
  ledger_enabled || return 0
  local way_bin=""
  way_bin="$(way_binary)" || return 0
  [[ -d "$git_dir" ]] || return 0

  local out=""
  out="$(mktemp "${TMPDIR:-/tmp}/grove-ledger-batch.XXXXXX")" || return 0
  if ( cd "$git_dir" && "$way_bin" worktree overlay --json >"$out" 2>/dev/null ); then
    _LEDGER_BATCH_FILE="$out"
  else
    rm -f "$out"
  fi
  return 0
}

# ledger_overlay_done — Drop the batch, returning rows to the legacy path
ledger_overlay_done() {
  [[ -n "$_LEDGER_BATCH_FILE" ]] && rm -f "$_LEDGER_BATCH_FILE"
  _LEDGER_BATCH_FILE=""
  return 0
}

# ledger_overlay_json — Build the optional `ledger` object for a worktree
#
# Sets REPLY exactly as ledger_overlay_json_legacy always has: a JSON object,
# or the empty string when the integration is off or `way` is absent. When a
# batch is primed, the row is one file lookup instead of three `way`
# processes; a row the batch does not carry is a worktree the ledger has no
# record of, which is the same "unavailable, with the reason" answer a failed
# `resume` produces today — never silently safe, never silently omitted.
ledger_overlay_json() {
  REPLY=""
  if [[ -z "$_LEDGER_BATCH_FILE" || ! -r "$_LEDGER_BATCH_FILE" ]]; then
    ledger_overlay_json_legacy "$1"
    return 0
  fi

  REPLY="$(python3 -c '
import json, os, sys

batch_path, wt_path = sys.argv[1], sys.argv[2]
try:
    with open(batch_path, encoding="utf-8") as handle:
        batch = json.load(handle)
except Exception:
    raise SystemExit(0)

wanted = os.path.realpath(wt_path)
for row in batch.get("worktrees") or []:
    path = row.get("path")
    if path and os.path.realpath(path) == wanted:
        print(json.dumps(row))
        raise SystemExit(0)

# Registered nowhere in the batch: the same answer a failed resume gives on
# the per-row path — unavailable, with the reason, never rendered as safe.
print(json.dumps({
    "available": False,
    "unavailable_reason": "not registered in the worktree ledger",
}))
' "$_LEDGER_BATCH_FILE" "$1" 2>/dev/null)" || REPLY=""
  [[ -n "$REPLY" ]] || ledger_overlay_json_legacy "$1"
  return 0
}

# ledger_overlay_json_legacy — The per-worktree overlay, three processes
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
# THREE questions, three commands, because no single `way` command answers all
# of them:
#   - `resume`        — identity, checkpoint, next action, drift. Without it
#                       there is no worktree_id, so a failure here is the only
#                       thing that makes the WHOLE overlay unavailable.
#   - `removal-check` — the risk. `resume` has never carried one, which is why
#                       `risk` was hardcoded null and the overlay could never
#                       show it.
#   - `lease status`  — who, if anyone, is working here.
#
# Risk and lease carry their OWN availability flags rather than folding into
# `available`, so "resume answered but the risk could not be established" stays
# distinguishable from "no risk found". A consumer that cannot tell those apart
# renders unknown as safe, which is the failure this whole system exists to
# prevent.
#
# The three run CONCURRENTLY. Sequentially they more than double `grove ls`
# (measured: resume ~440ms, removal-check ~410ms, lease ~110ms per worktree).
# Rows are processed one at a time, so this is at most three `way` processes at
# once. All three are read-only — no `--acknowledge`, no `--override-token`,
# ever. Issuing or spending an override is a deliberate command-line act and
# must never be a side effect of listing worktrees.
#
# Grove never parses ledger Markdown: this is Waypoint's own JSON, relayed.
ledger_overlay_json_legacy() {
  REPLY=""

  ledger_enabled || return 0
  local way_bin=""
  way_bin="$(way_binary)" || return 0
  [[ -d "$1" ]] || return 0

  local scratch=""
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/grove-ledger.XXXXXX")" || {
    REPLY='{"available": false, "unavailable_reason": "could not create a temporary directory for the ledger overlay"}'
    return 0
  }

  # stdout and stderr are kept apart on purpose: `removal-check` prints its JSON
  # to stdout and still exits 1 when it blocks, so a block is an ANSWER whose
  # body must survive. Merging the streams would let a stderr warning corrupt it.
  local resume_pid removal_pid lease_pid
  ( cd "$1" && "$way_bin" worktree resume --format json \
      >"$scratch/resume.out" 2>"$scratch/resume.err" ) &
  resume_pid=$!
  ( cd "$1" && "$way_bin" worktree removal-check --json \
      >"$scratch/removal.out" 2>"$scratch/removal.err" ) &
  removal_pid=$!
  ( cd "$1" && "$way_bin" worktree lease status --json \
      >"$scratch/lease.out" 2>"$scratch/lease.err" ) &
  lease_pid=$!

  # `set -e` is in force: a non-zero `wait` would abort grove outright, and
  # exit 1 from removal-check is an ordinary, expected answer.
  local resume_rc=0 removal_rc=0 lease_rc=0
  wait "$resume_pid" || resume_rc=$?
  wait "$removal_pid" || removal_rc=$?
  wait "$lease_pid" || lease_rc=$?

  # Reshape Waypoint's three answers into the published overlay. Done with a
  # single python pass rather than shell string-mangling because a malformed
  # object here would corrupt the whole status document.
  local overlay=""
  overlay="$(python3 -c '
import json, sys

scratch = sys.argv[1]
resume_rc, removal_rc, lease_rc = (int(code) for code in sys.argv[2:5])


def read(name):
    try:
        with open(f"{scratch}/{name}", encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def first_line(text, fallback):
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line
    return fallback


# --- resume: identity, and the whole overlay stands or falls on it ----------
if resume_rc != 0:
    reason = first_line(
        read("resume.err") + read("resume.out"),
        f"way worktree resume exited {resume_rc}",
    )
    print(json.dumps({"available": False, "unavailable_reason": reason}))
    raise SystemExit(0)

try:
    brief = json.loads(read("resume.out"))
except Exception as error:
    print(json.dumps({"available": False, "unavailable_reason": f"unreadable resume JSON: {error}"}))
    raise SystemExit(0)

view = brief.get("view", {})
narrative = view.get("narrative") or {}

# --- removal-check: the risk ------------------------------------------------
# Exit 0 (clear) and exit 1 (blocked) are both answers, and both print the
# RemovalCheck document to stdout. Exit 2 (usage) and exit 3 (could not answer)
# are not answers, and must not read as "no risk".
risk = None
risk_available = False
risk_unavailable_reason = None
removal_blocked = None

if removal_rc in (0, 1):
    try:
        check = json.loads(read("removal.out"))
    except Exception as error:
        check = None
        risk_unavailable_reason = f"unreadable removal-check JSON: {error}"
    # A document that does not carry a removal decision has not answered the
    # question asked, whatever else is in it.
    if isinstance(check, dict) and isinstance(check.get("removal_blocked"), bool):
        risk_available = True
        risk = check.get("highest_risk")
        removal_blocked = check["removal_blocked"]
    elif risk_unavailable_reason is None:
        risk_unavailable_reason = "removal-check returned no removal decision"
else:
    risk_unavailable_reason = first_line(
        read("removal.err") + read("removal.out"),
        f"way worktree removal-check exited {removal_rc}",
    )

# --- lease status: who is working here --------------------------------------
# `lease status` reports rather than gates, so it exits 0 whether or not a
# lease is held; anything non-zero means it could not tell us.
lease = None
lease_held = None
lease_available = False
lease_unavailable_reason = None

if lease_rc == 0:
    try:
        status = json.loads(read("lease.out"))
    except Exception as error:
        status = None
        lease_unavailable_reason = f"unreadable lease JSON: {error}"
    if isinstance(status, dict) and isinstance(status.get("held"), bool):
        lease_available = True
        lease_held = status["held"]
        holder = status.get("lease")
        lease = holder if isinstance(holder, dict) else None
    elif lease_unavailable_reason is None:
        lease_unavailable_reason = "lease status did not say whether the worktree is held"
else:
    lease_unavailable_reason = first_line(
        read("lease.err") + read("lease.out"),
        f"way worktree lease status exited {lease_rc}",
    )

print(json.dumps({
    "available": True,
    "worktree_id": view.get("worktree_id"),
    "workstream_id": view.get("workstream_id"),
    # Populated from removal-check. Null means EITHER no risk found (when
    # risk_available is true) OR the risk could not be established (when it is
    # false) — the flag is what tells them apart, and null alone never means safe.
    "risk": risk,
    "risk_available": risk_available,
    "risk_unavailable_reason": risk_unavailable_reason,
    # Relayed, never derived. Whether a risk blocks removal is a rule the
    # ledger states and Grove only repeats.
    "removal_blocked": removal_blocked,
    "lease_available": lease_available,
    "lease_unavailable_reason": lease_unavailable_reason,
    "lease_held": lease_held,
    "lease": lease,
    "checkpoint_at": view.get("last_checkpoint_at"),
    "next_action": narrative.get("next_action"),
    "narrative_status": brief.get("narrative_status"),
    "drift": (brief.get("drift") or {}).get("since_checkpoint"),
    "unavailable_reason": None,
}))
' "$scratch" "$resume_rc" "$removal_rc" "$lease_rc" 2>/dev/null)" || overlay=""

  rm -rf "$scratch"

  if [[ -z "$overlay" ]]; then
    REPLY='{"available": false, "unavailable_reason": "could not read the ledger overlay"}'
  else
    REPLY="$overlay"
  fi
  return 0
}
