#!/usr/bin/env bats
# ledger.bats - Integration tests for the optional Worktree Ledger gate in
# lib/13-ledger.sh and its use by cmd_rm.
#
# These exercise the REAL zsh helpers against a stub `way` binary whose exit
# code and output each test controls. A stub rather than the real Waypoint on
# purpose: this suite must not depend on whether the developer has `way`
# installed, or on which ledger root it happens to be pointed at.
#
# The three behaviours that matter, and why:
#   - Blocked (exit 1) stops the removal, however forceful the caller was. This
#     is the whole point: -f forces git, it does not accept the loss of work
#     nobody has recorded.
#   - Could-not-answer (exit 3) does NOT stop it in `auto` mode. A worktree
#     grove could always remove must not become unremovable merely because
#     Waypoint has nothing to say about it — that is how a safety gate gets
#     switched off within a day.
#   - Absent `way` degrades visibly. "No gate ran" and "the gate passed" must
#     never look alike.

load '../test-helper'

setup() {
  setup_test_environment

  # These tests are ABOUT the integration, so switch it back on. The helper
  # disables it for every other test in the suite.
  export LEDGER_INTEGRATION=auto

  STUB_BIN="$TEST_TEMP_DIR/stub-bin"
  export STUB_BIN
  mkdir -p "$STUB_BIN"

  LEDGER_FNS="$TEST_TEMP_DIR/ledger-fns.zsh"
  export LEDGER_FNS
  cat > "$LEDGER_FNS" <<'STUB'
info() { print -r -- "INFO: $*" >&2; }
ok()   { print -r -- "OK: $*" >&2; }
warn() { print -r -- "WARN: $*" >&2; }
dim()  { print -r -- "DIM: $*" >&2; }
QUIET=false
STUB
  cat "$GROVE_ROOT/lib/13-ledger.sh" >> "$LEDGER_FNS"

  # A worktree for the gate to be asked about.
  WT="$TEST_TEMP_DIR/wt"
  export WT
  mkdir -p "$WT"
}

teardown() {
  teardown_test_environment
}

# Write a stub `way` that exits with $1 and prints $2.
stub_way() {
  local exit_code="$1" message="$2"
  cat > "$STUB_BIN/way" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/way-argv.log"
printf '%s\n' '$message'
exit $exit_code
EOF
  chmod +x "$STUB_BIN/way"
}

run_zsh() {
  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c "source '$LEDGER_FNS'; $1"
}

# Run with no `way` discoverable: a PATH holding only the system tools zsh
# needs, and a HOME with no ~/.local/bin/way or ~/.cargo/bin/way in it.
run_zsh_without_way() {
  mkdir -p "$TEST_TEMP_DIR/nohome"
  run env PATH="/usr/bin:/bin" GROVE_WAY_BIN="" HOME="$TEST_TEMP_DIR/nohome" \
    zsh -c "source '$LEDGER_FNS'; $1"
}

@test "ledger: a clear check permits removal" {
  stub_way 0 "Removal is safe"
  run_zsh "ledger_check_removal '$WT' ''"
  [ "$status" -eq 0 ]
}

@test "ledger: a blocked check refuses removal and relays the reason verbatim" {
  stub_way 1 "REMOVAL BLOCKED - 1 untracked file is not checkpointed"
  run_zsh "ledger_check_removal '$WT' ''"
  [ "$status" -ne 0 ]
  # The remedy travels with the refusal; a gate that blocks without saying how
  # to proceed is what teaches people to work around it.
  [[ "$output" == *"not checkpointed"* ]]
}

@test "ledger: could-not-answer does not block in auto mode, but says so" {
  stub_way 3 "not a registered worktree"
  run_zsh "ledger_check_removal '$WT' ''"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not consulted"* ]]
}

@test "ledger: could-not-answer DOES block in required mode" {
  stub_way 3 "no worktree ledger root configured"
  run_zsh "LEDGER_INTEGRATION=required; ledger_check_removal '$WT' ''"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not answer"* ]]
}

@test "ledger: an absent way binary degrades visibly rather than silently" {
  run_zsh_without_way "ledger_check_removal '$WT' ''"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable"* ]]
}

@test "ledger: an absent way binary blocks when the integration is required" {
  run_zsh_without_way "LEDGER_INTEGRATION=required; ledger_check_removal '$WT' ''"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "ledger: LEDGER_INTEGRATION=off skips the check entirely" {
  stub_way 1 "REMOVAL BLOCKED"
  run_zsh "LEDGER_INTEGRATION=off; ledger_check_removal '$WT' ''"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/way-argv.log" ]
}

@test "ledger: an acknowledgement token is passed through to way" {
  stub_way 0 "Acknowledgement accepted"
  run_zsh "ledger_check_removal '$WT' 'ack1.tok'"
  [ "$status" -eq 0 ]
  [[ "$(cat "$TEST_TEMP_DIR/way-argv.log")" == *"--override-token ack1.tok"* ]]
}

@test "ledger: a refused token still blocks the removal" {
  stub_way 1 "this acknowledgement token has already been used"
  run_zsh "ledger_check_removal '$WT' 'ack1.spent'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already been used"* ]]
}

@test "ledger: no token means no --override-token argument" {
  stub_way 0 "clear"
  run_zsh "ledger_check_removal '$WT' ''"
  [[ "$(cat "$TEST_TEMP_DIR/way-argv.log")" != *"--override-token"* ]]
}

@test "ledger: registration failure never fails the caller" {
  stub_way 1 "no worktree ledger root configured"
  run_zsh "ledger_register '$WT'; print -r -- 'reached'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reached"* ]]
}

@test "ledger: registration is skipped entirely when the integration is off" {
  stub_way 0 "registered"
  run_zsh "LEDGER_INTEGRATION=off; ledger_register '$WT'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/way-argv.log" ]
}

@test "ledger: a move reconciles the recorded path without failing the caller" {
  stub_way 1 "not registered"
  run_zsh "ledger_moved '$WT'; print -r -- 'reached'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reached"* ]]
}

@test "ledger: GROVE_WAY_BIN overrides discovery" {
  cat > "$TEST_TEMP_DIR/custom-way" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/custom-way"
  run env GROVE_WAY_BIN="$TEST_TEMP_DIR/custom-way" PATH="/usr/bin:/bin" \
    zsh -c "source '$LEDGER_FNS'; way_binary"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TEST_TEMP_DIR/custom-way" ]]
}

@test "ledger: a worktree directory that no longer exists is not treated as blocked" {
  stub_way 1 "REMOVAL BLOCKED"
  run_zsh "ledger_check_removal '$TEST_TEMP_DIR/gone' ''"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Batch overlay: one `way` process per listing
# ============================================================================

# A `way` that answers `worktree overlay --json` with one known row and
# refuses everything else the way an older binary would (exit 2).
stub_way_with_overlay() {
  cat > "$STUB_BIN/way" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/way-argv.log"
case "\$*" in
  *"worktree overlay"*)
    printf '%s' '{"schema_version":1,"repository":"app","worktrees":[{"available":true,"worktree_id":"wt_batch01","path":"$WT","risk":"warning","risk_available":true,"risk_unavailable_reason":null,"removal_blocked":true,"lease_available":true,"lease_held":false,"lease":null,"unavailable_reason":null}]}'
    exit 0
    ;;
  *)
    printf 'unknown subcommand\n' >&2
    exit 2
    ;;
esac
EOF
  chmod +x "$STUB_BIN/way"
}

@test "ledger: a primed batch answers a row with no further way processes" {
  stub_way_with_overlay
  run_zsh "ledger_overlay_prime '$TEST_TEMP_DIR'; ledger_overlay_json '$WT'; print -r -- \"\$REPLY\"; ledger_overlay_done"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"worktree_id": "wt_batch01"'* || "$output" == *'"worktree_id":"wt_batch01"'* ]]
  # Exactly one way invocation: the batch. No resume, removal-check or lease.
  [ "$(wc -l < "$TEST_TEMP_DIR/way-argv.log")" -eq 1 ]
  [[ "$(cat "$TEST_TEMP_DIR/way-argv.log")" == *"worktree overlay"* ]]
}

@test "ledger: a row the batch does not carry is unavailable, never omitted" {
  stub_way_with_overlay
  mkdir -p "$TEST_TEMP_DIR/unregistered"
  run_zsh "ledger_overlay_prime '$TEST_TEMP_DIR'; ledger_overlay_json '$TEST_TEMP_DIR/unregistered'; print -r -- \"\$REPLY\"; ledger_overlay_done"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"available": false'* ]]
  [[ "$output" == *"not registered in the worktree ledger"* ]]
}

@test "ledger: an older way without the overlay subcommand falls back per row" {
  stub_way 2 "unknown subcommand 'overlay'"
  run_zsh "ledger_overlay_prime '$TEST_TEMP_DIR'; ledger_overlay_json '$WT'; print -r -- \"\$REPLY\""
  [ "$status" -eq 0 ]
  # The legacy three-process path answered: resume failed (exit 2), so the
  # overlay is unavailable with the reason — not silently absent.
  [[ "$output" == *'"available": false'* ]]
  [[ "$(cat "$TEST_TEMP_DIR/way-argv.log")" == *"worktree resume"* ]]
}

@test "ledger: dropping the batch returns rows to the legacy path" {
  stub_way_with_overlay
  run_zsh "ledger_overlay_prime '$TEST_TEMP_DIR'; _batch=\"\$_LEDGER_BATCH_FILE\"; ledger_overlay_done; ledger_overlay_json '$WT'; print -r -- \"\$REPLY\"; if [[ -e \"\$_batch\" ]]; then print -r -- 'batch file leaked'; else print -r -- 'batch file removed'; fi"
  [ "$status" -eq 0 ]
  # After done, the legacy path runs (resume via the stub exits 2 for
  # non-overlay calls, so the row reads unavailable) and the file is gone.
  [[ "$output" == *'"available": false'* ]]
  [[ "$output" == *"batch file removed"* ]]
  [[ "$(cat "$TEST_TEMP_DIR/way-argv.log")" == *"worktree resume"* ]]
}

# ============================================================================
# cmd_rm: the gate as the lifecycle actually uses it
# ============================================================================

setup_cmd_rm_harness() {
  RM_FNS="$TEST_TEMP_DIR/rm-fns.zsh"
  export RM_FNS
  cat > "$RM_FNS" <<'STUB'
info() { :; }
ok()   { :; }
warn() { print -r -- "WARN: $*" >&2; }
dim()  { :; }
notify() { :; }
C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_MAGENTA='' C_GREEN='' C_YELLOW='' C_RED='' C_BLUE=''
JSON_OUTPUT=false
FORCE=false
LEDGER_ACK=""
DELETE_BRANCH=false
DROP_DB=false
INTERACTIVE=false
GROVE_URL_SUBDOMAIN=''
error_exit() { print -r -- "ERROR:$1:$2" >&2; exit "${3:-1}"; }
die() { print -r -- "ERROR:$*" >&2; exit 1; }
spinner_stop() { :; }
json_escape() { REPLY="$1"; }
format_json() { print -r -- "$1"; }
to_json_bool() { case "${1:l}" in true|1|yes|on) print -r -- true ;; *) print -r -- false ;; esac }
validate_name() { return 0; }
ensure_bare_repo() { return 0; }
restart_herd_service() { return 0; }
count_lines() { print -r -- 0; }
run_hooks() { return 0; }
is_protected_branch() { return 1; }
slugify_branch() { REPLY="$1"; }
STUB
  cat "$GROVE_ROOT/lib/11-resilience.sh" >> "$RM_FNS"
  cat "$GROVE_ROOT/lib/13-ledger.sh" >> "$RM_FNS"
  cat "$GROVE_ROOT/lib/commands/lifecycle.sh" >> "$RM_FNS"

  GIT_DIR_FIXTURE="$TEST_TEMP_DIR/app.git"
  WT_FIXTURE="$TEST_TEMP_DIR/wt-app"
  export GIT_DIR_FIXTURE WT_FIXTURE
  local seed="$TEST_TEMP_DIR/seed"
  git init -q -b main "$seed"
  git -C "$seed" config user.email t@t.t
  git -C "$seed" config user.name 'Test'
  git -C "$seed" commit -q --allow-empty -m init
  git clone -q --bare "$seed" "$GIT_DIR_FIXTURE"
  git --git-dir="$GIT_DIR_FIXTURE" worktree add -q -b feature/login "$WT_FIXTURE" HEAD
}

run_cmd_rm() {
  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c "
    source '$RM_FNS'
    git_dir_for() { print -r -- '$GIT_DIR_FIXTURE'; }
    resolve_worktree_path() { print -r -- '$WT_FIXTURE'; }
    url_for() { print -r -- 'https://x.test'; }
    db_name_for() { print -r -- 'app__x'; }
    $1
    cmd_rm 'app' 'feature/login'
  "
}

@test "cmd_rm: a blocked ledger stops the removal before git touches anything" {
  setup_cmd_rm_harness
  stub_way 1 "REMOVAL BLOCKED - untracked work"

  run_cmd_rm "FORCE=false"

  [ "$status" -ne 0 ]
  [[ "$output" == *"LEDGER_BLOCKED"* ]]
  [ -d "$WT_FIXTURE" ]
}

@test "cmd_rm: -f alone cannot bypass the ledger gate" {
  # The single most important test in this file. -f forces git; it is not
  # consent to lose work nobody has recorded.
  setup_cmd_rm_harness
  stub_way 1 "REMOVAL BLOCKED - local-only commits"

  run_cmd_rm "FORCE=true"

  [ "$status" -ne 0 ]
  [[ "$output" == *"LEDGER_BLOCKED"* ]]
  [ -d "$WT_FIXTURE" ]
}

@test "cmd_rm: the refusal tells the operator exactly how to proceed" {
  setup_cmd_rm_harness
  stub_way 1 "REMOVAL BLOCKED"

  run_cmd_rm "FORCE=true"

  [[ "$output" == *"removal-check --acknowledge"* ]]
  [[ "$output" == *"--ledger-ack"* ]]
}

@test "cmd_rm: a valid acknowledgement lets the removal through" {
  setup_cmd_rm_harness
  stub_way 0 "Acknowledgement accepted"

  run_cmd_rm "FORCE=true; LEDGER_ACK='ack1.tok'"

  [ "$status" -eq 0 ]
  [ ! -d "$WT_FIXTURE" ]
  [[ "$(cat "$TEST_TEMP_DIR/way-argv.log")" == *"--override-token ack1.tok"* ]]
}

@test "cmd_rm: an unregistered worktree is still removable" {
  setup_cmd_rm_harness
  stub_way 3 "not a registered worktree"

  run_cmd_rm "FORCE=true"

  [ "$status" -eq 0 ]
  [ ! -d "$WT_FIXTURE" ]
}

# ============================================================================
# The optional `ledger` object in status JSON
# ============================================================================

# Build a sourceable file with json_escape plus the real ledger module.
setup_overlay_harness() {
  OVERLAY_FNS="$TEST_TEMP_DIR/overlay-fns.zsh"
  export OVERLAY_FNS
  cat > "$OVERLAY_FNS" <<'STUB'
warn() { :; }
dim()  { :; }
ok()   { :; }
json_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; REPLY="$s"; }
STUB
  cat "$GROVE_ROOT/lib/13-ledger.sh" >> "$OVERLAY_FNS"
}

# Stub a `way` whose `resume --format json` prints $1.
stub_way_resume() {
  cat > "$STUB_BIN/way" <<EOF
#!/bin/sh
cat <<'JSON'
$1
JSON
exit 0
EOF
  chmod +x "$STUB_BIN/way"
}

@test "json: no overlay is emitted when the integration is off" {
  setup_overlay_harness
  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c \
    "source '$OVERLAY_FNS'; LEDGER_INTEGRATION=off; ledger_overlay_json '$WT'; print -r -- \"[\$REPLY]\""
  [ "$status" -eq 0 ]
  # Empty REPLY means the caller omits the key, so an older consumer sees
  # exactly the document it always saw.
  [[ "$output" == "[]" ]]
}

@test "json: the overlay carries the ledger facts when way answers" {
  setup_overlay_harness
  stub_way_resume '{"view":{"worktree_id":"wt_abc","workstream_id":"ws_1","last_checkpoint_at":"2026-08-04T14:30:00Z","narrative":{"next_action":"Run focused UAT"}},"narrative_status":"present","drift":{"since_checkpoint":true}}'

  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c \
    "source '$OVERLAY_FNS'; ledger_overlay_json '$WT'; print -r -- \"\$REPLY\""

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['available'] is True, d
assert d['worktree_id'] == 'wt_abc', d
assert d['next_action'] == 'Run focused UAT', d
assert d['narrative_status'] == 'present', d
assert d['drift'] is True, d
"
}

@test "json: a failing way yields available=false with a reason, never a silent pass" {
  setup_overlay_harness
  stub_way 3 "no worktree ledger root configured"

  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c \
    "source '$OVERLAY_FNS'; ledger_overlay_json '$WT'; print -r -- \"\$REPLY\""

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
# available:false is 'unknown', NOT 'nothing at risk' — and it must say why.
assert d['available'] is False, d
assert d['unavailable_reason'], d
"
}

@test "json: unreadable resume output degrades to available=false rather than corrupting the document" {
  setup_overlay_harness
  stub_way_resume 'this is not json at all'

  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c \
    "source '$OVERLAY_FNS'; ledger_overlay_json '$WT'; print -r -- \"\$REPLY\""

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['available'] is False, d
"
}

@test "json: an overlay from a worktree that no longer exists is omitted" {
  setup_overlay_harness
  stub_way_resume '{"view":{"worktree_id":"wt_abc"}}'

  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c \
    "source '$OVERLAY_FNS'; ledger_overlay_json '$TEST_TEMP_DIR/gone'; print -r -- \"[\$REPLY]\""

  [ "$status" -eq 0 ]
  [[ "$output" == "[]" ]]
}

# ============================================================================
# Risk and lease in the overlay
#
# `resume` has never carried a risk, so `risk` was hardcoded null and Grove's
# overlay could not show one however dangerous the worktree was. It now also
# asks `removal-check` (which computes risk) and `lease status` (who is working
# here). Both are read-only, and both carry their OWN availability flag: a null
# risk from an answered check means "nothing found", a null risk from a check
# that could not run means "unknown", and rendering those the same way is
# exactly how a safety gate silently stops mattering.
# ============================================================================

# Stub a `way` that answers each subcommand differently.
#   $1 - resume stdout        $2 - resume exit
#   $3 - removal-check stdout $4 - removal-check exit
#   $5 - lease stdout         $6 - lease exit
# Non-zero exits print their body on stderr, as the real `way` does for errors;
# removal-check is the exception the code cares about, and it is covered
# explicitly below.
stub_way_dispatch() {
  cat > "$STUB_BIN/way" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/way-argv.log"
case "\$*" in
  *resume*)
    printf '%s\n' '$1'; exit $2 ;;
  *removal-check*)
    if [ "$4" -eq 0 ] || [ "$4" -eq 1 ]; then printf '%s\n' '$3'; else printf '%s\n' '$3' >&2; fi
    exit $4 ;;
  *lease*)
    if [ "$6" -eq 0 ]; then printf '%s\n' '$5'; else printf '%s\n' '$5' >&2; fi
    exit $6 ;;
esac
exit 2
EOF
  chmod +x "$STUB_BIN/way"
}

overlay_of() {
  run env PATH="$STUB_BIN:$PATH" GROVE_WAY_BIN="" zsh -c \
    "source '$OVERLAY_FNS'; ledger_overlay_json '$WT'; print -r -- \"\$REPLY\""
}

RESUME_OK='{"view":{"worktree_id":"wt_abc","last_checkpoint_at":"2026-08-04T14:30:00Z"},"narrative_status":"present","drift":{"since_checkpoint":false}}'
CHECK_BLOCKED='{"worktree_id":"wt_abc","removal_blocked":true,"highest_risk":"critical","risks":[{"level":"critical","code":"dirty-uncheckpointed","detail":"d","remedy":"r"}],"freshness":"live"}'
CHECK_CLEAR='{"worktree_id":"wt_abc","removal_blocked":false,"highest_risk":null,"risks":[],"freshness":"live"}'
LEASE_NONE='{"worktree_id":"wt_abc","held":false,"lease":null}'

@test "json: a BLOCKED removal-check is an answer — its risk reaches the overlay" {
  setup_overlay_harness
  # Exit 1 with the document on stdout. Treating a block as a failure would
  # throw away the one answer that matters most.
  stub_way_dispatch "$RESUME_OK" 0 "$CHECK_BLOCKED" 1 "$LEASE_NONE" 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['available'] is True, d
assert d['risk'] == 'critical', d
assert d['risk_available'] is True, d
assert d['removal_blocked'] is True, d
assert d['risk_unavailable_reason'] is None, d
"
}

@test "json: a clear removal-check reports no risk as an ANSWER, not as unknown" {
  setup_overlay_harness
  stub_way_dispatch "$RESUME_OK" 0 "$CHECK_CLEAR" 0 "$LEASE_NONE" 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
# risk null AND risk_available true is the only combination that means safe.
assert d['risk'] is None, d
assert d['risk_available'] is True, d
assert d['removal_blocked'] is False, d
"
}

@test "json: a removal-check that could not answer leaves risk UNKNOWN, never clear" {
  setup_overlay_harness
  stub_way_dispatch "$RESUME_OK" 0 "no worktree ledger root configured" 3 "$LEASE_NONE" 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['risk'] is None, d
assert d['risk_available'] is False, d
assert d['risk_unavailable_reason'], d
# Not derivable either: Grove must not infer 'not blocked' from silence.
assert d['removal_blocked'] is None, d
# The rest of the overlay still stands — resume answered.
assert d['available'] is True, d
assert d['worktree_id'] == 'wt_abc', d
"
}

@test "json: a usage error from removal-check is unknown risk, not clear risk" {
  setup_overlay_harness
  stub_way_dispatch "$RESUME_OK" 0 "unrecognised option" 2 "$LEASE_NONE" 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['risk_available'] is False, d
assert d['removal_blocked'] is None, d
"
}

@test "json: a removal-check reply carrying no decision is not an answer" {
  setup_overlay_harness
  # Exit 0 and valid JSON, but no removal_blocked field — an older `way`, or a
  # different command's output. Shape is what makes it an answer, not exit 0.
  stub_way_dispatch "$RESUME_OK" 0 '{"worktree_id":"wt_abc"}' 0 "$LEASE_NONE" 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['risk_available'] is False, d
assert d['risk_unavailable_reason'], d
"
}

@test "json: a live lease names its holder so Grove can show an agent is working here" {
  setup_overlay_harness
  stub_way_dispatch "$RESUME_OK" 0 "$CHECK_CLEAR" 0 \
    '{"worktree_id":"wt_abc","held":true,"lease":{"tool":"claude","session_id":"s1","machine_id":"machine_x","acquired_at":"2026-08-06T08:00:00Z","last_heartbeat_at":"2026-08-06T08:20:00Z","expires_at":"2026-08-06T08:50:00Z"}}' 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['lease_available'] is True, d
assert d['lease_held'] is True, d
assert d['lease']['tool'] == 'claude', d
assert d['lease']['session_id'] == 's1', d
assert d['lease']['machine_id'] == 'machine_x', d
assert d['lease']['expires_at'] == '2026-08-06T08:50:00Z', d
"
}

@test "json: an EXPIRED lease still names who held it, and is not reported as held" {
  setup_overlay_harness
  stub_way_dispatch "$RESUME_OK" 0 "$CHECK_CLEAR" 0 \
    '{"worktree_id":"wt_abc","held":false,"lease":{"tool":"codex","session_id":"s9","machine_id":"machine_y","acquired_at":"2026-08-05T08:00:00Z","last_heartbeat_at":"2026-08-05T08:20:00Z","expires_at":"2026-08-05T08:50:00Z"}}' 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['lease_available'] is True, d
assert d['lease_held'] is False, d
# Expired is not absent: the last holder is still a fact worth showing.
assert d['lease']['tool'] == 'codex', d
"
}

@test "json: a lease that could not be read is unknown, not 'nobody is working here'" {
  setup_overlay_harness
  stub_way_dispatch "$RESUME_OK" 0 "$CHECK_CLEAR" 0 'wt_abc is not registered' 1
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['lease_available'] is False, d
assert d['lease_unavailable_reason'], d
assert d['lease_held'] is None, d
assert d['lease'] is None, d
"
}

@test "json: building the overlay NEVER acknowledges or overrides anything" {
  setup_overlay_harness
  stub_way_dispatch "$RESUME_OK" 0 "$CHECK_BLOCKED" 1 "$LEASE_NONE" 0
  overlay_of
  [ "$status" -eq 0 ]

  # Listing worktrees must never issue or spend an override. That is a
  # deliberate command-line act, recorded and single-use, and it must not be
  # reachable as a side effect of drawing a row.
  run cat "$TEST_TEMP_DIR/way-argv.log"
  [[ "$output" != *"--acknowledge"* ]]
  [[ "$output" != *"--override-token"* ]]
  # And it really did ask all three questions.
  [[ "$output" == *"resume"* ]]
  [[ "$output" == *"removal-check"* ]]
  [[ "$output" == *"lease status"* ]]
}

@test "json: BOTH row builders carry the overlay — ls is the one Grove desktop reads" {
  # The overlay was wired into `grove status --json` only, while Grove desktop
  # calls `grove ls <repo> --json` (get_worktrees, grove/src-tauri/src/wt.rs).
  # The result was an overlay that no consumer ever saw and badges that could
  # never render. Whichever row builder gains a field, the other needs it too.
  local ls_row status_row
  ls_row="$(awk '/^_display_worktree\(\)/,/^}$/' "$GROVE_ROOT/lib/commands/info.sh" | grep -c 'ledger_overlay_json' || true)"
  status_row="$(awk '/^_display_status_row\(\)/,/^}$/' "$GROVE_ROOT/lib/commands/info.sh" | grep -c 'ledger_overlay_json' || true)"
  [ "$ls_row" -ge 1 ]
  [ "$status_row" -ge 1 ]
}

@test "json: a failing resume makes the WHOLE overlay unavailable, risk included" {
  setup_overlay_harness
  # resume is where the identity comes from; without it there is nothing to
  # hang a risk on, so this stays the one failure that unavailables everything.
  stub_way_dispatch "not registered" 3 "$CHECK_BLOCKED" 1 "$LEASE_NONE" 0
  overlay_of

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['available'] is False, d
assert d['unavailable_reason'], d
assert 'risk' not in d or d['risk'] is None, d
"
}

# --- archiving on removal --------------------------------------------------
#
# Slice 2 specified a `post-rm` archive and it was never written, so every
# worktree grove removed stayed `active` in the ledger for ever. `doctor` kept
# counting folders that no longer exist, which is precisely the "the record
# disagrees with the disk" failure the ledger is meant to catch.
#
# The id has to be read BEFORE the folder goes, and the archive issued AFTER —
# so these are two functions, and neither may ever fail a removal.

@test "ledger: the worktree id is captured before removal" {
  cat > "$STUB_BIN/way" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/way-argv.log"
printf '%s\n' '{"view":{"worktree_id":"wt_abc123"}}'
exit 0
EOF
  chmod +x "$STUB_BIN/way"
  run_zsh "ledger_worktree_id '$WT'; print -r -- \"\$REPLY\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"wt_abc123"* ]]
}

@test "ledger: archiving names the worktree by id and records the reason" {
  stub_way 0 "archived wt_abc123"
  run_zsh "ledger_archive 'wt_abc123' 'removed by grove'"
  [ "$status" -eq 0 ]
  run cat "$TEST_TEMP_DIR/way-argv.log"
  [[ "$output" == *"worktree archive"* ]]
  [[ "$output" == *"--worktree-id wt_abc123"* ]]
  [[ "$output" == *"--reason removed by grove"* ]]
}

@test "ledger: a failed archive never fails the removal that already happened" {
  # The worktree is already gone by this point. Turning a bookkeeping failure
  # into a non-zero exit would report a successful removal as a failure.
  stub_way 1 "ledger unreachable"
  run_zsh "ledger_archive 'wt_abc123' 'removed by grove'"
  [ "$status" -eq 0 ]
}

@test "ledger: an absent way binary makes archiving a no-op, not an error" {
  run_zsh_without_way "ledger_archive 'wt_abc123' 'removed by grove'"
  [ "$status" -eq 0 ]
}

@test "ledger: LEDGER_INTEGRATION=off skips archiving entirely" {
  stub_way 0 "archived"
  run_zsh "LEDGER_INTEGRATION=off; ledger_archive 'wt_abc123' 'removed by grove'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/way-argv.log" ]
}

@test "ledger: archiving without an id does nothing rather than guessing" {
  stub_way 0 "archived"
  run_zsh "ledger_archive '' 'removed by grove'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/way-argv.log" ]
}
