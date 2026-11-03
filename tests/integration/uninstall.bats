#!/usr/bin/env bats
# uninstall.sh 'wt' link detection. Only the functions are loaded, never the
# script body, so nothing outside the throwaway directory is touched.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/repo" "$TMP/bin" "$TMP/tools/grove-utils"
  printf '#!/bin/sh\n' > "$TMP/repo/grove"
  ln -s "$TMP/repo/grove" "$TMP/bin/grove"
  # Function definitions only: from "name() {" to the closing "}".
  FUNCS="$(awk '/^[a-z_]+\(\) \{/{f=1} f{print} /^\}/{f=0}' "$PROJECT_ROOT/uninstall.sh")"
  export FUNCS TMP
}

teardown() {
  rm -rf "$TMP"
}

# Identify wt, remove grove (as the script does), then remove the identified link.
uninstall_wt() {
  run bash -c 'eval "$FUNCS"
    link="$(grove_wt_link "$TMP/bin")"
    rm -f "$TMP/bin/grove"
    remove_wt_symlink "$link"'
}

@test "removes an absolute wt link to the installed grove" {
  ln -s "$TMP/bin/grove" "$TMP/bin/wt"
  uninstall_wt
  [ "$status" -eq 0 ]
  [ ! -L "$TMP/bin/wt" ]
}

@test "removes a relative wt link to the installed grove" {
  ( cd "$TMP/bin" && ln -s grove wt )
  uninstall_wt
  [ "$status" -eq 0 ]
  [ ! -L "$TMP/bin/wt" ]
}

@test "removes a wt link straight to the resolved grove script" {
  ( cd "$TMP/bin" && ln -s ../repo/grove wt )
  uninstall_wt
  [ "$status" -eq 0 ]
  [ ! -L "$TMP/bin/wt" ]
}

@test "preserves an unrelated wt link whose path contains grove" {
  printf '#!/bin/sh\n' > "$TMP/tools/grove-utils/wt"
  ln -s "$TMP/tools/grove-utils/wt" "$TMP/bin/wt"
  uninstall_wt
  [ "$status" -eq 0 ]
  [ -L "$TMP/bin/wt" ]
  [ -f "$TMP/tools/grove-utils/wt" ]
}

@test "preserves a regular wt file" {
  printf '#!/bin/sh\n' > "$TMP/bin/wt"
  uninstall_wt
  [ "$status" -eq 0 ]
  [ -f "$TMP/bin/wt" ] && [ ! -L "$TMP/bin/wt" ]
}

@test "preserves a dangling wt link when grove is not installed there" {
  rm "$TMP/bin/grove"
  ln -s "$TMP/bin/grove" "$TMP/bin/wt"
  uninstall_wt
  [ "$status" -eq 0 ]
  [ -L "$TMP/bin/wt" ]
}
