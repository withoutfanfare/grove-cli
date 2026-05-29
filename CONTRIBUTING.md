# Contributing to grove

Thanks for your interest in contributing to grove! This document provides guidelines for contributing.

## Code of Conduct

Be respectful and constructive. We're all here to make a useful tool.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Include your macOS version, Herd version, and `grove --version`
3. Provide steps to reproduce the issue
4. Include the actual vs expected behaviour

### Suggesting Features

1. Check existing issues/discussions first
2. Explain the use case - what problem does it solve?
3. Consider if it fits the tool's scope (Laravel Herd + worktrees)

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test thoroughly (see below)
5. Submit a PR with a clear description

## Development Setup

> ⚠️ **`grove` is a generated file — never edit it directly.** It is compiled from the
> modular sources in `lib/` by `./build.sh`. Any hand-edit to `grove` is overwritten on the
> next build (and `grove upgrade` runs `./build.sh` too). **All real source lives in `lib/`.**

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/grove-cli.git
cd grove-cli

# Edit the SOURCE in lib/, then rebuild the grove artifact
$EDITOR lib/commands/lifecycle.sh   # for example
./build.sh                          # regenerates ./grove from lib/

# Create a test symlink (don't overwrite your installed version)
ln -s "$(pwd)/grove" /usr/local/bin/grove-dev

# Test your changes (rebuild first if you changed anything in lib/)
./build.sh
grove-dev doctor
grove-dev --help
```

## Testing Checklist

Before submitting a PR, please:

- [ ] Edit only files in `lib/` (and `tests/`, docs) — **never** the generated `grove`
- [ ] `./build.sh` — regenerate `grove` (commit the rebuilt artifact alongside your `lib/` change)
- [ ] `./run-tests.sh` — lint + unit + integration all pass
- [ ] `shellcheck` is installed so the lint stage actually runs (`brew install shellcheck`)
- [ ] If you changed a `--json` command, validate it: `./grove <cmd> --json | python3 -c 'import json,sys; json.load(sys.stdin)'`
- [ ] `grove --version` shows the correct version
- [ ] `grove doctor` passes all checks
- [ ] `grove add <repo> <branch>` / `grove ls <repo>` / `grove rm <repo> <branch>` work end-to-end
- [ ] Tab completion works, and works with and without fzf installed

## Code Style

- Use consistent indentation (2 spaces)
- Use meaningful function and variable names
- Add comments for non-obvious logic
- Follow existing patterns in the codebase
- Use British English in user-facing text (colour, honour, etc.)

## Commit Messages

Use conventional commit format:

```bash
feat: add new command for X
fix: correct database backup path
docs: update installation instructions
refactor: simplify branch detection logic
```

## Architecture Notes

`grove` is **generated** from modular sources in `lib/` by `./build.sh`, which concatenates
the modules in dependency order. Edit `lib/`, never the generated `grove`.

```text
lib/
├── 00-header.sh      # Version, defaults, global flags
├── 01-core.sh        # Config loading, colour output, helpers
├── 02-validation.sh  # Input validation (security-critical)
├── 03-paths.sh       # Worktree path/URL/slug generation
├── 04-git.sh         # Git operations, fetch cache
├── 05-database.sh    # MySQL helpers (DB work is delegated to hooks)
├── 06-hooks.sh       # Lifecycle hook execution
├── 07-templates.sh   # Templates + json_escape/format_json
├── 08-spinner.sh     # Progress spinner
├── 09-parallel.sh    # Parallel operations
├── 10-interactive.sh # fzf interactive flows
├── 11-resilience.sh  # Lock handling, recovery
├── 12-deps.sh        # Shared dependency management
├── 99-main.sh        # usage() + argument dispatch
└── commands/         # One file per command group (cmd_* functions)
```

When adding a new command:

1. Create `cmd_yourcommand()` in the appropriate `lib/commands/*.sh` file
2. Add a `yourcommand)` branch to the `case` statement in `lib/99-main.sh`
3. Add it to `usage()` in `lib/99-main.sh`
4. Update the completion script `_grove`
5. Run `./build.sh`, then `./run-tests.sh`
6. Add documentation to `README.md`

## Questions?

Open an issue or discussion - happy to help!
