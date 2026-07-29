#!/bin/bash
# Resolve one PHP binary for every PHP-based hook in a lifecycle run.

grove_php_bin() {
  local candidate

  for candidate in \
    "${GROVE_PHP_BIN:-}" \
    "$HOME/Library/Application Support/Herd/bin/php"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  command -v php
}
