# grove Detailed Setup Guide

A slightly longer, slightly more comforting guide for installing and getting started with `grove`.

## Who this is for

- You want the full install options, not just the happy path.
- You are setting up a new machine or helping a teammate onboard.
- You like to know where files live before you start.

## Platform support

| Platform | Status |
|----------|--------|
| macOS | Fully supported |
| Linux | Planned (see [`roadmap.md`](../development/roadmap.md)) |
| Windows | Planned via WSL (see [`roadmap.md`](../development/roadmap.md)) |

## Dependencies

Required:

- `zsh` (the tool is written in zsh)
- `git`

Optional but useful:

- `fzf` for pickers (`grove add -i`, `grove switch`)
- `jq` for pretty JSON output (`--pretty`)
- `mysql` if you want automatic database creation in hooks

On macOS, you can grab optional tools with Homebrew:

```bash
brew install fzf jq mysql
```

## Installation (recommended)

```bash
# Clone the repo
git clone https://github.com/dannyharding10/grove-cli.git ~/Projects/grove-cli

# Run the installer
cd ~/Projects/grove-cli
./install.sh
```

Open a new terminal so your PATH and completion updates are picked up, then check:

```bash
grove --version
grove doctor
```

### Installer options

- `./install.sh` - interactive (default)
- `./install.sh --merge` - add new example hooks without overwriting yours
- `./install.sh --overwrite` - replace hooks (backs up first)
- `./install.sh --skip-hooks` - do not touch hooks
- `./install.sh --quiet` - minimal output

The installer is safe to re-run and will keep your config and data.

### What gets installed

- `/usr/local/bin/grove` - main executable (symlink)
- `/opt/homebrew/share/zsh/site-functions/_grove` - completions (Apple Silicon path)
- `~/.groverc` - your config file
- `~/.grove/hooks/` - lifecycle hooks directory

Because these are symlinks, updating the repo updates the tool.

## Manual installation (if you like to steer the ship)

```bash
# Clone the repo
git clone https://github.com/dannyharding10/grove-cli.git ~/Projects/grove-cli

# Symlink the script
sudo ln -sf ~/Projects/grove-cli/grove /usr/local/bin/grove

# Symlink completions (Apple Silicon Mac)
ln -sf ~/Projects/grove-cli/_grove /opt/homebrew/share/zsh/site-functions/_grove

# Create config
cp ~/Projects/grove-cli/.groverc.example ~/.groverc

# Create hooks directory
mkdir -p ~/.grove/hooks/post-add.d
```

## First-time setup wizard

```bash
grove setup
```

This will:

1. Ask for your `HERD_ROOT` (default: `~/Herd`)
2. Set your default base branch (e.g., `origin/staging` or `origin/main`)
3. Configure database settings (if you want DB automation)
4. Create `~/.grove/hooks/` and `~/.grove/templates/`
5. Write `~/.groverc`
6. Run `grove doctor`

## Your first worktree (step-by-step)

### Step 1: Create a bare repo

A bare repo is a git-only store (no working files), which lets `grove` create multiple worktrees from one source of truth.

Recommended (let `grove` do it):

```bash
grove clone <git-url> <repo-name> [branch]
# Example:
grove clone git@github.com:your-org/example-app.git example-app staging
```
Use `main` instead of `staging` if that's your default branch.

That `<repo-name>` is the handle you will type in most commands (like `grove add example-app ...`). Tip: if your bare repo folder is `example-app.git`, the repo name is `example-app`.

`grove clone` creates a bare repo at `$HERD_ROOT/<repo-name>.git/` (default `$HERD_ROOT` is `~/Herd`) and creates an initial worktree for the branch you asked for.

Manual option (if you want to create the bare repo yourself):

```bash
git clone --bare <repo-url> <target-dir>

# Example (inside your Herd root, usually `~/Herd`):
cd ~/Herd
git clone --bare git@github.com:your-org/example-app.git example-app.git
```

### Step 2: Create a worktree

If you used `grove clone ... staging` in Step 1, you already have the staging worktree - you can jump in:

```bash
cd "$(grove switch example-app staging)"
```

If you did a manual `git clone --bare`, create the staging worktree now:

```bash
grove add example-app staging
cd "$(grove switch example-app staging)"
```

If your default branch is `main`, just use that instead of `staging`.

## Everyday commands

```bash
grove add <repo> <branch>           # Create a worktree
grove switch <repo> [branch]        # Jump to a worktree (fzf if branch omitted)
grove code <repo> [branch]          # Open in editor
grove open <repo> [branch]          # Open in browser
grove pull-all <repo>               # Pull all worktrees
grove sync <repo> <branch>          # Rebase onto base branch
grove rm <repo> <branch>            # Remove worktree
```

## Configuration basics

Your config lives at `~/.groverc`. Common settings:

```bash
HERD_ROOT=~/Herd
DEFAULT_BASE=origin/staging
DEFAULT_EDITOR=cursor
DB_HOST=127.0.0.1
DB_USER=root
DB_PASSWORD=
DB_CREATE=true
DB_BACKUP=true
```

See [`configuration.md`](../reference/configuration.md) for the full list.

## Hooks (optional, but powerful)

Hooks let you run scripts when worktrees are created or removed.

Common hooks:

- `post-add` - install dependencies, copy `.env`, run migrations
- `pre-rm` - backup database, stop you deleting with uncommitted changes
- `post-switch` - update `.env` values when switching worktrees

Hooks live in `~/.grove/hooks/` and are executed in this order:

1. Single hook file: `~/.grove/hooks/<hook>`
2. Global hooks: `~/.grove/hooks/<hook>.d/*.sh`
3. Repo-specific hooks: `~/.grove/hooks/<hook>.d/<repo>/*.sh`

Repo-specific hooks let you customise behaviour for individual projects without affecting others.

See `examples/hooks/README.md` for detailed documentation and example hooks.

## Uninstall

```bash
cd ~/Projects/grove-cli
./uninstall.sh
```

This removes symlinks but keeps your config (`~/.groverc`), hooks (`~/.grove/`), repos, and worktrees.

## Quick troubleshooting

- **'Bare repo not found'** → Run `grove clone` first.
- **'Worktree already exists'** → Use `grove cd`/`grove switch`, or remove it with `grove rm`.
- **Missing `fzf` picker** → `brew install fzf` and reopen your terminal.
- **Database not created** → Check MySQL is running, or set `DB_CREATE=false`.

If you get stuck, run:

```bash
grove doctor
```

It will point you at missing dependencies or misconfigurations.
