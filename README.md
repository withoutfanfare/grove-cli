# grove - Git Worktree Manager

A command-line tool for managing git worktrees with optional Laravel Herd integration. Work on multiple branches at once without stash gymnastics.

**Framework-agnostic by design.** The core `grove` tool handles git worktree operations only. Framework setup (Laravel, Node.js, etc.) happens in lifecycle hooks that you can use, tweak, or ignore.

## At a glance

- Keep multiple branches open at the same time, each in its own folder
- Create and clean worktrees with one command
- Optional Laravel Herd URLs, database setup, and artisan shortcuts
- Safe by default: health checks, branch protection, mismatch warnings
- Batch commands for pulling, building, and syncing across worktrees
- Optional service management for Horizon, Reverb, and schedulers

## Installation

```bash
# 1) Clone the repo
git clone https://github.com/dannyharding10/grove-cli.git ~/Projects/grove-cli

# 2) Run the installer
cd ~/Projects/grove-cli
./install.sh

# 3) Open a new terminal, then sanity-check
grove --version
grove doctor
```

For detailed install options, manual install, or platform notes, see [docs/guides/getting-started.md](docs/guides/getting-started.md).

## First-time onboarding

1. **Run the setup wizard**
   ```bash
   grove setup
   ```
   This asks a few friendly questions and creates your `~/.groverc` config.

2. **Clone your project as a bare repo**

   ```bash
   grove clone git@github.com:your-org/example-app.git example-app staging
   ```

   - `example-app` is the short name you'll type in most commands
   - `staging` (or `main`) is the default branch to create a worktree for
   - This creates a bare repo at `~/Herd/example-app.git/` and a worktree for the branch

   **Manual option** (if you prefer):
   ```bash
   cd ~/Herd
   git clone --bare git@github.com:your-org/example-app.git example-app.git
   grove add example-app staging
   ```

3. **Jump in**
   ```bash
   cd "$(grove switch example-app staging)"
   ```

4. **Daily flow**
   ```bash
   grove add example-app feature/my-branch
   cd "$(grove switch example-app feature/my-branch)"
   ```

**Golden rule:** one worktree = one branch. Do not run `git checkout` inside a worktree. Switch worktrees instead.

---

## What are Git Worktrees?

Normally, you have one working directory per repository. If you're working on a feature and need to fix a bug on another branch, you have to stash your changes, switch branches, fix the bug, switch back, and unstash.

**With worktrees**, you can have multiple branches checked out at the same time, each in its own directory:

```text
~/Herd/
├── example-app.git/                    # Bare repo (stores all git data)
└── example-app-worktrees/              # Worktrees organised by repo
    ├── example-app/                    # staging branch
    ├── login/                          # feature/login branch
    └── bugfix-123/                     # bugfix/123 branch
```

Each worktree is a fully functional working directory with its own `.env`, `vendor/`, `node_modules/`, etc. You can have them all running simultaneously with different URLs in Laravel Herd.

### The Golden Rule: One Branch Per Worktree

**Each worktree is the permanent home for ONE specific branch.** The directory name tells you which branch belongs there.

| Do | Don't |
|----|-------|
| `grove switch example-app feature/login` | `git checkout feature/login` inside a worktree |
| `grove add example-app feature/new-thing` | `git switch main` inside a worktree |
| `git commit`, `git push`, `git pull` | `git checkout` or `git switch` to a different branch |
| `git rebase`, `git merge`, `git stash` | Switch branches in SourceTree/VS Code Git panel |

Think of each worktree as a **dedicated workspace** for one branch:

| Directory | Branch | Purpose |
|-----------|--------|---------|
| `example-app-worktrees/example-app` | `staging` | Integration testing, merges |
| `example-app-worktrees/login` | `feature/login` | Login feature development |
| `example-app-worktrees/bugfix-cart` | `bugfix/cart` | Cart bug fix |

You don't "switch branches" -- you **switch worktrees**.

If you accidentally ran `git checkout` inside a worktree, `grove status` will warn you. Fix it:
```bash
cd ~/Herd/example-app-worktrees/login
git checkout feature/login              # Put the right branch back
```

---

## Quick Reference

All grove commands at a glance. For detailed usage, flags, and JSON schemas, see [docs/reference/commands.md](docs/reference/commands.md).

```bash
# Example repo name used throughout: `example-app`

# Setup + sanity checks
grove clone git@github.com:your-org/example-app.git example-app
grove setup
grove doctor
grove config
grove repos

# Create / rename / remove worktrees
grove add example-app staging
grove add example-app feature/login
grove add example-app feature/api origin/staging
grove add -i                                          # interactive wizard
grove add example-app feature/api --template=backend  # use template
grove move example-app feature/login login
grove rm example-app feature/login
grove rm --drop-db --delete-branch example-app feature/login

# Navigate (auto-detects repo/branch if inside a worktree)
cd "$(grove cd example-app feature/login)"
grove code example-app feature/login    # open in editor
grove open example-app feature/login    # open URL in browser
grove switch example-app feature/login  # cd + code + open in one
grove exec example-app feature/login php artisan migrate

# Git ops + visibility
grove ls example-app
grove status example-app
grove dashboard
grove info example-app feature/login
grove pull example-app feature/login
grove pull-all example-app
grove sync example-app feature/login
grove diff example-app feature/login
grove summary example-app feature/login
grove log example-app feature/login -n 10
grove changes example-app feature/login
grove branches example-app
grove prune example-app
grove recent 10
grove health example-app

# Parallel commands
grove build-all example-app
grove exec-all example-app npm test

# Laravel shortcuts
grove migrate example-app feature/login
grove tinker example-app feature/login
grove fresh example-app feature/login

# Services (optional -- for Horizon/Reverb/scheduler management)
grove services                          # show help or status
grove services add myapp                # register an app
grove services status                   # check all services
grove services start myapp              # start services
grove services stop myapp               # stop services
grove services restart all              # restart everything
grove services apps                     # list registered apps
grove services horizon myapp            # open Horizon dashboard
grove services logs myapp               # tail Horizon logs
grove services doctor                   # check dependencies

# Shortcuts
grove @1                                # most recent worktree
grove code example-app feat-auth        # fuzzy match: feature/auth-improvements

# Utilities
grove clean example-app
grove alias add login example-app/feature/login
grove group add client-work example-app
grove templates
grove repair example-app
grove cleanup-herd
grove unlock example-app
grove share-deps status
grove upgrade
```

---

## Common Workday Scenarios

### Starting your day

```bash
# Check what you were working on
grove status example-app

# Pull all worktrees to get overnight changes
grove pull-all example-app

# Jump straight into your current feature
cd "$(grove switch example-app)"
```

### Starting a new feature

```bash
# Create worktree (auto-creates branch from staging, runs post-add hooks)
grove add example-app feature/user-avatars

# Opens editor + browser, prints path for cd
cd "$(grove switch example-app feature/user-avatars)"
```

### Reviewing a colleague's PR

```bash
# Create worktree for their branch
grove add example-app feature/colleague-work

# Open it up
cd "$(grove switch example-app feature/colleague-work)"

# Reset to clean state if needed
grove fresh example-app feature/colleague-work

# When done reviewing, clean up
grove rm --drop-db example-app feature/colleague-work
```

### Quick hotfix on staging

```bash
# Make sure staging is up to date
grove pull example-app staging

# Open staging
cd "$(grove switch example-app staging)"

# Make your fix, commit, then switch back
cd "$(grove switch example-app feature/current-work)"
```

### Keeping your feature branch up to date

```bash
# Sync your branch with latest staging (fetches + rebases)
grove sync example-app feature/user-avatars

# If there are conflicts, resolve them then:
git rebase --continue

# After syncing, you may need to force push
git push --force-with-lease
```

### Switching between features

```bash
# Quick switch with fzf picker
cd "$(grove switch example-app)"

# Or explicit branch
cd "$(grove switch example-app feature/other-feature)"
```

### End of day cleanup

```bash
# See what branches you have
grove ls example-app

# Remove branches you're done with (keeps backup)
grove rm example-app feature/completed-work

# Or drop the database too
grove rm --drop-db example-app feature/completed-work

# Clean up merged branches
grove prune -f example-app
```

### After a PR is merged

```bash
# Remove the worktree and delete the local branch
grove rm --delete-branch --drop-db example-app feature/merged-feature

# Update staging
grove pull example-app staging

# Sync other feature branches with new staging
grove sync example-app feature/other-feature
```

---

## Configuration

Create `~/.groverc` (or run `grove setup`):

```bash
HERD_ROOT=$HOME/Herd                    # Where bare repos and worktrees live
DEFAULT_BASE=origin/staging             # Base branch for new worktrees
DEFAULT_EDITOR=cursor                   # Editor command (cursor, code, phpstorm)
DB_USER=root                            # MySQL user
DB_PASSWORD=                            # MySQL password
DB_BACKUP_DIR=$HOME/Code/Backups        # Where database backups go
PROTECTED_BRANCHES="staging main master"
```

For full configuration options, see [docs/reference/configuration.md](docs/reference/configuration.md).

### Hooks

Hooks run custom scripts at various points in the worktree lifecycle. Create executable scripts in `~/.grove/hooks/`:

| Hook | When it runs | Can abort? |
|------|--------------|------------|
| `pre-add` | Before worktree creation | Yes |
| `post-add` | After worktree creation | No |
| `pre-rm` | Before worktree removal | Yes |
| `post-rm` | After worktree removal | No |
| `post-pull` | After `grove pull` succeeds | No |
| `post-sync` | After `grove sync` succeeds | No |
| `post-switch` | After `grove switch` succeeds | No |
| `pre-move` | Before `grove move` | Yes |
| `post-move` | After `grove move` succeeds | No |

**Hook variables available:** `GROVE_REPO`, `GROVE_BRANCH`, `GROVE_PATH`, `GROVE_URL`, `GROVE_DB_NAME`

**Multiple hooks:** Create a `.d` directory (e.g., `~/.grove/hooks/post-add.d/`) with numbered scripts. Repo-specific hooks go in subdirectories matching the repo name.

The installer includes example Laravel hooks. Run `grove doctor` to verify hooks are set up correctly.

### Service Management (Optional)

Grove includes optional service management for Laravel apps using Supervisor, Horizon, Reverb, or scheduled tasks. Entirely opt-in -- invisible if no apps are registered.

```bash
# Register an app
grove services add myapp

# Check everything is working
grove services doctor

# Daily use
grove services status               # show all service status
grove services start myapp          # start services
grove services stop myapp           # stop services
grove services restart all          # restart everything
grove services horizon myapp        # open Horizon dashboard
grove services logs myapp           # tail Horizon logs
grove services logs myapp reverb    # tail Reverb logs
```

When you run `grove switch`, services automatically restart for the switched app. No extra configuration needed.

For full setup, config format, and troubleshooting, see [docs/guides/services.md](docs/guides/services.md).

---

## Flags

| Flag | Description |
|------|-------------|
| `-q, --quiet` | Suppress informational output |
| `-f, --force` | Skip confirmations / force protected branch removal |
| `-i, --interactive` | Launch interactive worktree creation wizard |
| `--json` | Output in JSON format (for scripting and the Tauri app) |
| `--pretty` | Pretty-print JSON output with colours |
| `--dry-run` | Preview actions without executing (`grove add`) |
| `--delete-branch` | Delete branch when removing worktree |
| `--drop-db` | Drop database when removing worktree |
| `--no-backup` | Skip database backup when removing worktree |
| `--template=<name>` | Apply template when creating worktree |
| `--all-repos` | Apply operation across all repositories |
| `-v, --version` | Show version (add `--check` to check for updates) |

---

## Troubleshooting

### "Bare repo not found"

Clone the repo first:
```bash
grove clone git@github.com:org/repo.git
```

### "Worktree already exists"

Either use the existing worktree (`grove cd example-app branch`) or remove it first (`grove rm example-app branch`).

### Branch not found

Fetch latest branches:
```bash
git --git-dir="$HOME/Herd/example-app.git" fetch --all
```

### Worktree has uncommitted changes

Commit or stash before removing/syncing:
```bash
cd "$(grove cd example-app feature/work)"
git stash
```

### Rebase conflicts during sync

1. Navigate to the worktree: `cd "$(grove cd example-app feature/branch)"`
2. Resolve conflicts in your editor
3. `git add <resolved-files>`
4. `git rebase --continue` (or `git rebase --abort` to cancel)

### Can't remove staging/main/master worktree

Protected branches require the force flag:
```bash
grove rm -f example-app staging
```

### Database not created

1. Check MySQL is running: `mysql -u root -e "SELECT 1"`
2. Set password in `~/.groverc` if needed: `DB_PASSWORD=your_password`
3. Or disable auto-creation: `DB_CREATE=false`

### fzf picker not working

Install fzf: `brew install fzf`

### SSH authentication issues

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

---

## Further Reading

| Document | What's in it |
|----------|-------------|
| [Command Reference](docs/reference/commands.md) | Every command, flag, and JSON schema in detail |
| [Configuration Reference](docs/reference/configuration.md) | All config options and environment variables |
| [Services Guide](docs/guides/services.md) | Full Horizon/Reverb/Supervisor service management setup |
| [Advanced Guide](docs/guides/advanced.md) | Templates, aliases, groups, multi-repo ops, developer guide |
| [Getting Started](docs/guides/getting-started.md) | Detailed installation and platform notes |
| [Tutorials](docs/guides/tutorials.md) | Step-by-step recipes and onboarding walkthroughs |
| [Release Verification](docs/release-packaging-verification.md) | Tauri app compatibility checklist |

---

## Tips

### Use aliases for common repos

Add to `~/.zshrc`:
```bash
alias gs="grove status example-app"
alias gl="grove ls example-app"
alias gc="grove code example-app"
```

### Quick navigation function

Add to `~/.zshrc`:
```bash
# Usage: gcd example-app feature/login
gcd() {
  cd "$(grove cd "$@")"
}
```

### Database per worktree

Each worktree gets its own database named `<repo>__<branch_slug>`:
- `example-app` + `feature/login` = `example_app__feature_login`

Set `DB_DATABASE` in your `.env.example` and the hooks handle the rest.

---

## Testing

```bash
# Run all tests
./run-tests.sh

# Run specific categories
./run-tests.sh unit
./run-tests.sh integration
./run-tests.sh lint
```

Install BATS: `brew install bats-core`

---

*Built by [Danny Harding](https://github.com/dannyharding10). Contributions welcome.*
