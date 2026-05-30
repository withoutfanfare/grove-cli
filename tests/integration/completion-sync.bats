#!/usr/bin/env bats
# completion-sync.bats - Enforce that the _grove completion stays in sync
# with the dispatcher in lib/99-main.sh.
#
# The _grove completion script is hand-maintained (NOT generated), so it can
# silently drift from the dispatcher. This test converts the manual "keep the
# completion in sync" CLAUDE.md step into an enforced invariant: every command
# the dispatcher can route MUST be offered by the completion.

load '../test-helper'

MAIN_SRC="$GROVE_ROOT/lib/99-main.sh"
COMPLETION_SRC="$GROVE_ROOT/_grove"

# Commands intentionally absent from the completion's command list, if any.
# Prefer full parity — keep this empty unless a command is deliberately hidden.
HIDDEN_COMMANDS=()

# Extract every dispatchable command label from the dispatcher case statement,
# i.e. the `  <name>) cmd_... ;;` arms in lib/99-main.sh.
_dispatch_commands() {
  grep -oE '^[[:space:]]+[a-z][a-z0-9-]*\)[[:space:]]+cmd_' "$MAIN_SRC" \
    | sed -E 's/^[[:space:]]+([a-z0-9-]+)\).*/\1/' \
    | sort -u
}

# Extract the command labels from the `commands=( '<name>:...' )` array in
# _grove. The array spans from the `commands=(` line to the closing `)`.
_completion_commands() {
  sed -n '/^[[:space:]]*commands=(/,/^[[:space:]]*)/p' "$COMPLETION_SRC" \
    | grep -oE "^[[:space:]]+'[a-z][a-z0-9-]*:" \
    | sed -E "s/^[[:space:]]+'([a-z0-9-]+):.*/\1/" \
    | sort -u
}

@test "completion-sync: dispatcher exposes commands" {
  run _dispatch_commands
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"add"* ]]
}

@test "completion-sync: _grove lists commands" {
  run _completion_commands
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"add"* ]]
}

@test "completion-sync: every dispatchable command appears in _grove completion" {
  local completion; completion="$(_completion_commands)"
  local missing=()
  local cmd
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    # Skip deliberately hidden commands.
    if (( ${#HIDDEN_COMMANDS[@]} > 0 )); then
      local skip="" h
      for h in "${HIDDEN_COMMANDS[@]}"; do
        [[ "$cmd" == "$h" ]] && skip=1 && break
      done
      [[ -n "$skip" ]] && continue
    fi
    if ! grep -qx "$cmd" <<< "$completion"; then
      missing+=("$cmd")
    fi
  done < <(_dispatch_commands)

  if (( ${#missing[@]} > 0 )); then
    echo "Dispatchable commands missing from _grove completion: ${missing[*]}"
  fi
  [ "${#missing[@]}" -eq 0 ]
}
