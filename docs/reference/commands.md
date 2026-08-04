# Command Reference

> Complete reference for all grove commands. For getting started, see the [README](../../README.md).

This is the exhaustive, per-command reference for `grove` — a command-line git **worktree** manager (a worktree is a checkout of a branch in its own directory, all backed by a single **bare repo**: a `.git` directory with no working tree) with optional Laravel **Herd** integration. Each entry gives the synopsis, flags, examples, and — where applicable — the `--json` output shape. Use it to look up the exact behaviour of any single command.

A few conventions used throughout:

- `<arg>` is required, `[arg]` is optional.
- Many git, navigation and Laravel commands **auto-detect** the repo/branch when run from inside a worktree under `HERD_ROOT`; their synopses show `[repo] [branch]` and say so explicitly.
- The `--json` output is a **data contract** consumed by the grove-app desktop application — the shapes here are authoritative. The `--pretty` flag colourises and indents JSON (except for `grove config`).
- `grove` itself is a generated artifact built from `lib/` via `./build.sh` — contributors edit the modular sources in `lib/`, never the `grove` file directly.

---

## Contents

- **Core Commands** — [add](#grove-add) · [rm](#grove-rm) · [move](#grove-move) · [clone](#grove-clone) · [ls](#grove-ls) · [repos](#grove-repos) · [status](#grove-status) · [config](#grove-config) · [templates](#grove-templates)
- **Navigation** — [cd](#grove-cd) · [code](#grove-code) · [open](#grove-open) · [switch](#grove-switch) · [exec](#grove-exec)
- **Git Operations** — [pull](#grove-pull) · [pull-all](#grove-pull-all) · [sync](#grove-sync) · [diff](#grove-diff) · [summary](#grove-summary) · [log](#grove-log) · [changes](#grove-changes) · [branches](#grove-branches) · [prune](#grove-prune)
- **Information & Monitoring** — [dashboard](#grove-dashboard) · [info](#grove-info) · [recent](#grove-recent) · [health](#grove-health) · [report](#grove-report) · [clean](#grove-clean)
- **Laravel Commands** — [fresh](#grove-fresh) · [migrate](#grove-migrate) · [tinker](#grove-tinker)
- **Parallel Operations** — [build-all](#grove-build-all) · [exec-all](#grove-exec-all)
- **Service Management** — [services status](#grove-services-status) · [start](#grove-services-start) · [stop](#grove-services-stop) · [restart](#grove-services-restart) · [apps](#grove-services-apps) · [add](#grove-services-add) · [remove](#grove-services-remove) · [horizon](#grove-services-horizon) · [logs](#grove-services-logs) · [doctor](#grove-services-doctor)
- **Utilities** — [doctor](#grove-doctor) · [setup](#grove-setup) · [repair](#grove-repair) · [upgrade](#grove-upgrade) · [version](#grove-version) · [cleanup-herd](#grove-cleanup-herd) · [unlock](#grove-unlock) · [share-deps](#grove-share-deps) · [alias](#grove-alias) · [group](#grove-group) · [restructure](#grove-restructure)
- **Reference** — [Global Flags](#global-flags) · [Shell Completion](#shell-completion) · [JSON Output Reference](#json-output-reference) · [Branch Shortcuts](#branch-shortcuts) · [Configuration](#configuration) · [Health Score System](#health-score-system)

---

## Core Commands

### grove add

Creates a new worktree for a branch.

**Usage**

```bash
grove add <repo> <branch> [base]
grove add -i
grove add <repo> <branch> --template=<name>
grove add <repo> <branch> --dry-run
```

**Arguments**

| Argument | Description |
|----------|-------------|
| `<repo>` | Repository name (bare repo without `.git`) |
| `<branch>` | Branch name (existing or new) |
| `[base]` | Base branch to create from (default: `origin/staging`) |

**Flags**

| Flag | Description |
|------|-------------|
| `-i`, `--interactive` | Guided creation wizard (requires fzf). Also reachable as bare `grove -i` (no command). |
| `--dry-run` | Preview what would happen without executing |
| `-t`, `--template=<name>` | Use a worktree template for setup hooks (`-t <name>` or `--template=<name>`) |
| `-f`, `--force` | Allow creating a new branch that does not yet exist locally or on remote (otherwise `add` aborts and suggests checking the branch name) |
| `--json` | Output result as JSON |

**Examples**

```bash
# Create from existing remote branch
grove add example-app feature/existing-branch

# Create new branch from default base (origin/staging)
grove add example-app feature/new-work

# Create new branch from a specific base
grove add example-app feature/new-work origin/main

# Interactive wizard
grove add -i

# Use a template
grove add example-app feature/api-work --template=backend

# Preview without executing
grove add example-app feature/new-work --dry-run
```

**What it does**

1. Fetches the latest branches from remote
2. Runs `pre-add` lifecycle hooks (a non-zero exit aborts the operation)
3. Creates the worktree directory at `~/Herd/<repo>-worktrees/<site-name>/`
4. Pushes new branches to remote and sets up tracking
5. Stores the base ref (`git config --local grove.base`) so later `sync`/`diff`/`summary` default to the same base
6. Runs `post-add` lifecycle hooks

> `--force` only affects the new-branch case: without it, `add` refuses to create a branch that exists neither locally nor on remote. It does **not** bypass `BRANCH_PATTERN` validation, which is enforced separately.

**JSON output**

Object: `{path, url, branch, database}`.

```json
{"path": "/Users/you/Herd/example-app-worktrees/login", "url": "https://login.test", "branch": "feature/login", "database": "example_app__feature_login"}
```

---

### grove rm

Removes a worktree with cleanup of associated resources.

**Usage**

```bash
grove rm [-f] [--delete-branch] [--drop-db] [--no-backup] [--ledger-ack <token>] <repo> [branch]
```

If `branch` is omitted and `fzf` is installed, an interactive picker is shown.

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Skip uncommitted changes warning and protected branch check |
| `--delete-branch` | Also delete the local git branch |
| `--drop-db` | Request that the database be dropped (delegated to hooks) |
| `--no-backup` | Request that the database backup be skipped (delegated to hooks) |
| `--json` | Output result as JSON |

**Examples**

```bash
# Interactive selection (requires fzf)
grove rm example-app

# Explicit branch
grove rm example-app feature/done

# When the Worktree Ledger refuses a removal, `-f` does NOT override it.
# Issue a one-use code first, then pass it:
way worktree removal-check --acknowledge      # run inside the worktree
grove rm -f --ledger-ack ack1.ack_019f… example-app feature/done

# Force remove (bypass warnings)
grove rm -f example-app feature/done

# Remove worktree and delete the local branch
grove rm --delete-branch example-app feature/done

# Drop database too
grove rm --drop-db example-app feature/done

# Combined
grove rm -f --delete-branch --drop-db example-app feature/done
```

**What it does**

1. Runs `pre-rm` lifecycle hooks (a non-zero exit aborts removal)
2. Removes the worktree directory
3. Optionally deletes the local branch (`--delete-branch`)
4. Prunes stale worktree references
5. Runs `post-rm` lifecycle hooks

> Database backup/drop is **not** performed by `rm` itself — it is delegated to the lifecycle hooks. `--drop-db`/`--no-backup` are intent flags passed through to those hooks; the JSON contract reports `db_drop_requested` (the request), not a confirmed drop.

**Safety**

- Protected branches (`staging`, `main`, `master`) require `-f` to remove
- Warns if there are uncommitted changes (override with `-f`)
- `--delete-branch` only removes the local branch, not the remote

**JSON output**

Object: `{success, repo, branch, path, branch_deleted, db_drop_requested}`. `branch_deleted` reflects the real deletion outcome; `db_drop_requested` reflects the `--drop-db` flag only.

```json
{"success": true, "repo": "example-app", "branch": "feature/done", "path": "/Users/you/Herd/example-app-worktrees/done", "branch_deleted": true, "db_drop_requested": false}
```

**See also:** [grove add](#grove-add), [grove move](#grove-move)

---

### grove move

Renames or moves a worktree, automatically handling Laravel Herd SSL certificates.

**Usage**

```bash
grove move <repo> <branch> <new-name>
```

If `branch` is omitted and `fzf` is installed, an interactive branch picker is shown. If `<new-name>` is omitted, grove prompts `New directory name:` interactively. The fzf picker only covers branch selection — it does not choose the destination name.

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Skip confirmation prompt |

**Examples**

```bash
# Pick the branch via fzf, then enter the new name when prompted
grove move example-app

# Explicit
grove move example-app feature/login example-app-login

# Promote to top-level site
grove move example-app develop example-app
```

**What it does**

1. Validates source exists, destination does not
2. Detects if the old site has an SSL certificate via Herd
3. Runs `pre-move` lifecycle hooks (can abort)
4. Unsecures the old site if secured, moves the worktree, re-secures under new name
5. Runs `post-move` lifecycle hooks

---

### grove clone

Clones a repository as a bare repo and creates an initial worktree.

**Usage**

```bash
grove clone <git-url> [repo-name] [branch]
```

**Arguments**

| Argument | Description |
|----------|-------------|
| `<git-url>` | Remote repository URL |
| `[repo-name]` | Short name used in grove commands (default: derived from URL) |
| `[branch]` | Branch to create worktree for (default: staging/main/master) |

**Examples**

```bash
# Clone with auto-detected name
grove clone git@github.com:your-org/example-app.git

# Clone with custom name
grove clone git@github.com:your-org/example-app.git example-app

# Clone and checkout specific existing branch
grove clone git@github.com:your-org/example-app.git example-app feature/auth

# Clone and create new feature branch
grove clone git@github.com:your-org/example-app.git example-app feature/new-dashboard
```

**What it does**

1. Clones as a bare repository to `$HERD_ROOT/<repo>.git/`
2. Configures fetch to get all branches
3. Fetches all remote branches
4. Creates the initial worktree (auto-detects staging/main/master if no branch given)

**JSON output**

Object: `{success, repo, path, message}`. On failure `success` is `false` and `message` carries the git error.

```json
{"success": true, "repo": "example-app", "path": "/Users/you/Herd/example-app.git", "message": "Repository cloned successfully"}
```

> With `--json`, `clone` only creates the bare repo (the initial worktree is not created); the human-readable mode also creates an initial worktree.

**See also:** [grove add](#grove-add)

---

### grove ls

Lists all worktrees for a repository with detailed status.

**Usage**

```bash
grove ls <repo>
grove ls --json <repo>
```

**Examples**

```bash
grove ls example-app
grove ls --json example-app
grove ls --pretty example-app
```

**Output**

```text
[1] 📁 /Users/you/Herd/example-app-worktrees/example-app
    branch  🌿 staging
    sha     a1b2c3d
    state   ● clean
    sync    ↑0 ↓0
    url     🌐 https://example-app.test
    cd      cd '/Users/you/Herd/example-app-worktrees/example-app'
```

Mismatch warnings are shown when a worktree's directory name no longer matches its branch (e.g., after running `git checkout` inside the worktree).

**JSON output**

```json
[
  {
    "path": "/Users/you/Herd/example-app-worktrees/example-app",
    "branch": "staging",
    "sha": "a1b2c3d",
    "url": "https://example-app.test",
    "dirty": false,
    "ahead": 0,
    "behind": 0,
    "mismatch": false,
    "health_grade": "A",
    "health_score": 100,
    "lastAccessed": "2025-01-15T10:30:00Z",
    "merged": false,
    "stale": false
  }
]
```

---

### grove repos

Lists all bare repositories in `HERD_ROOT`.

**Usage**

```bash
grove repos
grove repos --json
```

**Output**

```text
📦 Repositories in /Users/you/Herd

  example-app (3 worktrees)
  example-api (1 worktrees)
```

**JSON output**

```json
[
  {"name": "example-app", "worktrees": 3},
  {"name": "example-api", "worktrees": 1}
]
```

---

### grove status

Shows a dashboard view of all worktrees with their state and sync status. The repo is required — `status` does **not** auto-detect from the current directory.

**Usage**

```bash
grove status <repo>
grove status --json <repo>
```

**Output**

```text
📊 Worktree Status: example-app

  BRANCH                         STATE        SYNC       SHA
  ──────────────────────────────────────────────────────────────────────
  staging                        ●            ↑0 ↓0      a1b2c3d
  feature/login                  ◐ 3          ↑5 ↓12     e4f5g6h
  feature/dashboard              ●            ↑2 ↓0      i7j8k9l
```

- `●` = clean, `◐ N` = N uncommitted changes
- `↑N` = commits ahead, `↓N` = commits behind (vs base branch)

**JSON output**

```json
[
  {
    "branch": "staging",
    "path": "/Users/you/Herd/example-app-worktrees/example-app",
    "sha": "a1b2c3d",
    "dirty": false,
    "changes": 0,
    "ahead": 0,
    "behind": 0,
    "stale": false,
    "age": "1d",
    "age_days": 1,
    "merged": false
  }
]
```

**See also:** [grove health](#grove-health), [grove dashboard](#grove-dashboard), [grove info](#grove-info)

---

### grove config

Shows current grove configuration.

**Usage**

```bash
grove config
grove config --json
```

**JSON output**

```json
{
  "success": true,
  "data": {
    "default_base_branch": "origin/staging",
    "protected_branches": ["staging", "main", "master"],
    "config_dir": "/Users/you/.grove",
    "hooks_dir": "/Users/you/.grove/hooks",
    "repos_dir": "/Users/you/Code",
    "hooks_enabled": true,
    "database": {
      "enabled": true,
      "host": "127.0.0.1",
      "user": "root"
    },
    "herd_enabled": false,
    "url_subdomain": null
  }
}
```

> Notes:
> - `repos_dir` reflects the `GROVE_REPOS_DIR` environment variable (default `~/Code`) and is informational only. grove stores bare repos and worktrees under `HERD_ROOT`, **not** `repos_dir`.
> - `grove config --json` always prints compact JSON — it does **not** honour `--pretty` (it bypasses the shared formatter). Every other JSON command does honour `--pretty`.

---

### grove templates

Lists available worktree templates or shows details of a specific template.

**Usage**

```bash
grove templates
grove templates <name>
```

**Examples**

```bash
# List all templates
grove templates

# Show template details
grove templates minimal
```

> **No templates are active by default.** `GROVE_TEMPLATES_DIR` defaults to `~/.grove/templates`, which is empty on a fresh install, so `grove templates` shows `(no templates found)` until you add some. The four example templates below ship under `examples/templates/` in the grove repo and must be **copied** into `~/.grove/templates/` (or your `GROVE_TEMPLATES_DIR`) before they appear.

**Output (list)**

On a fresh install:

```text
📋 Available Templates

  (no templates found)
```

Once you copy templates in (e.g. `cp examples/templates/*.conf ~/.grove/templates/`):

```text
📋 Available Templates

  backend - Backend only - PHP, database, no npm/build
  laravel - Laravel with MySQL, Composer, NPM, and migrations
  minimal - Minimal - git worktree only, no setup
  node - Node.js project (npm only, no PHP/database)

Usage: grove templates <name>  - Show template details
       grove add <repo> <branch> --template=<name>
```

**Example templates (bundled under `examples/templates/`)**

These are examples, **not** active by default — copy them into `GROVE_TEMPLATES_DIR` to use them.

| Template | Description |
|----------|-------------|
| `laravel` | Full Laravel setup — database, composer, npm, build, migrations |
| `node` | Node.js projects — npm only, skips PHP and database |
| `minimal` | Git worktree only — skips all setup hooks |
| `backend` | Backend API work — PHP and database, no frontend build |

**Creating custom templates**

Templates are key=value files in `GROVE_TEMPLATES_DIR` (default `~/.grove/templates/`):

```bash
# ~/.grove/templates/api-only.conf
TEMPLATE_DESC="API backend - database and PHP only"

GROVE_SKIP_NPM=true
GROVE_SKIP_BUILD=true
GROVE_SKIP_HERD=true
```

---

## Navigation

### grove cd

Prints the worktree path for use with `cd`.

**Usage**

```bash
cd "$(grove cd <repo> [branch])"
```

**Examples**

```bash
cd "$(grove cd example-app feature/login)"

# Interactive selection with fzf
cd "$(grove cd example-app)"
```

---

### grove code

Opens a worktree in your configured editor (Cursor, VS Code, Zed, etc.).

**Usage**

```bash
grove code <repo> [branch]
```

**Examples**

```bash
grove code example-app feature/login

# Interactive selection with fzf
grove code example-app
```

Configure the editor in `~/.groverc`:

```bash
DEFAULT_EDITOR=cursor  # or: code, zed, etc.
```

The editor is the same value under two different spellings depending on where you set it:

- In `~/.groverc`, use the **config-file key** `DEFAULT_EDITOR=...`.
- To override at runtime, export the **environment variable** `GROVE_EDITOR=...`.

If the configured editor is not on your `PATH`, grove falls back to `cursor`, then `code`.

`grove code` auto-detects the repo/branch when run from inside a worktree. With a repo but no branch (and `fzf` installed), it shows a picker. It also resolves aliases, `@N` shortcuts and fuzzy matches.

---

### grove open

Opens the worktree URL in your default browser.

**Usage**

```bash
grove open <repo> [branch]
```

**Examples**

```bash
grove open example-app feature/login

# Interactive selection with fzf
grove open example-app
```

---

### grove switch

Opens a worktree in your editor and browser simultaneously and prints the path for `cd`. The recommended way to switch context between worktrees.

**Usage**

```bash
cd "$(grove switch <repo> [branch])"
```

**Examples**

```bash
# Interactive selection with fzf
cd "$(grove switch example-app)"

# Explicit branch
cd "$(grove switch example-app feature/login)"
```

This single command:
1. Prints the worktree path (for `cd`)
2. Opens the worktree in your editor
3. Opens the URL in your browser
4. Fires `post-switch` lifecycle hooks (e.g. update a `-current` symlink and restart registered services, **if** you have configured such a hook — grove ships none by default)

`switch` requires an explicit repo (it does **not** auto-detect, by design — it switches *to* a different worktree). The branch may be chosen via fzf, and it resolves aliases, `@N` and fuzzy matches.

---

### grove exec

Runs a command inside a worktree directory.

**Usage**

```bash
grove exec <repo> <branch> <command...>
```

**Examples**

```bash
grove exec example-app feature/login php artisan migrate
grove exec example-app feature/login npm run dev
grove exec example-app feature/login git status
grove exec example-app feature/login php artisan test

# Pass a command containing leading dashes — use -- as an end-of-options sentinel
grove exec example-app feature/login -- ls -la
```

The command runs with the worktree directory as the working directory. Both `<repo>` and `<branch>` are required — `exec` does not auto-detect. Use `--` before the command to pass arguments that begin with a dash (otherwise grove's flag parser would consume them).

---

## Git Operations

### grove pull

Pulls latest changes for a specific worktree using `git pull --rebase`.

**Usage**

```bash
grove pull [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree. If a repo is given without a branch (and `fzf` is installed), a picker is shown.

**Examples**

```bash
# Auto-detect from inside a worktree
grove pull

# Interactive selection with fzf
grove pull example-app

# Explicit branch
grove pull example-app feature/login

# JSON output
grove pull --json example-app feature/login
```

Fires `post-pull` lifecycle hooks on success.

**JSON output**

Object: `{success, already_up_to_date, conflicts, commits_pulled, message}`.

```json
{"success": true, "already_up_to_date": false, "conflicts": false, "commits_pulled": 3, "message": "..."}
```

**See also:** [grove sync](#grove-sync), [grove pull-all](#grove-pull-all)

---

### grove pull-all

Pulls all worktrees for a repository in parallel.

**Usage**

```bash
grove pull-all <repo>
grove pull-all --all-repos
grove pull-all @<group>
```

**Flags**

| Flag | Description |
|------|-------------|
| `--all-repos` | Pull all worktrees across every repository (not supported with `--json`) |

**Examples**

```bash
grove pull-all example-app
grove pull-all --all-repos
grove pull-all @frontend
grove pull-all --json example-app
```

**Output**

```text
→ Fetching latest...
→ Pulling 3 worktree(s) in parallel...
✔   feature/login
✔   feature/dashboard
✔   staging

✔ Pulled 3 worktree(s)
```

Sends a macOS desktop notification when complete.

**JSON output** (single-repo only)

Object: `{repo, worktrees: [{branch, success, already_up_to_date, commits_pulled, message}], summary: {total, succeeded, failed, up_to_date}}`. Passing `--json` together with `--all-repos` is rejected with an error.

```json
{
  "repo": "example-app",
  "worktrees": [
    {"branch": "feature/login", "success": true, "already_up_to_date": false, "commits_pulled": 2, "message": "..."}
  ],
  "summary": {"total": 3, "succeeded": 3, "failed": 0, "up_to_date": 1}
}
```

**See also:** [grove pull](#grove-pull), [grove build-all](#grove-build-all)

---

### grove sync

Rebases a feature branch onto its base branch, keeping it up to date.

**Usage**

```bash
grove sync [repo] [branch] [base]
```

Auto-detects the repo/branch when run from inside a worktree.

**How the base branch is chosen**

1. If `[base]` is passed, that is used
2. If the worktree has a stored base (`git config --local grove.base`), that is used
3. Falls back to `GROVE_BASE_DEFAULT` / `DEFAULT_BASE` (default: `origin/staging`)

**Examples**

```bash
# Interactive with fzf
grove sync example-app

# Default base (origin/staging)
grove sync example-app feature/login

# Custom base
grove sync example-app feature/login origin/main
```

**Safety**

- Always fetches before rebasing
- Refuses to run with uncommitted changes

Equivalent to:

```bash
git fetch --all --prune
git rebase <base>
```

Fires `post-sync` lifecycle hooks on success.

**JSON output**

Object: `{success, base, conflicts, dirty, commits_rebased, message}`. If the worktree has uncommitted changes, `success` is `false` and `dirty` is `true`.

```json
{"success": true, "base": "origin/staging", "conflicts": false, "dirty": false, "commits_rebased": 2, "message": "..."}
```

**See also:** [grove diff](#grove-diff), [grove summary](#grove-summary), [grove log](#grove-log)

---

### grove diff

Shows diff stats between a worktree and its base branch.

**Usage**

```bash
grove diff [repo] [branch] [base]
```

Auto-detects the repo/branch when run from inside a worktree.

**Examples**

```bash
# Auto-detect from inside a worktree
grove diff

grove diff example-app feature/login
grove diff example-app feature/login origin/main

# JSON output
grove diff --json example-app feature/login
```

**JSON output**

Object: `{repo, branch, base, commits, summary}`. `commits` is the count of commits ahead of `base`; `summary` is the diffstat last line (e.g. `3 files changed, 45 insertions(+), 12 deletions(-)`).

```json
{"repo": "example-app", "branch": "feature/login", "base": "origin/staging", "commits": 5, "summary": "3 files changed, 45 insertions(+), 12 deletions(-)"}
```

**See also:** [grove summary](#grove-summary), [grove log](#grove-log), [grove sync](#grove-sync)

---

### grove summary

Gives a compact overview of how a worktree differs from its base branch.

**Usage**

```bash
grove summary [repo] [branch] [base]
grove summary --json [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree. Includes: ahead/behind counts, uncommitted changes, recent commits, diffstat.

**Examples**

```bash
# Auto-detect from current directory
grove summary

# Explicit
grove summary example-app feature/login

# Custom base
grove summary example-app feature/login origin/main

# JSON output
grove summary --json example-app feature/login
```

**JSON output**

```json
{
  "repo": "example-app",
  "branch": "feature/login",
  "path": "/Users/you/Herd/example-app-worktrees/login",
  "base": "origin/staging",
  "ahead": 5,
  "behind": 2,
  "ahead_commits_total": 5,
  "behind_commits_total": 2,
  "uncommitted": {"total": 3, "staged": 1, "modified": 2, "untracked": 0},
  "diff": {"shortstat": "3 files changed, 45 insertions(+), 12 deletions(-)", "summary": "..."},
  "ahead_commits": [{"sha": "abc1234", "subject": "Add login form"}],
  "behind_commits": []
}
```

---

### grove log

Shows recent commits on a worktree branch compared to its base.

**Usage**

```bash
grove log [repo] [branch] [-n <count>]
grove log --json [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree. Shows the most recent commits (default 5). `-n N` (or `-nN` with no space) limits the count.

**Examples**

```bash
# Auto-detect from inside a worktree
grove log

grove log example-app feature/login
grove log example-app feature/login -n 20
grove log --json example-app feature/login
```

**JSON output**

```json
{
  "commits": [
    {
      "sha": "abc1234",
      "message": "Add login validation",
      "author": "Jane Smith",
      "date": "2025-01-15T10:30:00+00:00"
    }
  ]
}
```

---

### grove changes

Gets uncommitted file changes for a worktree.

**Usage**

```bash
grove changes [repo] [branch]
grove changes --json [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree. `--json` output also honours `--pretty`.

**Examples**

```bash
# Auto-detect from inside a worktree
grove changes

grove changes example-app feature/login
grove changes --json example-app feature/login
```

**JSON output**

Object with a `files` array (each element is `{path, status}`):

```json
{
  "files": [
    {"path": "app/Http/Controllers/LoginController.php", "status": "M"},
    {"path": "tests/Feature/LoginTest.php", "status": "A"},
    {"path": "notes.txt", "status": "?"}
  ]
}
```

Status codes: `M` = modified, `A` = added, `D` = deleted, `R` = renamed, `C` = copied, `U` = unmerged, `?` = untracked, `!` = ignored.

---

### grove branches

Lists available branches for a repository (local and remote). Used by the grove-app Tauri desktop GUI.

**Usage**

```bash
grove branches <repo>
grove branches --json <repo>
```

**Examples**

```bash
grove branches example-app
grove branches --json example-app
```

**JSON output**

```json
{
  "repo": "example-app",
  "branches": [
    {
      "name": "staging",
      "type": "local",
      "has_worktree": true,
      "worktree_path": "/Users/you/Herd/example-app-worktrees/example-app",
      "sha": "a1b2c3d",
      "last_commit_at": 1736940600
    },
    {
      "name": "feature/new-work",
      "type": "remote",
      "has_worktree": false,
      "worktree_path": null,
      "sha": "e4f5g6h",
      "last_commit_at": 1736854200
    }
  ]
}
```

---

### grove prune

Cleans up stale worktree references and identifies merged branches.

**Usage**

```bash
grove prune <repo>
grove prune -f <repo>
grove prune --all-repos
```

Repo is required in single mode (does **not** auto-detect). With `--all-repos`, prunes across all repositories in parallel.

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Actually delete merged branches (dry run without this flag) |
| `--all-repos` | Operate on all repositories in parallel (not supported with `--json`) |

**Examples**

```bash
# Show what would be deleted (dry run)
grove prune example-app

# Delete merged branches
grove prune -f example-app

# All repos
grove prune --all-repos
```

**What it does**

1. Prunes stale worktrees (entries pointing to directories that no longer exist)
2. Identifies local branches merged into the repo's base branch (`DEFAULT_BASE`, falling back to `origin/main`, then `origin/master`, if the configured base does not exist)
3. Deletes merged branches (with `-f`)

**Safety**

- Never deletes protected branches (`staging`, `main`, `master` by default — see `PROTECTED_BRANCHES`)
- Only deletes local branches, not remote
- Branches checked out in a worktree cannot be deleted until the worktree is removed

**JSON output**

Object: `{repo, stale_refs_pruned, merged_branches: [{name, deleted, reason}], summary: {branches_found, branches_deleted}}`. Without `-f`, `deleted` is `false` for every branch (dry run).

```json
{
  "repo": "example-app",
  "stale_refs_pruned": 1,
  "merged_branches": [
    {"name": "feature/done", "deleted": true, "reason": "merged to origin/staging"}
  ],
  "summary": {"branches_found": 1, "branches_deleted": 1}
}
```

---

## Information & Monitoring

### grove dashboard

Visual overview of all repositories with health grades, worktree counts, and status indicators.

**Usage**

```bash
grove dashboard
grove dashboard -i
```

**Flags**

| Flag | Description |
|------|-------------|
| `-i`, `--interactive` | Interactive mode with quick actions (requires fzf) |

**Output**

```text
╔════════════════════════════════════════════════════════════════════╗
║                    grove Dashboard                                    ║
╚════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────┐
│ example-app                                           3 worktrees    A     │
├──────────────────────────────────────────────────────────────────────┤
│   staging              A    ●                                        │
│   feature/login        B    ◐ 3                                      │
│   feature/dashboard    A    ●                                        │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ example-api                                           1 worktrees    A     │
├──────────────────────────────────────────────────────────────────────┤
│   main                 A    ●                                        │
└──────────────────────────────────────────────────────────────────────┘

Summary: 2 repos, 4 worktrees, 1 dirty, 0 stale
```

> `grove dashboard` does **not** support `--json` — it errors and suggests `grove status`/`health`/`ls --json` instead.

**Interactive mode quick actions**

| Key | Action |
|-----|--------|
| `p` | Pull the selected worktree |
| `s` | Sync (rebase onto base branch) |
| `o` | Open in browser |
| `c` | Open in editor |
| `r` | Remove worktree (with confirmation) |
| `i` | Show detailed info |
| `Enter` | Print path for `cd` |

---

### grove info

Detailed information about a specific worktree.

**Usage**

```bash
grove info [repo] [branch]
grove info --json [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree.

**Examples**

```bash
# Auto-detect from inside a worktree
grove info

grove info example-app feature/login

# Interactive selection with fzf
grove info example-app

# JSON output
grove info --json example-app feature/login
```

> Set `GROVE_INFO_FAST=true` to skip the heavy disk-size and MySQL probes. JSON consumers should then expect zeroed `disk.*` fields and `database.exists: false` (metadata only). See [Environment-only variables](#environment-only-variables).

**Output**

```text
📋 Worktree Info: example-app / feature/login

Path:       /Users/you/Herd/example-app-worktrees/login
URL:        https://feature-login.test
Database:   example_app__feature_login
Branch:     feature/login
SHA:        a1b2c3d4

Health Score: 85/100 (B)
  ├─ Commits behind base: -10 (5 commits behind origin/staging)
  ├─ Uncommitted changes: -5 (3 files modified)
  ├─ Days since commit:   0 (committed today)
  ├─ Merge status:        0 (no conflicts)
  └─ Untracked files:     0 (none)

Sync Status:
  ├─ Ahead:  2 commits
  └─ Behind: 5 commits (vs origin/staging)

Last Commit: Fix login validation (2 hours ago)
```

**JSON output**

```json
{
  "repo": "example-app",
  "branch": "feature/login",
  "path": "/Users/you/Herd/example-app-worktrees/login",
  "url": "https://feature-login.test",
  "bare_repo": "/Users/you/Herd/example-app.git",
  "database": {"name": "example_app__feature_login", "exists": true},
  "git": {
    "sha": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
    "sha_short": "a1b2c3d",
    "branch": "feature/login",
    "tracking": "origin/feature/login",
    "ahead": 2,
    "behind": 5,
    "dirty": true,
    "changes": 3,
    "last_message": "Fix login validation",
    "last_author": "Jane Smith",
    "last_date": "2 hours ago"
  },
  "uncommitted": {"total": 3, "staged": 1, "modified": 2, "untracked": 0},
  "disk": {
    "size_bytes": 524288000,
    "size_human": "500 MB",
    "node_modules_bytes": 314572800,
    "vendor_bytes": 89128960
  },
  "framework": {
    "detected": "laravel",
    "version": "11.x",
    "php_version": "8.3",
    "node_deps": true
  },
  "timestamps": {
    "accessed_at": 1736940600,
    "last_commit_at": 1736933400
  },
  "health": {
    "grade": "B",
    "score": 85,
    "issues": ["5 commits behind base", "3 uncommitted files"]
  }
}
```

---

### grove recent

Lists recently accessed worktrees sorted by last access time.

**Usage**

```bash
grove recent [limit]
grove recent --json [limit]
```

**Examples**

```bash
# Show 5 most recent (default)
grove recent

# Show 10 most recent
grove recent 10

# JSON output
grove recent --json 10
```

**Output**

```text
📅 Recently Accessed Worktrees

  1. example-app / feature/login         2 hours ago
  2. example-app / staging               5 hours ago
  3. example-api / main                  1 day ago
  4. example-app / feature/dashboard     2 days ago
  5. example-app / bugfix/cart           5 days ago
```

**JSON output**

```json
[
  {
    "repo": "example-app",
    "branch": "feature/login",
    "path": "/Users/you/Herd/example-app-worktrees/login",
    "url": "https://login.test",
    "accessed_at": 1736940600,
    "accessed_ago": "2h ago",
    "dirty": false
  }
]
```

---

### grove health

Comprehensive health check on a repository identifying issues across all worktrees. The repo is required — `health` does **not** auto-detect from the current directory.

**Usage**

```bash
grove health <repo>
grove health --json <repo>
```

**Examples**

```bash
grove health example-app
grove health --json example-app
```

**What it checks**

1. Stale worktrees (references pointing to directories that no longer exist)
2. Orphaned databases (MySQL databases without corresponding worktrees)
3. Missing `.env` files
4. Branch consistency (directory names that don't match their branch)

**Output**

```text
🏥 Health Check: example-app

  BRANCH                    GRADE   SCORE   ISSUES
  ─────────────────────────────────────────────────────
  staging                   A       100     -
  feature/login             B       85      5 behind, 3 uncommitted
  feature/old-work          D       62      25 days old, 15 behind
  bugfix/stale              F       45      45 days old, 32 behind, conflicts
```

**JSON output**

```json
{
  "repo": "example-app",
  "overall_grade": "B",
  "overall_score": 83,
  "worktree_count": 4,
  "summary": {"healthy": 2, "warning": 1, "critical": 1},
  "issues": [
    {"severity": "warning", "worktree": "feature/old-work", "message": "25 days since last commit"},
    {"severity": "critical", "worktree": "bugfix/stale", "message": "Merge conflicts detected"}
  ],
  "worktrees": [
    {"branch": "staging", "grade": "A", "score": 100, "issues": []},
    {"branch": "feature/login", "grade": "B", "score": 85, "issues": ["5 commits behind base"]}
  ]
}
```

---

### grove report

Generates a markdown status report for all worktrees in a repository.

**Usage**

```bash
grove report <repo>
grove report <repo> --output <file>
```

**Examples**

```bash
# Output to console
grove report example-app

# Save to file
grove report example-app --output ~/Desktop/worktree-report.md
```

Includes: summary table with total/clean/dirty counts, per-worktree details (branch, status, ahead/behind, last commit), list of available lifecycle hooks.

> `report` has **no** `--json` mode — it always emits markdown (to stdout, or to the file given by `--output`).

---

### grove clean

Removes `node_modules/` and `vendor/` from inactive worktrees to free disk space.

**Usage**

```bash
grove clean [repo]
grove clean -f [repo]
```

Auto-detects the repo when run from inside a worktree. Bare `grove clean` (no repo) operates across **all** repositories.

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Skip confirmation prompt (auto-confirm) |

**Examples**

```bash
# Auto-detect from inside a worktree
grove clean

# One repo
grove clean example-app
grove clean -f example-app

# All repositories (previews, then confirms)
grove clean
```

**Notes**

- The inactivity window defaults to **30 days**, overridable via the `GROVE_CLEAN_INACTIVE_DAYS` environment variable. Only worktrees not accessed within the window are affected.
- Bare `grove clean` previews the affected worktrees and prompts for confirmation before deleting across all repos (auto-confirmed with `-f`). `grove clean <repo>` scopes to one repo.
- Worktrees remain functional — run `composer install` / `npm install` when you return to them.

---

## Laravel Commands

### grove fresh

Resets a Laravel application to a clean state. Drops all tables and rebuilds.

**Usage**

```bash
grove fresh [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree.

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Skip the destructive-action confirmation prompt before `migrate:fresh` |

**Examples**

```bash
# Auto-detect from inside a worktree
grove fresh

# Interactive selection with fzf
grove fresh example-app

# Explicit branch
grove fresh example-app feature/login
```

**What it does**

1. If an `artisan` file is present: runs `php artisan migrate:fresh --seed`. Unless `-f` is given, it first prompts `Continue with migrate:fresh? [y/N]` (answering no skips this step).
2. If a `package.json` file is present: runs `npm ci`, then `npm run build`.

Steps are skipped when their marker file is absent, so the command is safe to run on non-Laravel or non-Node worktrees.

> **Caution:** `migrate:fresh` drops all tables. Use with care on worktrees with data you want to keep.

---

### grove migrate

Runs Laravel migrations for a worktree.

**Usage**

```bash
grove migrate [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree.

**Examples**

```bash
# Auto-detect from inside a worktree
grove migrate

grove migrate example-app feature/login

# Interactive selection with fzf
grove migrate example-app
```

Equivalent to `php artisan migrate` in the worktree directory.

---

### grove tinker

Opens Laravel Tinker (interactive REPL) in the worktree's context.

**Usage**

```bash
grove tinker [repo] [branch]
```

Auto-detects the repo/branch when run from inside a worktree.

**Examples**

```bash
# Auto-detect from inside a worktree
grove tinker

grove tinker example-app feature/login

# Interactive selection with fzf
grove tinker example-app
```

Models and services are available because Tinker runs in the worktree's context.

---

## Parallel Operations

### grove build-all

Runs `npm run build` on all worktrees for a repository in parallel.

**Usage**

```bash
grove build-all <repo>
grove build-all --all-repos
grove build-all @<group>
```

**Flags**

| Flag | Description |
|------|-------------|
| `--all-repos` | Build all worktrees across every repository |

**Examples**

```bash
grove build-all example-app
grove build-all --all-repos
grove build-all @frontend
```

---

### grove exec-all

Executes an arbitrary command across all worktrees for a repository in parallel.

**Usage**

```bash
grove exec-all <repo> <command>
grove exec-all --all-repos <command>
grove exec-all @<group> <command>
```

**Flags**

| Flag | Description |
|------|-------------|
| `--all-repos` | Execute in all worktrees across every repository |

**Examples**

```bash
grove exec-all example-app npm test
grove exec-all example-app php artisan cache:clear
grove exec-all --all-repos "php artisan cache:clear"
grove exec-all @backend "php artisan queue:restart"

# Pass a command containing leading dashes — use -- as an end-of-options sentinel
grove exec-all example-app -- ls -la
```

> **Note:** Warns about potentially destructive commands (e.g., `migrate:fresh`, `db:drop`). Use `--` before the command to pass arguments that begin with a dash.

---

### Parallel concurrency

Configure maximum concurrent operations via `GROVE_MAX_PARALLEL` (default: `4`):

```bash
# In ~/.groverc
GROVE_MAX_PARALLEL=8
```

---

## Service Management

Service management is optional and only active when apps are registered. Service commands are safe to run with no apps registered: `restart` is a silent no-op for unregistered apps (and for bare/no-args invocations), which makes it safe to call from hooks, while `status` and `doctor` still report daemon (Supervisor, Redis) and dependency health. Configuration is lazy-loaded from the registry only when `grove services` is invoked. Bare `grove services` (no subcommand) shows status if any apps are registered, otherwise prints the services help.

App registry file: `~/.grove/services/apps.conf`

```text
# app_name|system_name|services|supervisor_process|domain
myapp|myapp|horizon|myapp-horizon|myapp.test
```

| Field | Description | Default |
|-------|-------------|---------|
| `app_name` | Short name for commands | (required) |
| `system_name` | Directory name in Herd | Same as app_name |
| `services` | `horizon`, `horizon:reverb`, or `none` | `horizon` |
| `supervisor_process` | Supervisor process pattern | `<system_name>-horizon` |
| `domain` | Local .test domain | `<system_name>.test` |

### grove services status

Shows status of supervisor daemon, Redis, and all registered app services.

**Usage**

```bash
grove services status
grove services status <app>
```

**Examples**

```bash
grove services status
grove services status myapp
```

---

### grove services start

Starts services (supervisor process + scheduler LaunchAgent) for an app.

**Usage**

```bash
grove services start <app|all>
```

**Examples**

```bash
grove services start myapp
grove services start all
```

---

### grove services stop

Stops services for an app.

**Usage**

```bash
grove services stop <app|all>
```

**Examples**

```bash
grove services stop myapp
grove services stop all
```

---

### grove services restart

Restarts services for an app. Called automatically by the `post-switch` hook.

**Usage**

```bash
grove services restart <app|all>
```

**Examples**

```bash
grove services restart myapp
grove services restart all
```

Exits silently (a no-op) when the app is not registered, or when called with no arguments — making it safe to call idempotently from hooks.

---

### grove services apps

Lists all registered apps and their configuration.

**Usage**

```bash
grove services apps
grove services apps --json
```

**JSON output**

```json
[
  {
    "name": "myapp",
    "system_name": "myapp",
    "services": "horizon",
    "supervisor_process": "myapp-horizon",
    "domain": "myapp.test"
  }
]
```

---

### grove services add

Registers a new app in the service registry.

**Usage**

```bash
grove services add <name> [options]
```

**Options**

| Option | Description | Default |
|--------|-------------|---------|
| `--system-name=<name>` | Directory name in Herd | Same as `<name>` |
| `--services=<type>` | `horizon`, `horizon:reverb`, or `none` | `horizon` |
| `--supervisor=<process>` | Supervisor process name/pattern | `<system_name>-horizon` |
| `--domain=<domain>` | Local .test domain | `<system_name>.test` |

**Examples**

```bash
grove services add myapp
grove services add myapp --system-name=myapp-repo --services=horizon:reverb --domain=myapp.test
```

---

### grove services remove

Removes an app from the service registry.

**Usage**

```bash
grove services remove <name>
```

**Examples**

```bash
grove services remove myapp
```

---

### grove services horizon

Opens the Laravel Horizon dashboard in your browser.

**Usage**

```bash
grove services horizon <app>
```

**Examples**

```bash
grove services horizon myapp
```

---

### grove services logs

Tails a log file for an app's services.

**Usage**

```bash
grove services logs <app> [type]
```

**Types**

| Type | Log file | Notes |
|------|----------|-------|
| `horizon` | `storage/logs/horizon.log` | Default if no type given |
| `queue` | `storage/logs/horizon.log` | Alias of `horizon` — tails the same file |
| `reverb` | `storage/logs/reverb.log` | |
| `scheduler` | `~/Library/Logs/<app>-scheduler.log` | |

**Examples**

```bash
grove services logs myapp            # Tail Horizon logs (default)
grove services logs myapp queue      # Same as horizon
grove services logs myapp reverb     # Tail Reverb logs
grove services logs myapp scheduler  # Tail scheduler logs
```

---

### grove services doctor

Runs a services health check.

**Usage**

```bash
grove services doctor
```

**What it checks**

- Homebrew, PHP, Redis (`redis-cli ping`), and Supervisor (`brew services` shows it started)
- The Supervisor config directory exists and the number of `*.ini` configs in it
- When apps are registered: each app's `<system_name>-current` symlink exists and points to a real directory, and each app's Supervisor process status (RUNNING / other)

---

## Utilities

### grove doctor

Checks your system configuration and available tools.

**Usage**

```bash
grove doctor
```

**Output**

```text
🩺 grove doctor

Configuration
✔ HERD_ROOT: /Users/you/Herd
  DB_BACKUP_DIR does not exist (will be created on first backup)

Required Tools
✔ git: git version 2.43.0
✔ composer: Composer version 2.7.1

Optional Tools
✔ mysql: mysql Ver 8.0.36
✔   MySQL connection: OK
✔ herd: installed
✔ fzf: installed
✔ editor: cursor

Config Files
✔ User config: /Users/you/.groverc
  Project config: /Users/you/Herd/.groveconfig (not found)

✔ All checks passed!
```

---

### grove setup

First-time configuration wizard.

**Usage**

```bash
grove setup
```

The wizard walks through seven numbered sections:
1. **Worktree Directory** — `HERD_ROOT` (default: `~/Herd`); offers to create it if missing.
2. **Default Base Branch** — `DEFAULT_BASE` (e.g. `origin/staging` or `origin/main`).
3. **Default Editor** — `DEFAULT_EDITOR`; auto-detects installed editors (`cursor`, `code`, `zed`, …).
4. **Database Settings** — optional MySQL connection plus an "auto-create databases?" prompt (leave empty to skip database features).
5. **Branch Naming Pattern** — optional `BRANCH_PATTERN` regex (leave empty to allow any branch name).
6. **Creating directories** — creates `~/.grove/hooks/` and `~/.grove/templates/`.
7. **Writing configuration** — writes `~/.groverc` (backing up any existing file).

It then prints suggested **next steps** — clone a repository, create a worktree, and run `grove doctor`. The wizard **does not** run `grove doctor` for you.

---

### grove repair

Scans for and fixes common issues: orphaned worktrees, stale git locks.

**Usage**

```bash
grove repair [repo]
grove repair --recovery [repo]
```

**Flags**

| Flag | Description |
|------|-------------|
| `--recovery` | Attempt recovery of partially-created worktrees |

**Examples**

```bash
grove repair example-app
grove repair --recovery example-app
```

---

### grove upgrade

Self-update to the latest version.

**Usage**

```bash
grove upgrade
grove --version --check
```

**Examples**

```bash
# Check for updates
grove --version --check

# Upgrade
grove upgrade
```

`grove upgrade` is a guarded self-update over your local clone: it runs `git pull --rebase` on the default branch (`main`, falling back to `master`) and rebuilds with `./build.sh`. There are no downloads or checksum steps. It refuses to run on a feature branch or with a dirty working tree. See [Self-Update](../guides/advanced.md#self-update) for the full behaviour.

**Output (upgrade)**

```text
ℹ Repository: /Users/you/Projects/grove-cli
ℹ Current version: v4.1.0
ℹ Fetching updates...
ℹ Updates available: 3 new commit(s)

Upgrade now? [y/N] y
ℹ Pulling updates...
ℹ Rebuilding...

✔ Upgraded: v4.1.0 → v4.2.0

Verify with: grove --version
```

---

### grove version

Prints the grove version string.

**Usage**

```bash
grove version
grove --version
grove -v
```

`grove version`, `grove --version` and `grove -v` all print `grove version <x.y.z>`. Only `grove --version --check` performs the update check (see [grove upgrade](#grove-upgrade)).

---

### grove cleanup-herd

Removes orphaned Herd nginx configs (entries with no corresponding worktree directory).

**Usage**

```bash
grove cleanup-herd
```

---

### grove unlock

Removes stale git index lock files that can prevent git operations.

**Usage**

```bash
grove unlock [repo]
```

**Examples**

```bash
grove unlock example-app
grove unlock          # All repos
```

---

### grove share-deps

Shares `vendor/` and `node_modules/` across worktrees with identical lockfiles to save disk space.

**Usage**

```bash
grove share-deps           # Show status (default action)
grove share-deps enable    # Enable sharing (from within a worktree)
grove share-deps disable   # Disable and restore local copies
grove share-deps clean     # Remove unused shared caches (global cleanup)
```

Auto-detects the repo/branch when run from inside a worktree; otherwise it uses an fzf picker. The action defaults to `status`. The `clean` action works but is not listed in `grove --help`.

**How it works**

1. Dependencies are moved to `~/.grove/shared-deps/` and symlinked back
2. Cache key is the MD5 hash of lockfiles (`composer.lock`, `package-lock.json`, `yarn.lock`)
3. Lockfile changes automatically create a new cache entry
4. Multiple worktrees with identical dependencies share a single copy

**Output (status)**

```text
Dependency Status

  ● vendor: shared (a1b2c3d4e5f6)
  ● node_modules: shared (f6e5d4c3b2a1)
```

---

### grove alias

Manages branch aliases — shortcuts for frequently accessed worktrees.

**Usage**

```bash
grove alias                           # List all aliases
grove alias add <name> <repo/branch>  # Create alias
grove alias rm <name>                 # Remove alias
```

**Examples**

```bash
# Create aliases
grove alias add login example-app/feature/user-authentication
grove alias add staging example-app/staging

# List aliases
grove alias

# Use an alias with navigation commands
grove code login
cd "$(grove switch login)"
grove open api

# Remove alias
grove alias rm login
```

**Output (list)**

```text
📝 Branch Aliases

  login    → example-app/feature/user-authentication
  staging  → example-app/staging
```

Aliases are stored in `~/.grove/aliases`.

---

### grove group

Manages named groups of repositories for batch operations.

**Usage**

```bash
grove group                              # List all groups
grove group add <name> <repo...>         # Create/update a group
grove group show <name>                  # Show repos in a group
grove group rm <name>                    # Delete a group
```

**Examples**

```bash
# Create a group
grove group add frontend example-app example-api

# Use with batch commands (@ prefix)
grove pull-all @frontend
grove build-all @backend
grove exec-all @frontend "npm run lint"

# Manage groups
grove group
grove group show frontend
grove group rm frontend
```

Groups are stored in `~/.grove/groups`.

---

### grove restructure

Migrates existing worktrees from the old `repo--branch` directory structure to the new hierarchical `repo-worktrees/feature-name` structure.

**Usage**

```bash
grove restructure [repo]
```

**Examples**

```bash
# Migrate all worktrees for a specific repo
grove restructure example-app

# Migrate all repositories
grove restructure
```

One-time migration command for users upgrading from v3.x to v4.x.

---

## Global Flags

Flags can appear anywhere in the command line:

```bash
grove -f prune example-app        # ✔
grove prune -f example-app        # ✔
grove prune example-app -f        # ✔
```

| Flag | Description |
|------|-------------|
| `-q`, `--quiet` | Suppress informational output |
| `-f`, `--force` | Skip confirmations, force operations |
| `-i`, `--interactive` | Interactive worktree creation wizard (bare `grove -i` with no command also enters the wizard) |
| `--dry-run` | Preview worktree creation without executing (`grove add`) |
| `--json` | Output in JSON format (data contract) |
| `--pretty` | Colourised, formatted JSON output (uses `jq`/`python3`, with a plain fallback). Ignored by `grove config --json`. |
| `--no-cache` | Bypass the fetch cache — always fetch fresh from remote (sets `GROVE_FETCH_CACHE_TTL=0`) |
| `--refresh` | Clear the fetch cache before running the command |
| `-t`, `--template=<name>` | Use a template when creating a worktree (`-t <name>` or `--template=<name>`) |
| `--delete-branch` | Delete branch when removing worktree (with `rm`) |
| `--drop-db` | Request the database be dropped when removing a worktree (with `rm`) |
| `--no-backup` | Request the database backup be skipped when removing a worktree (with `rm`) |
| `--all-repos` | Broaden `prune`/`pull-all`/`build-all`/`exec-all` to all repositories |
| `--recovery` | Attempt more aggressive recovery (with `repair`) |
| `--output <file>` | Write output to a file (with `report`) |
| `-n N`, `-nN` | Limit the number of commits shown (with `log`) |
| `--check` | Check for updates (with `--version`) |
| `-v`, `--version` | Show version (also available as the `grove version` subcommand) |
| `--` | End-of-options sentinel — everything after it is passed through verbatim (lets `exec`/`exec-all` run commands containing dashes) |
| `-h`, `--help` | Show usage and exit (same as the `help` command) |

> Although `--check`, `--all-repos`, `--recovery`, `--output` and `-n` are conceptually per-command, they are parsed by grove's global flag parser, so they may appear anywhere on the command line.

**Flag usage by command**

| Command | Supported flags |
|---------|----------------|
| `add` | `-i`, `--dry-run`, `--json`, `-t`/`--template`, `-f` |
| `rm` | `-f`, `--delete-branch`, `--drop-db`, `--no-backup`, `--json`, `--pretty` |
| `move` | `-f` |
| `clone` | `--json`, `--pretty` |
| `ls` | `--json`, `--pretty` |
| `status` | `--json`, `--pretty` |
| `summary` | `--json`, `--pretty` |
| `diff` | `--json`, `--pretty` |
| `log` | `--json`, `--pretty`, `-n <count>` |
| `changes` | `--json`, `--pretty` |
| `branches` | `--json`, `--pretty` |
| `recent` | `--json`, `--pretty` |
| `info` | `--json`, `--pretty` |
| `health` | `--json`, `--pretty` |
| `repos` | `--json`, `--pretty` |
| `config` | `--json` (does **not** honour `--pretty`) |
| `pull` | `--json`, `--pretty` |
| `sync` | `--json`, `--pretty` |
| `pull-all` | `--all-repos`, `--json`, `--pretty` (`--json` rejected with `--all-repos`) |
| `services apps` | `--json`, `--pretty` |
| `prune` | `-f`, `--all-repos` (`--json` rejected with `--all-repos`) |
| `build-all` | `--all-repos` |
| `exec-all` | `--all-repos` |
| `clean` | `-f` |
| `fresh` | `-f` |
| `repair` | `--recovery` |
| `report` | `--output <file>` (no `--json`) |
| `--version` | `--check` |
| All commands | `-q`, `--no-cache`, `--refresh` |

> `report` does not have a `--json` mode; `dashboard` rejects `--json`.

---

## Shell Completion

grove ships with a Zsh completion script (`_grove`) that completes commands, repositories, and branches. The installer links it into your completions directory automatically. To install it manually, place `_grove` on your `fpath` (e.g. `~/.zsh/completions/`) and ensure that directory is loaded before `compinit`:

```bash
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

Alternatively, source it directly: `source /path/to/_grove`.

---

## JSON Output Reference

Every command that accepts `--json` outputs valid JSON that can be piped to `jq` or `python3`. This table lists all of them:

```bash
grove ls example-app --json | python3 -c "import json,sys; json.load(sys.stdin)"
```

| Command | Output type | Top-level shape |
|---------|-------------|-----------------|
| `grove repos --json` | Array | `[{name, worktrees}]` |
| `grove ls <repo> --json` | Array | `[{path, branch, sha, url, dirty, ahead, behind, mismatch, health_grade, health_score, lastAccessed, merged, stale}]` |
| `grove status <repo> --json` | Array | `[{branch, path, sha, dirty, changes, ahead, behind, stale, age, age_days, merged}]` |
| `grove branches <repo> --json` | Object | `{repo, branches: [{name, type, has_worktree, worktree_path, sha, last_commit_at}]}` |
| `grove recent --json` | Array | `[{repo, branch, path, url, accessed_at, accessed_ago, dirty}]` |
| `grove health <repo> --json` | Object | `{repo, overall_grade, overall_score, worktree_count, summary, issues, worktrees}` |
| `grove log [repo] [branch] --json` | Object | `{commits: [{sha, message, author, date}]}` |
| `grove changes [repo] [branch] --json` | Object | `{files: [{path, status}]}` |
| `grove diff [repo] [branch] --json` | Object | `{repo, branch, base, commits, summary}` |
| `grove summary [repo] [branch] --json` | Object | `{repo, branch, path, base, ahead, behind, ahead_commits_total, behind_commits_total, uncommitted, diff, ahead_commits, behind_commits}` |
| `grove config --json` | Object | `{success, data: {default_base_branch, protected_branches, config_dir, hooks_dir, repos_dir, hooks_enabled, database, herd_enabled, url_subdomain}}` (compact; ignores `--pretty`) |
| `grove info [repo] [branch] --json` | Object | `{repo, branch, path, url, bare_repo, database, git, uncommitted, disk, framework, timestamps, health}` |
| `grove add <repo> <branch> --json` | Object | `{path, url, branch, database}` |
| `grove rm <repo> [branch] --json` | Object | `{success, repo, branch, path, branch_deleted, db_drop_requested}` |
| `grove clone <url> --json` | Object | `{success, repo, path, message}` |
| `grove pull [repo] [branch] --json` | Object | `{success, already_up_to_date, conflicts, commits_pulled, message}` |
| `grove sync [repo] [branch] --json` | Object | `{success, base, conflicts, dirty, commits_rebased, message}` |
| `grove pull-all <repo> --json` | Object | `{repo, worktrees: [{branch, success, already_up_to_date, commits_pulled, message}], summary: {total, succeeded, failed, up_to_date}}` (rejected with `--all-repos`) |
| `grove prune <repo> --json` | Object | `{repo, stale_refs_pruned, merged_branches: [{name, deleted, reason}], summary: {branches_found, branches_deleted}}` (rejected with `--all-repos`) |
| `grove services apps --json` | Array | `[{name, system_name, services, supervisor_process, domain}]` |

> `grove dashboard` and `grove report` do **not** support `--json`.

---

## Branch Shortcuts

The navigation commands (`grove cd`, `grove code`, `grove open`, `grove switch`) accept several shorthand forms. There are two distinct mechanisms that resolve different arguments:

### Aliases — resolve the *repo* argument

An alias is a user-defined name that resolves the **repo** argument (via `resolve_repo_arg`) in `code`/`open`/`cd`/`switch`. Aliases are created with [grove alias](#grove-alias) and stored in the aliases file.

```bash
grove alias add login example-app/feature/user-authentication

grove code login          # resolves the 'login' alias
cd "$(grove switch login)"
grove open api
```

### `@N` and fuzzy matching — resolve the *branch* argument

These resolve the **branch** argument against the repo's existing worktrees. They are not standalone commands.

**Numeric shortcuts** (`@1`, `@2`, `@3`) resolve to the Nth most recently modified worktree for that repo (`@1` = most recent):

```bash
grove code example-app @1            # Open the most recently modified worktree
cd "$(grove switch example-app @2)"  # Switch to the second most recent
```

**Fuzzy branch matching** — if no exact worktree matches the query, grove picks the closest branch:

```bash
grove code example-app feat-auth     # Matches e.g. feature/auth-improvements
grove open example-app dash          # Matches e.g. feature/dashboard
```

### Repository groups

`@<group>` names (created with [grove group](#grove-group)) expand to a set of repositories for multi-repo operations such as `pull-all`, `build-all` and `exec-all`.

```bash
grove pull-all @frontend
```

---

## Configuration

grove reads settings from two places with **different spellings**:

- The **config file** (`~/.groverc`, and per-repo `.groveconfig`) uses bare keys such as `DEFAULT_BASE` and `DB_USER`.
- **Environment variables** use the `GROVE_*` namespace, e.g. `GROVE_BASE_DEFAULT`, `GROVE_DB_USER`.

When the two names differ, the env var overrides the config-file key at runtime. Use the right spelling for where you set it — putting `GROVE_EDITOR=` in `~/.groverc` (or exporting `DEFAULT_EDITOR=`) will **not** work.

### Config-file keys (`~/.groverc`)

These are the keys recognised in `~/.groverc`. Only the path-typed keys expand `$HOME` and a leading `~`. Per-repo `.groveconfig` (in the bare repo) may override only `DEFAULT_BASE`, `GROVE_URL_SUBDOMAIN`, `PROTECTED_BRANCHES`, and `GROVE_STALE_THRESHOLD`.

| Config-file key | Env override | Default | Description |
|-----------------|--------------|---------|-------------|
| `HERD_ROOT` | `HERD_ROOT` | `$HOME/Herd` | Root directory where Herd sites/bare repos live (path) |
| `HERD_CONFIG` | — | `$HOME/Library/Application Support/Herd/config` | Herd config directory; used by `cleanup-herd` (path) |
| `DEFAULT_BASE` | `GROVE_BASE_DEFAULT` | `origin/staging` | Default base for `add`, rebase target for `sync` |
| `DEFAULT_EDITOR` | `GROVE_EDITOR` | `cursor` | Editor for `code`/`switch` (path) |
| `GROVE_URL_SUBDOMAIN` | `GROVE_URL_SUBDOMAIN` | (empty) | Subdomain prefix for URLs (e.g. `api` → `api.feature.test`) |
| `GROVE_MAX_PARALLEL` | `GROVE_MAX_PARALLEL` | `4` | Max concurrent parallel operations (positive integer) |
| `DB_HOST` | `GROVE_DB_HOST` | `127.0.0.1` | MySQL host |
| `DB_PORT` | `GROVE_DB_PORT` | `3306` | MySQL port; used by `doctor`'s connection check |
| `DB_USER` | `GROVE_DB_USER` | `root` | MySQL user |
| `DB_PASSWORD` | `GROVE_DB_PASSWORD` | (empty) | MySQL password |
| `DB_CREATE` | `GROVE_DB_CREATE` | `true` | Gate for the reference DB-create helper (delegated to hooks; not automatic on `add`) |
| `DB_BACKUP_DIR` | `GROVE_DB_BACKUP_DIR` | `$HOME/.grove/backups` | Database backup directory (path) |
| `DB_BACKUP` | `GROVE_DB_BACKUP` | `true` | Gate for the reference DB-backup helper (delegated to hooks; not automatic on `rm`) |
| `GROVE_HOOKS_DIR` | `GROVE_HOOKS_DIR` | `$HOME/.grove/hooks` | Lifecycle hook scripts directory (path) |
| `GROVE_TEMPLATES_DIR` | `GROVE_TEMPLATES_DIR` | `$HOME/.grove/templates` | Worktree template `.conf` directory (path) |
| `PROTECTED_BRANCHES` | `GROVE_PROTECTED_BRANCHES` | `staging main master` | Space-separated branches requiring `-f` to remove |
| `BRANCH_PATTERN` | `GROVE_BRANCH_PATTERN` | (empty) | Optional regex enforced on new branch names (empty = no enforcement) |
| `BRANCH_EXAMPLES` | `GROVE_BRANCH_EXAMPLES` | `feature/my-feature, bugfix/fix-login` | Example names shown when `BRANCH_PATTERN` validation fails |
| `REPO_GROUPS` | `GROVE_REPO_GROUPS` | (empty) | Predefined repository groups for multi-repo operations |
| `GROVE_SHARED_DEPS_DIR` | `GROVE_SHARED_DEPS_DIR` | `$HOME/.grove/shared-deps` | Shared `vendor`/`node_modules` cache directory (path) |
| `GROVE_STALE_THRESHOLD` | `GROVE_STALE_THRESHOLD` | `50` | Commits-behind-base before a branch is flagged stale (non-negative integer; per-repo overridable) |

### Environment-only variables

These are tunables read only from the environment (not from the config file):

| Variable | Default | Description |
|----------|---------|-------------|
| `GROVE_CONFIG` | `~/.groverc` | Path to the user config file |
| `GROVE_REPOS_DIR` | `~/Code` | Reported as `repos_dir` by `grove config`; informational only (grove stores worktrees under `HERD_ROOT`) |
| `GROVE_FETCH_CACHE_TTL` | `30` | Fetch cache lifetime in seconds (`0` disables caching; `--no-cache` sets it to `0`) |
| `GROVE_CLEAN_INACTIVE_DAYS` | `30` | Inactivity window (days) before `grove clean` considers a worktree's dependencies removable |
| `GROVE_INFO_FAST` | `false` | When `true`, `grove info --json` skips the heavy disk-size and MySQL probes (zeroed `disk.*` fields, `database.exists: false`) |

---

## Health Score System

Every worktree receives a health score from 0–100, shown as a letter grade. Used by `grove dashboard`, `grove health`, `grove info`, and `grove status`.

### Score calculation

Starts at 100 and deducts:

| Factor | Max deduction | Rate |
|--------|---------------|------|
| Commits behind base | −30 | −2 per commit (max 15 commits) |
| Uncommitted changes | −20 | −5 per file (max 4 files) |
| Days since last commit | −25 | −1 per day (max 25 days) |
| Merge conflicts | −10 | −10 if conflicted |
| Untracked files | −5 | −1 per file (max 5 files) |

### Grade scale

| Grade | Score range | Meaning |
|-------|-------------|---------|
| **A** | 90–100 | Excellent — up-to-date and clean |
| **B** | 80–89 | Good — minor issues |
| **C** | 70–79 | Fair — needs some attention |
| **D** | 60–69 | Poor — significant issues |
| **F** | 0–59 | Failing — urgent attention needed |

### Improving scores

| Issue | Solution |
|-------|----------|
| Commits behind | `grove sync <repo> <branch>` |
| Uncommitted changes | Commit or stash your work |
| Old commits | Make regular commits as you work |
| Merge conflicts | Resolve conflicts and complete the merge |
| Untracked files | Add to `.gitignore` or delete if not needed |
