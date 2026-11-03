# Grove CLI review and fixes — 2 November 2026

The concrete bugs identified by Claude Code Opus 5.5 and Codex Astra, both at
medium effort, have fixes and regression coverage in this checkout. The generated
`grove` executable has been rebuilt. Changes remain uncommitted and have not been
installed or released.

Baseline: `5aa59f77ea12cf987075cca151dd4e233b3c2c37`, branch
`fix/respect-herd-skip`.

## Resulting behaviour

| Area | Fixes |
| --- | --- |
| Environment rewrites | Private temporary storage, preserved permissions and symlinks, atomic replacement, and failures propagated through move/restructure. |
| Worktree safety | Removal is checked again after pre-removal hooks. Move/removal detect current-site links. Dependency cleanup skips dirty/current/recent worktrees and confirms single-repo deletion. |
| Database identity | Database deletion requires a recorded identity and checks registered siblings. Switch hooks receive the resolved identity; the example refuses an empty identity before editing `.env`. |
| Base isolation | Worktree bases use their own sidecars. Shared legacy config cannot leak between worktrees. Merge, stale and health reports use each worktree's base. |
| Command results | Bulk arguments retain their boundaries; all-repo pruning returns correctly. Failed migration, repair pruning, upgrade builds and service operations no longer report success. |
| Services and installation | Switching stops after a service stop failure. Registry rewrites use unique temporary files. Hook replacement requires a successful backup. Uninstall checks the exact Grove target before deleting a `wt` link. |
| Wizard and templates | Invalid branch input reprompts; cancelled input/selections stop safely. Template booleans use the literal config parser. Pre-built environment templates are selected before configuration; existing custom files are preserved. Shared symlinks are left to repo-specific configuration hooks. |
| Migration and completion | Migration honours the selected Herd root, preserves failed backups/sidecars, keeps ambiguous shared bases, and reports content rewrites during dry runs. Completion honours exported `HERD_ROOT` and performs no background fetch. |
| Shared dependencies | Relative links resolve from the selected worktree. A private staged copy is prepared before replacing the link; failures retain the link and propagate. |

## Intentional change to `fresh`

`grove fresh` now runs `npm ci` and `npm run build` when `package.json` exists.
It preserves databases, including with `--force`, and returns failure when an
asset command fails.

A literal `.env` database name cannot establish which database Laravel will
reset: cached configuration, connection URLs and exported settings can select a
different connection. The recommended database-preserving default was applied
after the preference question remained unanswered. Help, completion and command
documentation reflect this behaviour.

## Verification

- `./build.sh`: succeeded; generated executable SHA-256
  `0494f5ca8825155849c36713967c788ad7bc876b58fcfda9772936f666bef754`.
- `./run-tests.sh`: exit 0; **694 passed, 9 skipped, 0 failed** across 703 cases.
  Includes Zsh parse checks and ShellCheck for Bash scripts and bundled hooks.
- `zsh -n _grove`: passed.
- `git diff --check`: passed.
- Built-executable checks for `repos`, `recent`, `ls demo`, `branches demo` and
  `health demo`, each with `--json`: exit 0 and one valid JSON document per
  command, using a disposable Git repository and isolated configuration.
- New regression cases reproduced the root's configuration, completion,
  migration-preview and `fresh` failures before their fixes. Model-owned fixes
  were inspected and included in the final combined run.

The nine skips cover a real npm build, live MySQL, installed Herd and local hooks
that are not bundled. No real database reset/import/removal, service switch or
installation was exercised. No background server or service was started.
The removal recheck reduces the race window; it does not establish exclusive
ownership across independent tools.

## New test files

- `tests/integration/completion-herd-root.bats`
- `tests/integration/install.bats`
- `tests/integration/migration.bats`
- `tests/integration/report-base.bats`
- `tests/integration/uninstall.bats`
- `tests/integration/wizard.bats`
- `tests/unit/template-load.bats`

Existing regression files were extended for the other fixes.
