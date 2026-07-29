#!/usr/bin/env zsh
# 09-parallel.sh - Parallel execution framework

autoload -Uz is-at-least

typeset -ga PARALLEL_PIDS=()
typeset -g PARALLEL_TMPDIR=""
typeset -g PARALLEL_USES_PROCESS_GROUPS=false

# Stop active workers before an interrupt exits Grove. When session support is
# available, signalling -PID reaches each command's children as well as its
# result wrapper; the fallback signals the wrapper PID directly.
parallel_stop() {
  local pid

  for pid in "${PARALLEL_PIDS[@]}"; do
    [[ "$PARALLEL_USES_PROCESS_GROUPS" == "true" ]] && kill -TERM -- "-$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
  done
  (( ${#PARALLEL_PIDS[@]} > 0 )) && sleep 0.05
  for pid in "${PARALLEL_PIDS[@]}"; do
    [[ "$PARALLEL_USES_PROCESS_GROUPS" == "true" ]] && kill -KILL -- "-$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  PARALLEL_PIDS=()
  PARALLEL_USES_PROCESS_GROUPS=false

  if [[ -n "$PARALLEL_TMPDIR" && -d "$PARALLEL_TMPDIR" ]]; then
    rm -rf "$PARALLEL_TMPDIR"
  fi
  PARALLEL_TMPDIR=""
}

# report_results — Display success/failure summary after parallel operations
report_results() {
  local success="$1" failed="$2" total="$3"

  print -r -- ""
  if (( failed == 0 )); then
    ok "All $total operation(s) completed successfully"
  else
    warn "$failed of $total operation(s) failed"
  fi
}

# parallel_run — Execute "label|path|command" operations in parallel with concurrency limiting
#
# CALLING CONVENTION (callers in lib/commands/*.sh MUST match this):
#   parallel_run <result_handler> "<label>|<path>|<command>" ["<label>|<path>|<command>" ...]
#
# Each operation is a single string with THREE pipe-delimited fields:
#   1. label   — human-readable name shown in the summary (e.g. the branch)
#   2. path     — working directory the command runs in (may contain spaces; a
#                 single quote is rejected as a defensive measure, see below)
#   3. command  — the shell command line to run, as a single string
#
# Only the first two '|' separate the fields; any further '|' belong to the
# command. The path and command are passed as SEPARATE argv to a fixed wrapper
# (`sh -c 'cd "$1" && exec sh -c "$2"' _ "$path" "$command"`), so the
# path is never interpolated into a shell string — this is the security boundary
# replacing the old `cd '$path' && ...` quoting (see improvement plan #16).
#
# A MISSING result file is counted as a FAILURE (not silently dropped), so callers
# can rely on total == succeeded + failed.
parallel_run() {
  local result_handler="$1"
  shift
  local operations=("$@")

  local total=${#operations[@]}
  [[ $total -eq 0 ]] && return 0

  # Create temp directory for results (use PATH-resolved mktemp, verify it worked)
  local tmpdir
  tmpdir="$(mktemp -d 2>/dev/null)"
  if [[ -z "$tmpdir" || ! -d "$tmpdir" ]]; then
    error_exit "IO_ERROR" "Failed to create temporary directory for parallel run" 5
  fi
  PARALLEL_TMPDIR="$tmpdir"
  PARALLEL_PIDS=()

  # Prefer a process group so Ctrl-C can stop the shell command and its children.
  # macOS has POSIX::setsid in system Perl; Linux normally provides setsid.
  local -a session_runner
  PARALLEL_USES_PROCESS_GROUPS=false
  if command -v setsid >/dev/null 2>&1; then
    session_runner=(setsid)
    PARALLEL_USES_PROCESS_GROUPS=true
  elif command -v perl >/dev/null 2>&1 && perl -MPOSIX -e 'exit(defined(&POSIX::setsid) ? 0 : 1)' 2>/dev/null; then
    session_runner=(perl -MPOSIX -e 'my $sid = POSIX::setsid(); defined($sid) or die "setsid failed"; exec @ARGV; die "exec failed"')
    PARALLEL_USES_PROCESS_GROUPS=true
  else
    # ponytail: direct-PID cancellation may leave grandchildren; require a
    # session tool only if that becomes an observed problem on these systems.
    session_runner=()
  fi
  # NOTE: Don't use EXIT trap - cleanup manually after wait completes
  # to avoid race condition where trap fires before background jobs finish

  # Job tracking
  local running=0

  info "Running $total operation(s) in parallel (max $GROVE_MAX_PARALLEL concurrent)..."

  local i=0
  local label rest wt_path cmd
  for op in "${operations[@]}"; do
    i=$((i + 1))
    # Split on the first two '|' only; the command may itself contain '|'
    label="${op%%|*}"
    rest="${op#*|}"
    wt_path="${rest%%|*}"
    cmd="${rest#*|}"

    # Defensive: reject single quotes in the path. The wrapper passes the path as
    # argv (not interpolated), so this can't break quoting, but a quote in a path
    # almost always signals a mistake — fail loudly rather than run in the wrong dir.
    if [[ "$wt_path" == *"'"* ]]; then
      echo "fail|$label" > "$tmpdir/$i"
      continue
    fi

    # Wait if at max parallel
    while (( running >= GROVE_MAX_PARALLEL )); do
      local new_pids=()
      for pid in "${PARALLEL_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
          new_pids+=("$pid")
        else
          wait "$pid" 2>/dev/null || true
          running=$((running - 1))
        fi
      done
      PARALLEL_PIDS=("${new_pids[@]}")
      if (( running >= GROVE_MAX_PARALLEL )); then
        if is-at-least 5.9 "${ZSH_VERSION:-0}"; then
          wait -n 2>/dev/null || sleep 0.1
        else
          sleep 0.1
        fi
      fi
    done

    # Launch job
    # Path and command are passed as separate argv to a fixed wrapper, so neither
    # is interpolated into a shell string here (security boundary — see #16).
    # stdin from /dev/null: parallel jobs are inherently non-interactive, and a
    # job inheriting the parent's stdin can block/contend on it (which also hangs
    # `wait` below, e.g. under bats or when grove is driven via a pipe).
    "${session_runner[@]}" sh -c '
      op_status=fail
      if cd "$1" && sh -c "$2" </dev/null >/dev/null 2>&1; then
        op_status=ok
      fi
      printf "%s|%s\n" "$op_status" "$4" > "$3"
    ' _ "$wt_path" "$cmd" "$tmpdir/$i" "$label" &
    PARALLEL_PIDS+=($!)
    running=$((running + 1))
  done

  # Wait for ALL remaining jobs to complete before processing results
  for pid in "${PARALLEL_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  PARALLEL_PIDS=()
  PARALLEL_USES_PROCESS_GROUPS=false

  # NOW it's safe to collect and report results (all background jobs finished)
  local success=0 failed=0
  # Declare loop variables outside the loop to avoid zsh re-declaration output.
  # NB: 'label' is already declared above in this function scope — re-declaring
  # it here with a value would make zsh echo 'label=...' to stdout (corrupting
  # captured/JSON output), so it is deliberately omitted here.
  local result op_status
  i=0
  for op in "${operations[@]}"; do
    i=$((i + 1))
    # A missing result file means the job died before recording its outcome
    # (e.g. killed) — count it as a FAILURE so total == success + failed, never drop it.
    if [[ ! -f "$tmpdir/$i" ]]; then
      warn "  ${op%%|*} - failed (no result)"
      failed=$((failed + 1))
      continue
    fi

    result="$(<"$tmpdir/$i")"
    op_status="${result%%|*}"
    label="${result#*|}"

    if [[ "$op_status" == "ok" ]]; then
      ok "  $label"
      success=$((success + 1))
    else
      warn "  $label - failed"
      failed=$((failed + 1))
    fi
  done

  # Clean up temp directory now that all results are collected
  rm -rf "$tmpdir"
  PARALLEL_TMPDIR=""

  # Call result handler
  "$result_handler" "$success" "$failed" "$total"

  return $(( failed > 0 ? 1 : 0 ))
}
