# Contributing to grove

Thanks for your interest in contributing to grove! This guide is for developers making their
first contribution. It covers how to report bugs and suggest features, how to set up your
development environment, the testing checklist a pull request must pass, the code style and commit
conventions we follow, and an orientation to the codebase architecture.

A quick orientation before anything else:

- **grove** is a command-line *git worktree* manager. A **worktree** is a working copy of a branch
  that lives in its own directory, so you can have several branches checked out at once. grove keeps
  each repo as a **bare repo** (a `.git` directory with no working tree of its own) under `HERD_ROOT`
  and hangs worktrees off it. Branch names like `feature/login` become filesystem-safe **slugs**
  like `feature-login` for directory names. **Herd** is Laravel's local development environment;
  grove can optionally wire worktrees into Herd sites, but all framework-specific setup is handled
  through customisable lifecycle hooks.
- **The `grove` executable is a generated artifact.** You never edit it directly. You edit the
  modular sources in `lib/` and run `./build.sh` to regenerate it. This rule is repeated below
  because it is the single most important thing to get right.

## Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Pull Requests](#pull-requests)
- [Prerequisites](#prerequisites)
- [Development Setup](#development-setup)
- [Testing Checklist](#testing-checklist)
- [Code Style](#code-style)
- [Commit Messages](#commit-messages)
- [Architecture Notes](#architecture-notes)
- [Questions?](#questions)

## Code of Conduct

Be respectful and constructive. We're all here to make a useful tool. Bug reports and feature
ideas are filed as GitHub issues — see [Questions?](#questions) for the repository links.

## How to Contribute

> ⚠️ **Before you change anything:** `grove` is a *generated* file. Make your changes in `lib/`
> (and `tests/`, `_grove`, docs), then run `./build.sh`. Never hand-edit the `grove` file — your
> edits will be overwritten on the next build. Full details are in
> [Development Setup](#development-setup).

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Include your macOS version, Herd version, and `grove --version`
3. Provide steps to reproduce the issue
4. Include the actual vs expected behaviour

### Suggesting Features

1. Check existing issues/discussions first
2. Explain the use case — what problem does it solve?
3. Consider if it fits the tool's scope (Laravel Herd + worktrees)

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes **in `lib/`** (never in the generated `grove` file), then run `./build.sh`
4. Test thoroughly — work through the [Testing Checklist](#testing-checklist)
5. Submit a PR with a clear description

## Prerequisites

Install these dev dependencies before running the test suite:

- **bats-core** — the test runner. `./run-tests.sh` **hard-fails and exits** if BATS is not found,
  so this is required. Install it one of these ways:
  ```bash
  brew install bats-core                                                   # macOS (Homebrew)
  npm install -g bats                                                      # npm
  git clone https://github.com/bats-core/bats-core.git test_modules/bats  # local checkout (auto-detected)
  ```
- **shellcheck** — the static-analysis linter. Without it the lint stage is *skipped* (not failed),
  and `./run-tests.sh` warns you. Install it to make the lint stage run: `brew install shellcheck`.
- **python3** — used by the `--json` validation one-liner in the checklist below. Ships with recent
  macOS; otherwise `brew install python3`.
- **zsh** — grove and `build.sh` are zsh scripts; macOS ships with zsh by default.

## Development Setup

> ⚠️ **`grove` is a generated file — never edit it directly.** It is compiled from the
> modular sources in `lib/` by `./build.sh`. Any hand-edit to `grove` is overwritten on the
> next build (and `grove upgrade` runs `./build.sh` too). **All real source lives in `lib/`.**

### 1. One-time setup

Do these once when you start working on grove:

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/grove-cli.git
cd grove-cli

# Install dev dependencies (see Prerequisites above)
brew install bats-core shellcheck

# Optional: expose the in-repo grove as a global command for ad-hoc use,
# without overwriting any version you installed normally.
ln -s "$(pwd)/grove" /usr/local/bin/grove-dev
```

### 2. Edit → build → test loop

Repeat this loop for every change. **`./build.sh` must be re-run after every edit to `lib/`**,
because `grove` is regenerated from `lib/` — your `lib/` changes are invisible until you rebuild.

```bash
# 1. Edit the SOURCE in lib/ (never the generated grove file)
$EDITOR lib/commands/lifecycle.sh   # for example

# 2. Rebuild the grove artifact from lib/
./build.sh                          # regenerates ./grove from lib/

# 3. Run the test suite
./run-tests.sh

# 4. Smoke-test the rebuilt binary directly from the repo
./grove --help
./grove doctor
```

Run `./grove ...` (from the repo root) throughout the loop so you are always exercising the artifact
you just rebuilt. The optional `grove-dev` symlink from step 1 is only for invoking grove from other
directories; if you use it, remember it points at the same `./grove` and still requires `./build.sh`
after each change.

## Testing Checklist

The automated suite (`./run-tests.sh`) is the primary gate; the manual smoke tests below it are for
changes that touch the worktree lifecycle. Before submitting a PR, please:

- [ ] Edit only files in `lib/` (and `tests/`, `_grove`, docs) — **never** the generated `grove`
- [ ] `./build.sh` — regenerate `grove` (commit the rebuilt artifact alongside your `lib/` change)
- [ ] `./run-tests.sh` — lint + unit + integration all pass
- [ ] `shellcheck` is installed so the lint stage actually runs (without it, lint is *skipped*, not
      failed; `brew install shellcheck` — see [Prerequisites](#prerequisites))
- [ ] If you touched any `--json` command **or a shared JSON helper**
      (`json_escape`/`format_json` in `lib/07-templates.sh`), re-validate **every** `--json`
      command, because `--json` is a data contract consumed by the grove-app desktop application:
      ```bash
      for cmd in "repos" "recent" "ls example-app" "branches example-app" \
                 "status example-app" "health example-app"; do
        ./grove $cmd --json | python3 -c 'import json,sys; json.load(sys.stdin)' \
          && echo "ok: grove $cmd --json"
      done
      ```
- [ ] `./grove --version` shows the correct version
- [ ] `./grove doctor` passes all checks
- [ ] **(lifecycle changes only)** `./grove add example-app <branch>` /
      `./grove ls example-app` / `./grove rm example-app <branch>` work end-to-end
- [ ] Tab completion works, and works with and without `fzf` installed

> **Note on the end-to-end smoke tests:** `grove add`/`ls`/`rm` need a real bare repo under
> `HERD_ROOT` (default `~/Herd`). If you don't have one, create a throwaway sandbox with
> `grove clone <url> example-app` or run `grove setup` first. A failure here usually means your
> environment isn't set up rather than that your change is broken — lean on `./run-tests.sh` as the
> authoritative gate.

### Running a subset of tests

While iterating you don't have to run the whole suite every time. `./run-tests.sh` accepts a target:

```bash
./run-tests.sh                 # everything: lint + unit + integration (the PR gate)
./run-tests.sh unit            # unit tests only (tests/unit/*.bats)
./run-tests.sh integration     # integration tests only (tests/integration/*.bats)
./run-tests.sh lint            # shellcheck + `zsh -n` parse-check only
./run-tests.sh validation.bats # a single file (resolved against tests/unit/, then
                               # tests/integration/, then as a literal path)
```

### What the lint stage actually checks

The lint stage does **not** run shellcheck against `grove` or `build.sh` — those are zsh, which
shellcheck (a bash/sh linter) cannot parse, so they are only *parse-checked* with `zsh -n`.
shellcheck runs on the genuine bash scripts: `run-tests.sh`, `install.sh`, `uninstall.sh`,
`migrate-from-wt.sh`, and `examples/hooks/*.sh`. Your edits in `lib/` are therefore **not**
shellchecked — they are validated via the built `grove`'s `zsh -n` parse-check and the BATS suite.

### Keep the bash test mirrors in sync

BATS runs under **bash**, but grove's source is **zsh**. So `tests/test-helper.bash` contains bash
*reimplementations* of several zsh functions — `slugify_string`, `slugify_branch`,
`is_reserved_ref_segment`, `db_name_for`, `validate_name`, and others. If you change that logic in
`lib/` (for example slug generation in `lib/03-paths.sh` or validation in `lib/02-validation.sh`),
you **must** update the matching mirror in `tests/test-helper.bash` too — otherwise the unit tests
will keep passing against the *stale* bash copy and silently miss your change.

## Code Style

- Use consistent indentation (2 spaces)
- Use meaningful function and variable names
- Add comments for non-obvious logic
- Follow existing patterns in the codebase
- Use British English in user-facing text (colour, behaviour, honour, etc.)
- Use the existing output helpers — `die()`, `info()`, `ok()`, `warn()`, `dim()`

## Commit Messages

Use conventional commit format:

```bash
feat: add new command for X
fix: correct database backup path
docs: update installation instructions
refactor: simplify branch detection logic
```

## Architecture Notes

User-facing command documentation lives in two places that must stay consistent: the **README.md**
command reference and `grove --help` (the `usage()` function in `lib/99-main.sh`). When you add or
change a command, update both so the help text and README match the actual behaviour.

`grove` is **generated** from modular sources in `lib/` by `./build.sh`, which concatenates
the modules in dependency order. Edit `lib/`, never the generated `grove`.

```text
lib/
├── 00-header.sh      # Version, defaults, global flags
├── 01-core.sh        # Config loading, colour output, helpers
├── 02-validation.sh  # Input validation (security-critical)
├── 03-paths.sh       # Worktree path/URL/slug generation
├── 04-git.sh         # Git operations, fetch cache
├── 05-database.sh    # MySQL database create/backup/remove helpers
│                     #   (invoked by the example lifecycle hooks, not by grove core;
│                     #    DB_CREATE / DB_BACKUP are gates the hooks honour)
├── 06-hooks.sh       # Lifecycle hook execution
├── 07-templates.sh   # Templates + json_escape/format_json (the --json data contract)
├── 08-spinner.sh     # Progress spinner
├── 09-parallel.sh    # Parallel operations
├── 10-interactive.sh # fzf interactive flows
├── 11-resilience.sh  # Lock handling, recovery
├── 12-deps.sh        # Shared dependency management
├── 99-main.sh        # usage() + argument dispatch
└── commands/         # One file per command group (cmd_* functions)

tests/
├── unit/             # Pure-function tests (12 .bats files: slugify, validation,
│                     #   db-naming, json-escape, services, …)
├── integration/      # Command/config integration (14 .bats files: lifecycle,
│                     #   git-ops, navigation, completion-sync, …)
├── test-helper.bash  # Shared bash helpers + bash MIRRORS of zsh functions (keep in sync)
└── fixtures/         # Test fixtures
```

When adding a new command:

1. Create `cmd_yourcommand()` in the appropriate `lib/commands/*.sh` file
2. Add a `yourcommand)` branch to the `case` statement in `lib/99-main.sh`
3. Add it to `usage()` in `lib/99-main.sh`
4. Update the **hand-maintained** completion script `./_grove` at the repo root — add the command to
   its `commands=(...)` array. The completion is **not** generated by `./build.sh`, and
   `tests/integration/completion-sync.bats` enforces parity with the dispatcher: the suite **fails**
   if a dispatchable command is missing from `_grove`.
5. Run `./build.sh`, then `./run-tests.sh`
6. Add documentation to `README.md` (the user-facing command reference) and keep it consistent with
   `usage()` in `lib/99-main.sh`

> **Note:** the help/usage function in `lib/99-main.sh` is named `usage()`. Older notes elsewhere may
> refer to it as `show_help()` — that name does not exist in the source; use `usage()`.

## Questions?

Open an issue or discussion on the repository — happy to help!

- Issues: <https://github.com/withoutfanfare/grove-cli/issues>
- Source: <https://github.com/withoutfanfare/grove-cli>
