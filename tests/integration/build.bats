#!/usr/bin/env bats
# Build integrity checks use a disposable source tree and never touch ./grove.

load '../test-helper'

setup() {
  setup_test_environment
  export BUILD_FIXTURE="$TEST_TEMP_DIR/build-fixture"
  mkdir -p "$BUILD_FIXTURE"
  cp "$GROVE_ROOT/build.sh" "$BUILD_FIXTURE/build.sh"
  cp -R "$GROVE_ROOT/lib" "$BUILD_FIXTURE/lib"
}

teardown() {
  teardown_test_environment
}

@test "build fails before replacing output when a required module is missing" {
  local output="$BUILD_FIXTURE/grove"
  printf 'known-good\n' > "$output"
  rm "$BUILD_FIXTURE/lib/05-database.sh"

  run zsh "$BUILD_FIXTURE/build.sh" --output "$output"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Module not found: 05-database.sh"* ]]
  [ "$(cat "$BUILD_FIXTURE/grove")" = "known-good" ]
}

@test "build rejects an output path that aliases a source module" {
  local source="$BUILD_FIXTURE/lib/01-core.sh"
  local checksum
  checksum="$(shasum -a 256 "$source")"

  run zsh "$BUILD_FIXTURE/build.sh" --output "$source"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Output path must not replace a build source"* ]]
  [ "$(shasum -a 256 "$source")" = "$checksum" ]
}

@test "build preserves the previous output when assembly fails" {
  local artifact="$BUILD_FIXTURE/grove"
  local fake_bin="$TEST_TEMP_DIR/bin"
  mkdir -p "$fake_bin"
  printf 'known-good\n' > "$artifact"
  cat > "$fake_bin/cat" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$fake_bin/cat"

  run env PATH="$fake_bin:/usr/bin:/bin" zsh "$BUILD_FIXTURE/build.sh" --output "$artifact"

  [ "$status" -eq 1 ]
  [ "$(cat "$artifact")" = "known-good" ]
  ! find "$BUILD_FIXTURE" -maxdepth 1 -name 'grove.tmp.*' | grep -q .
}

@test "build rejects a directory output path" {
  local outdir="$BUILD_FIXTURE/outdir"
  mkdir -p "$outdir"

  run zsh "$BUILD_FIXTURE/build.sh" --output "$outdir"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Output path is a directory"* ]]
  ! find "$BUILD_FIXTURE" -name 'outdir.tmp.*' | grep -q .
  ! find "$outdir" -mindepth 1 | grep -q .
}

@test "build produces a 0755 CLI artefact" {
  local artifact="$BUILD_FIXTURE/grove"

  run zsh "$BUILD_FIXTURE/build.sh" --output "$artifact"

  [ "$status" -eq 0 ]
  mode="$(stat -f '%Lp' "$artifact" 2>/dev/null || stat -c '%a' "$artifact")"
  [ "$mode" = "755" ]
}
