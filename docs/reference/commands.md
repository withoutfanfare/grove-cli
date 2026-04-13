# Command Reference

> Complete reference for all grove commands. For getting started, see the [README](../../README.md).

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
| `-i`, `--interactive` | Guided 5-step creation wizard (requires fzf) |
| `--dry-run` | Preview what would happen without executing |
| `-t`, `--template=<name>` | Use a worktree template for setup hooks |
| `-f`, `--force` | Bypass branch naming pattern validation |
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

1. Fetches all branches from remote
2. Creates the worktree directory at `~/Herd/<repo>-worktrees/<site-name>/`
3. Pushes new branches to remote and sets up tracking
4. Runs `post-add` lifecycle hooks

**JSON output**

```json
{"path": "/Users/you/Herd/example-app-worktrees/login", "url": "https://login.test", "branch": "feature/login", "database": "example_app__feature_login"}
```

---

### grove rm

Removes a worktree with cleanup of associated resources.

**Usage**

```bash
grove rm <repo> [branch]
```

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Skip uncommitted changes warning and protected branch check |
| `--delete-branch` | Also delete the local git branch |
| `--drop-db` | Drop the database after backup |
| `--no-backup` | Skip database backup |

**Examples**

```bash
# Interactive selection (requires fzf)
grove rm example-app

# Explicit branch
grove rm example-app feature/done

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

1. Runs `pre-rm` lifecycle hooks (can abort removal)
2. Removes the worktree directory
3. Optionally deletes the local branch (`--delete-branch`)
4. Prunes stale worktree references
5. Runs `post-rm` lifecycle hooks

**Safety**

- Protected branches (`staging`, `main`, `master`) require `-f` to remove
- Warns if there are uncommitted changes (override with `-f`)
- `--delete-branch` only removes the local branch, not the remote

---

### grove move

Renames or moves a worktree, automatically handling Laravel Herd SSL certificates.

**Usage**

```bash
grove move <repo> <branch> <new-name>
```

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Skip confirmation prompt |

**Examples**

```bash
# Interactive selection (requires fzf)
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

Shows a dashboard view of all worktrees with their state and sync status.

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

**Output (list)**

```text
📋 Available Templates

  backend - Backend only - PHP, database, no npm/build
  laravel - Laravel with MySQL, Composer, NPM, and migrations
  minimal - Minimal - git worktree only, no setup
  node - Node.js project (npm only, no PHP/database)

Usage: grove templates <name>  - Show template details
       grove add <repo> <branch> --template=<name>
```

**Included templates**

| Template | Description |
|----------|-------------|
| `laravel` | Full Laravel setup - database, composer, npm, build, migrations |
| `node` | Node.js projects - npm only, skips PHP and database |
| `minimal` | Git worktree only - skips all setup hooks |
| `backend` | Backend API work - PHP and database, no frontend build |

**Creating custom templates**

Templates are key=value files in `~/.grove/templates/`:

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
4. Fires `post-switch` lifecycle hooks (which restart registered services)

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
```

The command runs with the worktree directory as the working directory.

---

## Git Operations

### grove pull

Pulls latest changes for a specific worktree using `git pull --rebase`.

**Usage**

```bash
grove pull <repo> [branch]
```

**Examples**

```bash
# Interactive selection with fzf
grove pull example-app

# Explicit branch
grove pull example-app feature/login
```

Fires `post-pull` lifecycle hooks on success.

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
| `--all-repos` | Pull all worktrees across every repository |

**Examples**

```bash
grove pull-all example-app
grove pull-all --all-repos
grove pull-all @frontend
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

---

### grove sync

Rebases a feature branch onto its base branch, keeping it up to date.

**Usage**

```bash
grove sync <repo> [branch] [base]
```

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

---

### grove diff

Shows diff stats between a worktree and its base branch.

**Usage**

```bash
grove diff <repo> [branch] [base]
```

**Examples**

```bash
grove diff example-app feature/login
grove diff example-app feature/login origin/main
```

---

### grove summary

Gives a compact overview of how a worktree differs from its base branch.

**Usage**

```bash
grove summary [<repo> [branch] [base]]
grove summary --json <repo> <branch>
```

Includes: ahead/behind counts, uncommitted changes, recent commits, diffstat.

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
grove log <repo> [branch] [-n <count>]
grove log --json <repo> <branch>
```

**Examples**

```bash
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
grove changes <repo> <branch>
grove changes --json <repo> <branch>
```

**Examples**

```bash
grove changes example-app feature/login
grove changes --json example-app feature/login
```

**JSON output**

Array of file change objects:

```json
[
  {"status": "M", "path": "app/Http/Controllers/LoginController.php"},
  {"status": "A", "path": "tests/Feature/LoginTest.php"},
  {"status": "?", "path": "notes.txt"}
]
```

Status codes: `M` = modified, `A` = added, `D` = deleted, `R` = renamed, `C` = copied, `U` = unmerged, `?` = untracked.

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

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Actually delete merged branches (dry run without this flag) |
| `--all-repos` | Operate on all repositories |

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
2. Identifies local branches merged into `origin/staging`
3. Deletes merged branches (with `-f`)

**Safety**

- Never deletes `staging`, `main`, or `master`
- Only deletes local branches, not remote
- Branches checked out in a worktree cannot be deleted until the worktree is removed

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

Summary: 2 repos, 4 worktrees, 1 dirty, 0 stale
```

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
grove info <repo> [branch]
grove info --json <repo> <branch>
```

**Examples**

```bash
grove info example-app feature/login

# Interactive selection with fzf
grove info example-app

# JSON output
grove info --json example-app feature/login
```

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

Comprehensive health check on a repository identifying issues across all worktrees.

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

---

### grove clean

Removes `node_modules/` and `vendor/` from worktrees inactive for 30+ days to free disk space.

**Usage**

```bash
grove clean <repo>
grove clean -f <repo>
```

**Flags**

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Skip confirmation prompt |

**Examples**

```bash
grove clean example-app
grove clean -f example-app
```

**Notes**

- Only affects worktrees not accessed in the last 30 days
- Worktrees remain functional — run `composer install` / `npm install` when you return to them

---

## Laravel Commands

### grove fresh

Resets a Laravel application to a clean state. Drops all tables and rebuilds.

**Usage**

```bash
grove fresh <repo> [branch]
```

**Examples**

```bash
# Interactive selection with fzf
grove fresh example-app

# Explicit branch
grove fresh example-app feature/login
```

**What it does**

1. Runs `php artisan migrate:fresh --seed`
2. Runs `npm ci`
3. Runs `npm run build`

> **Caution:** This drops all tables. Use with care on worktrees with data you want to keep.

---

### grove migrate

Runs Laravel migrations for a worktree.

**Usage**

```bash
grove migrate <repo> [branch]
```

**Examples**

```bash
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
grove tinker <repo> [branch]
```

**Examples**

```bash
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
```

> **Note:** Warns about potentially destructive commands (e.g., `migrate:fresh`, `db:drop`).

---

### Parallel concurrency

Configure maximum concurrent operations via `GROVE_MAX_PARALLEL` (default: `4`):

```bash
# In ~/.groverc
GROVE_MAX_PARALLEL=8
```

---

## Service Management

Service management is optional and only active when apps are registered. All commands are idempotent — they exit silently if no apps are configured.

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

Exits silently if the app is not registered (safe for use in hooks).

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

Tails log files for an app's services.

**Usage**

```bash
grove services logs <app> [service]
```

**Examples**

```bash
grove services logs myapp          # Tail Horizon logs
grove services logs myapp reverb   # Tail Reverb logs
```

---

### grove services doctor

Checks that all required dependencies for service management are available.

**Usage**

```bash
grove services doctor
```

Checks for: `supervisorctl`, `redis-cli`, `launchctl`, and Homebrew.

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

The wizard prompts for:
1. `HERD_ROOT` directory (default: `~/Herd`)
2. Default base branch (e.g., `origin/staging` or `origin/main`)
3. Database connection settings
4. Creates `~/.grove/hooks/` and `~/.grove/templates/` directories
5. Writes `~/.groverc`
6. Runs `grove doctor`

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

**Output (upgrade)**

```text
→ Checking for updates...

⚠ Update available

Upgrade now? [Y/n]: y

→ Downloading...
→ Verifying checksum...
→ Installing...
→ Rebuilding from source...

✔ Upgrade complete

Restart your terminal for changes to take effect.
```

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
grove share-deps           # Show status
grove share-deps enable    # Enable sharing (from within a worktree)
grove share-deps disable   # Disable and restore local copies
grove share-deps clean     # Remove unused shared caches
```

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
| `-i`, `--interactive` | Interactive worktree creation wizard |
| `--dry-run` | Preview worktree creation without executing |
| `--json` | Output in JSON format |
| `--pretty` | Colourised, formatted JSON output (requires `jq`) |
| `-t`, `--template=<name>` | Use a template when creating a worktree |
| `--delete-branch` | Delete branch when removing worktree |
| `--drop-db` | Drop database after backup (with `rm`) |
| `--no-backup` | Skip database backup (with `rm`) |
| `--all-repos` | Apply operation to all repositories |
| `--check` | Check for updates (with `--version`) |
| `-v`, `--version` | Show version |
| `-h`, `--help` | Show help |

**Flag usage by command**

| Command | Supported flags |
|---------|----------------|
| `add` | `-i`, `--dry-run`, `--json`, `-t`/`--template`, `-f` |
| `rm` | `-f`, `--delete-branch`, `--drop-db`, `--no-backup` |
| `ls` | `--json`, `--pretty` |
| `status` | `--json`, `--pretty` |
| `summary` | `--json`, `--pretty` |
| `log` | `--json`, `-n <count>` |
| `changes` | `--json` |
| `branches` | `--json` |
| `recent` | `--json` |
| `info` | `--json` |
| `health` | `--json` |
| `repos` | `--json` |
| `config` | `--json` |
| `services apps` | `--json` |
| `prune` | `-f`, `--all-repos` |
| `pull-all` | `--all-repos` |
| `build-all` | `--all-repos` |
| `exec-all` | `--all-repos` |
| `clean` | `-f` |
| `--version` | `--check` |
| All commands | `-q` |

---

## JSON Output Reference

All commands that accept `--json` output valid JSON that can be piped to `jq` or `python3`:

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
| `grove log <repo> <branch> --json` | Object | `{commits: [{sha, message, author, date}]}` |
| `grove changes <repo> <branch> --json` | Array | `[{status, path}]` |
| `grove summary <repo> <branch> --json` | Object | `{repo, branch, path, base, ahead, behind, uncommitted, diff, ahead_commits, behind_commits}` |
| `grove config --json` | Object | `{success, data: {default_base_branch, protected_branches, config_dir, hooks_dir, repos_dir, hooks_enabled, database, herd_enabled, url_subdomain}}` |
| `grove info <repo> <branch> --json` | Object | `{repo, branch, path, url, bare_repo, database, git, uncommitted, disk, framework, timestamps, health}` |
| `grove add <repo> <branch> --json` | Object | `{path, url, branch, database}` |
| `grove services apps --json` | Array | `[{name, system_name, services, supervisor_process, domain}]` |

---

## Branch Shortcuts

If you have aliases configured, they work as shorthand with navigation commands:

```bash
grove code login          # uses the 'login' alias
cd "$(grove switch login)"
grove open api
```

See [grove alias](#grove-alias) for creating and managing aliases.

**Numeric shortcuts** (`@1`, `@2`, `@3`)

The `@N` shorthand lets you jump to a recently accessed worktree by number:

```bash
grove @1    # Navigate to most recently accessed worktree
grove @2    # Navigate to second most recent
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HERD_ROOT` | `$HOME/Herd` | Directory containing your sites |
| `GROVE_BASE_DEFAULT` | `origin/staging` | Default branch for new worktrees |
| `GROVE_EDITOR` | `cursor` | Editor for `grove code` command |
| `GROVE_CONFIG` | `~/.groverc` | Path to config file |
| `GROVE_DB_HOST` | `127.0.0.1` | MySQL host for database operations |
| `GROVE_DB_USER` | `root` | MySQL user for database operations |
| `GROVE_DB_PASSWORD` | (empty) | MySQL password for database operations |
| `GROVE_DB_CREATE` | `true` | Auto-create database on `grove add` |
| `GROVE_DB_BACKUP` | `true` | Backup database on `grove rm` |
| `GROVE_DB_BACKUP_DIR` | `~/Code/Project Support/Worktree/Database/Backup` | Backup directory |
| `GROVE_PROTECTED_BRANCHES` | `staging main master` | Space-separated list of protected branches |
| `GROVE_HOOKS_DIR` | `~/.grove/hooks` | Directory for hook scripts |
| `GROVE_URL_SUBDOMAIN` | (empty) | Optional subdomain prefix (e.g., `api` → `api.feature.test`) |
| `GROVE_MAX_PARALLEL` | `4` | Maximum concurrent parallel operations |
| `BRANCH_PATTERN` | (empty) | Regex pattern for branch name validation |

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
