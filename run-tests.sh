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

# Check for shellcheck
check_shellcheck() {
  if command -v shellcheck >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Run shellcheck static analysis
run_shellcheck() {
  if ! check_shellcheck; then
    warn "shellcheck not found - skipping static analysis"
    echo "  Install: brew install shellcheck"
    return 0
  fi

  info "Running shellcheck..."
  local files=("$SCRIPT_DIR/grove" "$SCRIPT_DIR/run-tests.sh" "$SCRIPT_DIR/install.sh")

  # Add hook examples if they exist
  if [[ -d "$SCRIPT_DIR/examples/hooks" ]]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$SCRIPT_DIR/examples/hooks" -type f -name "*.sh" -print0 2>/dev/null)
  fi

  local failed=0
  for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
      if shellcheck "$file" 2>&1; then
        echo -e "  ${GREEN}✔${NC} $file"
      else
        echo -e "  ${RED}✖${NC} $file"
        failed=1
      fi
    fi
  done

  if [[ $failed -eq 0 ]]; then
    ok "shellcheck passed"
  else
    error "shellcheck found issues"
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

  if [[ -z "$test_target" ]]; then
    # Run all tests (lint + unit + integration)
    run_shellcheck || true
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
  bats --tap "${existing_files[@]}"
  local exit_code=$?

  echo ""
  if [[ $exit_code -eq 0 ]]; then
    ok "All tests passed!"
  else
    error "Some tests failed"
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
