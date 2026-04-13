#!/usr/bin/env bats
# json-escape.bats - Tests for json_escape() function
#
# Ensures proper escaping for JSON output

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# ============================================================================
# Basic strings - should pass through unchanged
# ============================================================================

@test "json_escape: simple string unchanged" {
  result="$(json_escape "hello")"
  [ "$result" = "hello" ]
}

@test "json_escape: string with spaces" {
  result="$(json_escape "hello world")"
  [ "$result" = "hello world" ]
}

@test "json_escape: numbers unchanged" {
  result="$(json_escape "12345")"
  [ "$result" = "12345" ]
}

@test "json_escape: alphanumeric with dashes" {
  result="$(json_escape "my-app-name")"
  [ "$result" = "my-app-name" ]
}

@test "json_escape: path unchanged" {
  result="$(json_escape "/Users/danny/Herd/myapp")"
  [ "$result" = "/Users/danny/Herd/myapp" ]
}

@test "json_escape: URL unchanged" {
  result="$(json_escape "https://myapp--main.test")"
  [ "$result" = "https://myapp--main.test" ]
}

# ============================================================================
# Characters that need escaping
# ============================================================================

@test "json_escape: escapes double quotes" {
  result="$(json_escape 'hello "world"')"
  [ "$result" = 'hello \"world\"' ]
}

@test "json_escape: escapes backslashes" {
  result="$(json_escape 'path\to\file')"
  [ "$result" = 'path\\to\\file' ]
}

@test "json_escape: escapes newlines" {
  input=$'line1\nline2'
  result="$(json_escape "$input")"
  [ "$result" = 'line1\nline2' ]
}

@test "json_escape: escapes tabs" {
  input=$'col1\tcol2'
  result="$(json_escape "$input")"
  [ "$result" = 'col1\tcol2' ]
}

@test "json_escape: escapes carriage returns" {
  input=$'line1\rline2'
  result="$(json_escape "$input")"
  [ "$result" = 'line1\rline2' ]
}

@test "json_escape: escapes form feeds" {
  input=$'page1\fpage2'
  result="$(json_escape "$input")"
  [ "$result" = 'page1\fpage2' ]
}

@test "json_escape: escapes backspaces" {
  input=$'abc\bdef'
  result="$(json_escape "$input")"
  [ "$result" = 'abc\bdef' ]
}

# ============================================================================
# Combined escaping
# ============================================================================

@test "json_escape: multiple special characters" {
  input=$'path\\to\\"file\twith\nnewline'
  result="$(json_escape "$input")"
  # Backslash escaped first, then quote, tab, newline
  [ "$result" = 'path\\to\\\"file\twith\nnewline' ]
}

@test "json_escape: complex path with backslashes" {
  result="$(json_escape 'C:\Users\danny\Projects')"
  [ "$result" = 'C:\\Users\\danny\\Projects' ]
}

@test "json_escape: message with quotes" {
  result="$(json_escape 'Error: "file not found"')"
  [ "$result" = 'Error: \"file not found\"' ]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "json_escape: empty string" {
  result="$(json_escape "")"
  [ "$result" = "" ]
}

@test "json_escape: single backslash" {
  result="$(json_escape '\')"
  [ "$result" = '\\' ]
}

@test "json_escape: single quote" {
  result="$(json_escape '"')"
  [ "$result" = '\"' ]
}

@test "json_escape: only newline" {
  input=$'\n'
  result="$(json_escape "$input")"
  [ "$result" = '\n' ]
}

@test "json_escape: multiple newlines" {
  input=$'\n\n\n'
  result="$(json_escape "$input")"
  [ "$result" = '\n\n\n' ]
}

# ============================================================================
# Real-world examples
# ============================================================================

@test "json_escape: git commit message with quotes" {
  msg='fix: resolve "undefined variable" error'
  result="$(json_escape "$msg")"
  [ "$result" = 'fix: resolve \"undefined variable\" error' ]
}

@test "json_escape: error message with newlines" {
  msg=$'Error occurred:\n  - File not found\n  - Permission denied'
  result="$(json_escape "$msg")"
  [ "$result" = 'Error occurred:\n  - File not found\n  - Permission denied' ]
}

@test "json_escape: Windows path" {
  path='C:\Program Files\MyApp\config.json'
  result="$(json_escape "$path")"
  [ "$result" = 'C:\\Program Files\\MyApp\\config.json' ]
}
