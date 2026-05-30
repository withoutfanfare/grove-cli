#!/usr/bin/env bash
#
# run-tests.sh - Run the grove-cli test suite
#
# Usage:
#   ./run-tests.sh           # Run all tests (lint + unit + integration)
#   ./run-tests.sh unit      # Run only unit tests
#   ./run-tests.sh integration  # Run only integration tests
#   ./run-tests.sh lint      # Run shellcheck static analysis
#   ./run-tests.sh validation.bats  # Run specific test file
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

info() { echo -e "${BLUE}→${NC} $*"; }
ok() { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✖${NC} $*"; }

# Lint state (set during a full run so the summary never claims a clean pass when
# static analysis was skipped or found issues)
LINT_SKIPPED=0
LINT_FAILED=0

# Check for shellcheck
check_shellcheck() {
  if command -v shellcheck >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Run shellcheck static analysis
run_shellcheck() {
  local failed=0

  # The zsh sources (grove, build.sh) cannot be linted by shellcheck — it is a bash/sh
  # linter and cannot parse zsh globs/parameter flags (e.g. *.git(N), ${(k)arr}). Parse-check
  # them with `zsh -n` instead; shellcheck is reserved for the genuine bash scripts below.
  if command -v zsh >/dev/null 2>&1; then
    info "Parse-checking zsh sources (zsh -n)..."
    local zfile
    for zfile in "$SCRIPT_DIR/grove" "$SCRIPT_DIR/build.sh"; do
      [[ -f "$zfile" ]] || continue
      if zsh -n "$zfile" 2>&1; then
        echo -e "  ${GREEN}✔${NC} ${zfile##*/}"
      else
        echo -e "  ${RED}✖${NC} ${zfile##*/}"
        failed=1
      fi
    done
  fi

  if ! check_shellcheck; then
    warn "shellcheck NOT INSTALLED - bash static analysis SKIPPED (not run)"
    echo "  Install it (recommended dev dependency): brew install shellcheck"
    # A failed zsh parse-check is still a hard failure; otherwise report 'skipped'
    [[ $failed -eq 0 ]] && return 2 || return 1
  fi

  info "Running shellcheck on bash scripts..."
  local files=(
    "$SCRIPT_DIR/run-tests.sh"
    "$SCRIPT_DIR/install.sh"
    "$SCRIPT_DIR/uninstall.sh"
    "$SCRIPT_DIR/migrate-from-wt.sh"
  )

  # Add hook examples if they exist
  if [[ -d "$SCRIPT_DIR/examples/hooks" ]]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$SCRIPT_DIR/examples/hooks" -type f -name "*.sh" -print0 2>/dev/null)
  fi

  local file
  for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
      if shellcheck "$file" 2>&1; then
        echo -e "  ${GREEN}✔${NC} ${file##*/}"
      else
        echo -e "  ${RED}✖${NC} ${file##*/}"
        failed=1
      fi
    fi
  done

  if [[ $failed -eq 0 ]]; then
    ok "Static analysis passed"
  else
    error "Static analysis found issues"
    return 1
  fi
}

# Check for BATS
check_bats() {
  if command -v bats >/dev/null 2>&1; then
    return 0
  fi

  # Check for local installation
  if [[ -x "$SCRIPT_DIR/test_modules/bats/bin/bats" ]]; then
    export PATH="$SCRIPT_DIR/test_modules/bats/bin:$PATH"
    return 0
  fi

  error "BATS (Bash Automated Testing System) not found!"
  echo ""
  echo "Install BATS using one of these methods:"
  echo ""
  echo "  # macOS (Homebrew)"
  echo "  brew install bats-core"
  echo ""
  echo "  # npm"
  echo "  npm install -g bats"
  echo ""
  echo "  # Manual installation"
  echo "  git clone https://github.com/bats-core/bats-core.git test_modules/bats"
  echo ""
  exit 1
}

# Run tests
run_tests() {
  local test_target="${1:-}"
  local test_files=()

  # Make glob handling explicit: with nullglob, a *.bats pattern that matches
  # nothing expands to an empty list rather than the literal pattern string.
  shopt -s nullglob

  if [[ -z "$test_target" ]]; then
    # Run all tests (lint + unit + integration)
    local lint_rc=0
    run_shellcheck || lint_rc=$?
    if (( lint_rc == 2 )); then
      LINT_SKIPPED=1
    elif (( lint_rc != 0 )); then
      LINT_FAILED=1
    fi
    echo ""
    info "Running all tests..."
    test_files=("$TESTS_DIR"/unit/*.bats "$TESTS_DIR"/integration/*.bats)
  elif [[ "$test_target" == "lint" ]]; then
    # Run only shellcheck
    run_shellcheck
    return $?
  elif [[ "$test_target" == "unit" ]]; then
    # Run only unit tests
    info "Running unit tests..."
    test_files=("$TESTS_DIR"/unit/*.bats)
  elif [[ "$test_target" == "integration" ]]; then
    # Run only integration tests
    info "Running integration tests..."
    test_files=("$TESTS_DIR"/integration/*.bats)
  elif [[ -f "$TESTS_DIR/unit/$test_target" ]]; then
    # Run specific test file from unit/
    info "Running $test_target..."
    test_files=("$TESTS_DIR/unit/$test_target")
  elif [[ -f "$TESTS_DIR/integration/$test_target" ]]; then
    # Run specific test file from integration/
    info "Running $test_target..."
    test_files=("$TESTS_DIR/integration/$test_target")
  elif [[ -f "$test_target" ]]; then
    # Run specific test file by path
    info "Running $test_target..."
    test_files=("$test_target")
  else
    error "Test file or category not found: $test_target"
    echo ""
    echo "Available options:"
    echo "  ./run-tests.sh              # Run all tests (lint + unit + integration)"
    echo "  ./run-tests.sh unit         # Run unit tests only"
    echo "  ./run-tests.sh integration  # Run integration tests only"
    echo "  ./run-tests.sh lint         # Run shellcheck static analysis"
    echo "  ./run-tests.sh <file.bats>  # Run specific test file"
    exit 1
  fi

  # Filter to only existing files
  local existing_files=()
  for f in "${test_files[@]}"; do
    [[ -f "$f" ]] && existing_files+=("$f")
  done

  if [[ ${#existing_files[@]} -eq 0 ]]; then
    warn "No test files found"
    exit 0
  fi

  echo ""
  # Capture the real bats exit status. Guarding with `||` keeps `set -e` from
  # aborting before the summary, and assigning in two steps avoids `local`
  # resetting $? to its own (always-zero) return code.
  local exit_code=0
  bats --tap "${existing_files[@]}" || exit_code=$?

  echo ""
  if [[ $exit_code -eq 0 && $LINT_FAILED -eq 0 ]]; then
    if [[ $LINT_SKIPPED -eq 1 ]]; then
      ok "All tests passed (⚠ lint SKIPPED — install shellcheck to run static analysis)"
    else
      ok "All tests passed!"
    fi
  else
    [[ $exit_code -ne 0 ]] && error "Some tests failed"
    [[ $LINT_FAILED -ne 0 ]] && error "shellcheck found issues"
    [[ $exit_code -eq 0 ]] && exit_code=1
  fi

  return $exit_code
}

# Main
main() {
  echo ""
  echo "╔════════════════════════════════════════════╗"
  echo "║    grove-cli Test Suite                     ║"
  echo "╚════════════════════════════════════════════╝"
  echo ""

  check_bats
  run_tests "$@"
}

main "$@"
