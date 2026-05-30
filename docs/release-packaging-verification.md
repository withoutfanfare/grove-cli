# Release Packaging Verification Guide

> Checklist for verifying grove-cli changes against the grove-app Tauri desktop application.

This document has two parts:

1. **[Reusable Verification Checklist](#reusable-verification-checklist)** — run this for *any* release that could affect the JSON data contract. Keep it current.
2. **[Historical: `feat/release-packaging`](#historical-featrelease-packaging)** — the original retrospective for the merged `feat/release-packaging` PR. Point-in-time record; do not edit for new releases.

---

## Reusable Verification Checklist

### JSON contract verification (`verify-json.sh`)

Every JSON command must parse cleanly. Rather than repeat the same `python3 -c "import json,sys; json.load(sys.stdin)"` idiom for each endpoint, use one parameterised helper:

```bash
#!/usr/bin/env bash
# verify-json.sh <command...> -- run a grove JSON command and confirm it parses.
# Usage: ./verify-json.sh repos
#        ./verify-json.sh ls myrepo
verify_json() {
  local label="$*"
  printf '%-40s ' "$label:"
  if ./grove "$@" --json | python3 -c "import json,sys; json.load(sys.stdin)"; then
    echo "OK"
  else
    echo "FAIL"
    return 1
  fi
}

# Full JSON matrix. Replace <repo>/<branch> with real values from your machine.
REPO="${1:-myrepo}"
BRANCH="${2:-main}"

verify_json repos
verify_json recent
verify_json config
verify_json services apps
verify_json ls "$REPO"
verify_json branches "$REPO"
verify_json health "$REPO"
verify_json status "$REPO"
verify_json log "$REPO" "$BRANCH"
verify_json changes "$REPO" "$BRANCH"
verify_json summary "$REPO" "$BRANCH"
verify_json info "$REPO" "$BRANCH"
```

Run it with a repo (and optionally a branch) that exists locally:

```bash
./verify-json.sh myrepo feature/my-branch
```

This covers the full matrix in [Tauri App Compatibility Matrix](#tauri-app-compatibility-matrix). Wherever this guide shows a single `... | python3 -c "import json,sys; json.load(sys.stdin)"` invocation, it is shorthand for one `verify_json` call.

### Pre-flight (CLI)

```bash
# 1. Version check
grove --version

# 2. Full test suite.
#    IMPORTANT: ./run-tests.sh reports green even when shellcheck is NOT installed
#    -- the lint stage is SILENTLY SKIPPED. For a complete gate, install shellcheck
#    first (brew install shellcheck) and confirm the lint stage actually runs.
command -v shellcheck >/dev/null || echo "WARNING: shellcheck missing -- lint stage will be skipped"
./run-tests.sh

# 3. JSON contract -- run the full matrix (see verify-json.sh above)
./verify-json.sh myrepo
```

### Tauri app smoke tests

Run the [Tauri App Smoke Tests](#tauri-app-smoke-tests) below against the desktop app after updating the CLI.

---

## Historical: `feat/release-packaging`

> The remainder of this document is the original retrospective for the `feat/release-packaging` PR. It is kept for reference and is **not** updated for subsequent releases.

**Branch:** `feat/release-packaging` (merged to main)
**Date:** 2026-04-13

---

## Summary of Changes

### 1. New Command: `grove services`

A new top-level command for optional Laravel service management (Supervisor, Horizon, Reverb, schedulers). **This is entirely additive** -- no existing commands or JSON contracts were modified.

| Subcommand | Description | JSON Support |
|------------|-------------|:------------:|
| `grove services status [app]` | Show service status for all/one app | No |
| `grove services start <app\|all>` | Start supervisor processes and scheduler | No |
| `grove services stop <app\|all>` | Stop supervisor processes and scheduler | No |
| `grove services restart <app\|all>` | Restart supervisor processes | No |
| `grove services add <name> [opts]` | Register a new app | No |
| `grove services remove <name>` | Unregister an app | No |
| `grove services apps` | List registered apps | **Yes** |
| `grove services horizon <app>` | Open Horizon dashboard in browser | No |
| `grove services logs <app> [type]` | Tail service logs | No |
| `grove services doctor` | Check service dependencies | No |

### 2. New JSON Endpoint: `grove services apps --json`

**Schema:**

```json
[
  {
    "name": "myapp",
    "system_name": "myapp-repo",
    "services": "horizon",
    "supervisor_process": "myapp-horizon",
    "domain": "myapp.test"
  }
]
```

Returns an empty array `[]` if no apps are registered.

### 3. Documentation Fixes (No Code Impact)

- CHANGELOG header: `wt` -> `grove`
- README alias examples: `wts`/`wtl`/`wtc` -> `gs`/`gl`/`gc`
- README hooks table: added `post-switch`, `pre-move`, `post-move`
- Help text: added `post-switch` to hooks section, added `SERVICE MANAGEMENT` section

### 4. Installer Improvements

- `install.sh` now creates `~/.grove/templates`, `~/.grove/aliases`, `~/.grove/groups`, `~/.grove/services`
- `install.sh` now creates `~/.grove/hooks/post-switch.d/`
- `install.sh` detects existing `~/.devctl/apps.conf` and offers migration to `~/.grove/services/apps.conf`

### 5. Hook Update

- `examples/hooks/post-switch.d/02-devctl-restart.sh` rewritten to use `grove services restart` instead of hardcoded `devctl` calls. Idempotent -- exits silently if app not registered.

### 6. Build System

- `services.sh` added to `COMMAND_MODULES` in `build.sh`
- `services` case added to main argument parser in `lib/99-main.sh`
- Tab completion updated in `_grove` with services subcommands

---

## Tauri App Compatibility Matrix

### Existing JSON Endpoints (UNCHANGED)

All existing JSON endpoints are unmodified. Verify each still works as expected. The "Verify" column shows the `verify_json` helper from the [reusable checklist](#json-contract-verification-verify-jsonsh); each call appends `--json` and pipes through `json.load`, so there's no need to repeat the Python idiom per row.

| Command | Expected Behaviour | Verify |
|---------|-------------------|--------|
| `grove repos --json` | Array of repo objects | `verify_json repos` |
| `grove ls <repo> --json` | Array of worktree objects | `verify_json ls <repo>` |
| `grove recent --json` | Array of recent worktree objects | `verify_json recent` |
| `grove branches <repo> --json` | Array of branch objects | `verify_json branches <repo>` |
| `grove health <repo> --json` | Health report object | `verify_json health <repo>` |
| `grove status <repo> --json` | Array of status objects | `verify_json status <repo>` |
| `grove log <repo> <branch> --json` | Array of commit objects | `verify_json log <repo> <branch>` |
| `grove changes <repo> <branch> --json` | Array of file change objects | `verify_json changes <repo> <branch>` |
| `grove summary <repo> <branch> --json` | Summary object | `verify_json summary <repo> <branch>` |
| `grove config --json` | Config object | `verify_json config` |
| `grove info <repo> <branch> --json` | Worktree detail object | `verify_json info <repo> <branch>` |

### New JSON Endpoint

| Command | Schema | Verify |
|---------|--------|--------|
| `grove services apps --json` | Array of `{name, system_name, services, supervisor_process, domain}` | `verify_json services apps` |

---

## Verification Checklist

> PR-specific verification run for `feat/release-packaging`. For a release-agnostic version, use the [Reusable Verification Checklist](#reusable-verification-checklist) at the top of this document.

### Pre-flight (CLI)

Run these from the terminal to confirm grove-cli is working:

```bash
# 1. Version check
grove --version

# 2. Full test suite.
#    NOTE: ./run-tests.sh passes even when shellcheck is missing (lint is silently
#    skipped). Install shellcheck (brew install shellcheck) for a complete gate.
./run-tests.sh

# 3. Help shows new section
grove --help | grep -A 4 "SERVICE MANAGEMENT"

# 4. Services command works with no config
grove services

# 5. Idempotent restart (should exit 0 silently)
grove services restart nonexistent-app; echo "Exit: $?"

# 6. JSON smoke sample (NOT the full matrix -- repos/recent only).
#    For the full JSON contract, run ./verify-json.sh from the reusable checklist above.
for cmd in "repos" "recent"; do
  echo -n "$cmd: "
  grove $cmd --json | python3 -c "import json,sys; json.load(sys.stdin)" && echo "OK" || echo "FAIL"
done
```

> The loop above is a **smoke sample** -- it touches only `repos` and `recent`. The compatibility matrix below lists all 11+ JSON endpoints; verify them with `./verify-json.sh` (see the [reusable checklist](#json-contract-verification-verify-jsonsh)).

### Tauri App Smoke Tests

Test these scenarios in the grove-app:

- [ ] **App launches** without errors after updating grove CLI
- [ ] **Repository list** loads correctly (uses `grove repos --json`)
- [ ] **Worktree list** for a repo loads correctly (uses `grove ls <repo> --json`)
- [ ] **Recent worktrees** panel loads correctly (uses `grove recent --json`)
- [ ] **Branch list** for a repo loads correctly (uses `grove branches <repo> --json`)
- [ ] **Health view** loads correctly (uses `grove health <repo> --json`)
- [ ] **Status view** loads correctly (uses `grove status <repo> --json`)
- [ ] **Worktree creation** (`grove add`) still works via the app
- [ ] **Worktree removal** (`grove rm`) still works via the app
- [ ] **Pull** operations work via the app
- [ ] **Error handling** -- malformed input still returns JSON error objects (e.g. `grove ls nonexistent --json`)
- [ ] **Unknown command** -- `grove services` does not cause errors if the app doesn't know about it (it should be invisible to existing app features)

### Services Integration (Optional -- only if adding to Tauri app)

If the Tauri app will consume the new `grove services` commands:

- [ ] `grove services apps --json` returns valid JSON array
- [ ] `grove services apps --json` returns `[]` when no apps registered
- [ ] `grove services add testapp` followed by `grove services apps --json` includes the new app
- [ ] `grove services remove testapp` followed by `grove services apps --json` returns `[]`
- [ ] `grove services status` output can be parsed (currently text-only, no JSON)

---

## Risk Assessment

| Area | Risk | Rationale |
|------|------|-----------|
| Existing JSON endpoints | **None** | No changes to any existing JSON-producing code paths |
| CLI argument parsing | **None** | `services` added as new case, `""` and `*` cases unchanged |
| Help text | **Low** | Help output is longer now; if Tauri app parses help text, check it still works |
| Tab completion | **None** | Additive only -- new `services` entry in completions |
| Build system | **None** | `services.sh` appended to module list, no reordering |
| Hooks | **Low** | `02-devctl-restart.sh` rewritten; only affects users with existing devctl integration |
| Installer | **Low** | Only additive (new directories, optional migration prompt) |

---

## Files Changed

```bash
CHANGELOG.md                                        # Header fix (wt -> grove)
README.md                                           # Alias fixes, hooks table, services docs
_grove                                              # Tab completion for services
build.sh                                            # services.sh in module list
examples/hooks/README.md                            # devctl -> grove services references
examples/hooks/post-switch.d/02-devctl-restart.sh   # Rewritten to use grove services
grove                                               # Rebuilt artifact
install.sh                                          # New directories + migration
lib/99-main.sh                                      # services case + help text
lib/commands/services.sh                            # NEW: entire services module (700 lines)
tests/unit/services.bats                            # NEW: 16 unit tests
```
