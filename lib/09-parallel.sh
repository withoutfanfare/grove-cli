#!/usr/bin/env zsh
# 09-parallel.sh - Parallel execution framework

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

# parallel_run — Execute "label|command" operations in parallel with concurrency limiting
parallel_run() {
  local result_handler="$1"
  shift
  local operations=("$@")

  local total=${#operations[@]}
  [[ $total -eq 0 ]] && return 0

  # Create temp directory for results
  local tmpdir; tmpdir="$(/usr/bin/mktemp -d)"
  # NOTE: Don't use EXIT trap - cleanup manually after wait completes
  # to avoid race condition where trap fires before background jobs finish

  # Job tracking
  local pids=()
  local running=0

  info "Running $total operation(s) in parallel (max $GROVE_MAX_PARALLEL concurrent)..."

  local i=0
  for op in "${operations[@]}"; do
    i=$((i + 1))
    local label="${op%%|*}"
    local cmd="${op#*|}"

    # Wait if at max parallel
    while (( running >= GROVE_MAX_PARALLEL )); do
      local new_pids=()
      for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
          new_pids+=("$pid")
        else
          wait "$pid" 2>/dev/null || true
          running=$((running - 1))
        fi
      done
      pids=("${new_pids[@]}")
      if (( running >= GROVE_MAX_PARALLEL )); then
        if (( ${ZSH_VERSION%%.*} >= 5 )); then
          wait -n 2>/dev/null || sleep 0.1
        else
          sleep 0.1
        fi
      fi
    done

    # Launch job
    # Note: Using sh -c instead of eval for slightly better isolation
    # Commands are still user-controlled (exec-all feature), so validate in callers
    (
      if sh -c "$cmd" >/dev/null 2>&1; then
        echo "ok|$label" > "$tmpdir/$i"
      else
        echo "fail|$label" > "$tmpdir/$i"
      fi
    ) &
    pids+=($!)
    running=$((running + 1))
  done

  # Wait for ALL remaining jobs to complete before processing results
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # NOW it's safe to collect and report results (all background jobs finished)
  local success=0 failed=0
  # Declare loop variables outside the loop to avoid zsh re-declaration output
  local result op_status label
  i=0
  for op in "${operations[@]}"; do
    i=$((i + 1))
    if [[ -f "$tmpdir/$i" ]]; then
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
    fi
  done

  # Clean up temp directory now that all results are collected
  /bin/rm -rf "$tmpdir"

  # Call result handler
  "$result_handler" "$success" "$failed" "$total"

  return $(( failed > 0 ? 1 : 0 ))
}
