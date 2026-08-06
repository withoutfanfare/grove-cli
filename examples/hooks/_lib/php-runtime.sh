#!/bin/bash
# Resolve one PHP binary for every PHP-based hook in a lifecycle run.

grove_php_bin() {
  local candidate

  # An explicit GROVE_PHP_BIN is a policy, not a hint: if it cannot run,
  # fail rather than silently falling back to a different PHP.
  if [[ -n "${GROVE_PHP_BIN:-}" ]]; then
    if [[ -x "$GROVE_PHP_BIN" ]]; then
      printf '%s\n' "$GROVE_PHP_BIN"
      return 0
    fi
    echo "GROVE_PHP_BIN is set but not executable: $GROVE_PHP_BIN" >&2
    return 1
  fi

  candidate="$HOME/Library/Application Support/Herd/bin/php"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  command -v php
}
