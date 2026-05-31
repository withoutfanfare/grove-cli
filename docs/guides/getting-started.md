# grove Detailed Setup Guide

A slightly longer, slightly more comforting guide for installing and getting started with `grove` (v4.1.0). It spells out every step — prerequisites, both install routes, the setup wizard, your first worktree, the everyday commands, configuration, hooks, uninstalling, and a troubleshooting section keyed to real failure modes. It is aimed at someone installing `grove` for the first time who wants the full picture before they start.

A couple of terms used throughout:

- **Worktree** — a checked-out working copy of a branch in its own directory. `grove` lets one repository have many worktrees side by side, so you can work on several branches at once without stashing or switching.
- **Bare repo** — a git-only store with no working files. `grove` keeps one bare repo per project and creates worktrees from it, so all your branches share a single source of truth.
- **Slug** — a filesystem-safe version of a branch name. `feature/login-form` becomes `feature-login-form` for use in directory and database names.
- **Herd** — [Laravel Herd](https://herd.laravel.com), a macOS/Windows app that serves local sites over HTTPS at `https://<site>.test`. `grove` integrates with it so each worktree gets its own URL, but Herd is optional.

## Contents

- [Who this is for](#who-this-is-for)
- [Platform support](#platform-support)
- [Dependencies](#dependencies)
- [Installation (recommended)](#installation-recommended)
  - [Installer options](#installer-options)
  - [What gets installed](#what-gets-installed)
  - [Manual installation](#manual-installation-if-you-like-to-steer-the-ship)
- [First-time setup wizard](#first-time-setup-wizard)
- [Your first worktree (step-by-step)](#your-first-worktree-step-by-step)
- [Where files live on disk](#where-files-live-on-disk)
- [Everyday commands](#everyday-commands)
- [Configuration basics](#configuration-basics)
- [Hooks (optional, but powerful)](#hooks-optional-but-powerful)
- [Uninstall](#uninstall)
- [Quick troubleshooting](#quick-troubleshooting)

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

`install.sh` refuses to run on anything other than macOS today.

## Dependencies

**Required:**

- `zsh` (the tool is written in zsh)
- `git`

**Optional but useful:**

- `fzf` for pickers (`grove add -i`, `grove switch`, `grove rm` with no branch)
- `jq` for pretty JSON output (`--pretty`)
- `mysql` for automatic database creation on `grove add` and backups on `grove rm`

**Framework integration (for Laravel hooks):**

- `herd` — [Laravel Herd](https://herd.laravel.com) serves each worktree over HTTPS. It is what powers the auto-generated `https://<site>.test` URLs that `grove open`, `grove switch` and `grove info` use. `grove` works without it, but the local URLs will not resolve.
- `composer` — PHP dependency management, used by the example Laravel hooks.
- `npm` (Node.js) — JavaScript package management and `grove build-all`.

The installer checks for all of these and reports which are present, but only `zsh` and `git` are hard requirements; everything else is optional.

On macOS, you can grab the optional tools with Homebrew:

```bash
brew install fzf jq mysql
```

Laravel Herd is installed separately from [herd.laravel.com](https://herd.laravel.com).

## Installation (recommended)

```bash
# Clone the repo
git clone https://github.com/withoutfanfare/grove-cli.git ~/Projects/grove-cli

# Run the installer
cd ~/Projects/grove-cli
./install.sh
```

The installer is safe to re-run and keeps your config and data. By default it:

1. Checks dependencies (and prints what is missing).
2. Builds the `grove` executable from `lib/` if needed, then symlinks it into the install directory.
3. Installs the zsh completions.
4. Creates `~/.groverc` *only if it does not already exist*.
5. Creates the `~/.grove/` directories and the example hooks.

If the install directory is not on your `PATH`, the installer prints a warning and an `export PATH=...` line to add to your `~/.zshrc`. Likewise, if completions go to the fallback location it prints the `fpath`/`compinit` lines you need.

Open a new terminal so the `PATH` and completion updates are picked up, then check:

```bash
grove --version
grove doctor
```

### Installer options

- `./install.sh` — interactive (default)
- `./install.sh --merge` — add new example hooks without overwriting yours
- `./install.sh --overwrite` — replace hooks (backs up first)
- `./install.sh --skip-hooks` — do not touch hooks
- `./install.sh --quiet` — minimal output

The `--merge`/`--overwrite`/`--skip-hooks` options control the example hooks copied into `~/.grove/hooks/`.

You can also override two locations with environment variables (handy if you cannot write to `/usr/local/bin`):

- `GROVE_INSTALL_DIR` — where the `grove` symlink is created (default `/usr/local/bin`)
- `GROVE_COMPLETIONS_DIR` — where `_grove` completions are linked (auto-detected by default)

```bash
GROVE_INSTALL_DIR="$HOME/.local/bin" ./install.sh
```

### What gets installed

- `<install-dir>/grove` — main executable (a symlink; default `<install-dir>` is `/usr/local/bin`)
- `<completions-dir>/_grove` — zsh completions; the completions directory is auto-detected (see below)
- `~/.groverc` — your config file, created **only if it does not already exist**, with sensible defaults. Run `grove setup` for the interactive way to (re)generate it.
- `~/.grove/hooks/` — lifecycle hooks directory, with all nine `.d` subdirectories created (`pre-add.d`, `post-add.d`, `pre-rm.d`, `post-rm.d`, `post-pull.d`, `post-sync.d`, `post-switch.d`, `pre-move.d`, `post-move.d`) plus any example hooks
- `~/.grove/templates/` — worktree templates (empty by default)
- `~/.grove/aliases` — branch/repo aliases (`grove alias`)
- `~/.grove/groups` — repository groups (`grove group`)
- `~/.grove/services/` — optional Laravel service config (`grove services`)

The completions directory is chosen automatically by `install.sh`:

| Machine | Completions directory |
|---------|----------------------|
| Apple Silicon (Homebrew) | `/opt/homebrew/share/zsh/site-functions` |
| Intel Mac (Homebrew) | `/usr/local/share/zsh/site-functions` |
| Neither present (fallback) | `~/.zsh/completions` |

If the fallback is used, add this to your `~/.zshrc` so completions are found:

```bash
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

Because the executable and completions are symlinks into the cloned repo, pulling new commits updates the tool immediately.

### Manual installation (if you like to steer the ship)

```bash
# Clone the repo
git clone https://github.com/withoutfanfare/grove-cli.git ~/Projects/grove-cli

# Symlink the script
sudo ln -sf ~/Projects/grove-cli/grove /usr/local/bin/grove
```

Then symlink the completions to the directory that matches your machine (the recommended installer auto-detects this for you):

```bash
# Apple Silicon Mac (Homebrew)
ln -sf ~/Projects/grove-cli/_grove /opt/homebrew/share/zsh/site-functions/_grove

# Intel Mac (Homebrew)
ln -sf ~/Projects/grove-cli/_grove /usr/local/share/zsh/site-functions/_grove

# Fallback (neither Homebrew path exists)
mkdir -p ~/.zsh/completions
ln -sf ~/Projects/grove-cli/_grove ~/.zsh/completions/_grove
# ...then add to ~/.zshrc:
#   fpath=(~/.zsh/completions $fpath)
#   autoload -Uz compinit && compinit
```

Finally create your config:

```bash
# Create config
cp ~/Projects/grove-cli/.groverc.example ~/.groverc
```

You do not need to create the hook directories by hand: running `grove setup` (or re-running `./install.sh`) scaffolds them, and `grove` creates any missing hook subdirectory on demand. The full set is `pre-add.d`, `post-add.d`, `pre-rm.d`, `post-rm.d`, `post-pull.d`, `post-sync.d`, `post-switch.d`, `pre-move.d` and `post-move.d` under `~/.grove/hooks/`.

> **Note:** Never edit the generated `grove` file directly. It is built from the modular sources in `lib/` via `./build.sh`. If you change behaviour, edit `lib/` and rebuild.

## First-time setup wizard

```bash
grove setup
```

The wizard walks through seven numbered sections, in this order. If `~/.groverc` already exists it first asks whether to reconfigure (and backs up the old file before writing).

1. **Worktree directory (`HERD_ROOT`)** — where bare repos and worktrees live (default `~/Herd`). Offers to create the directory if it does not exist.
2. **Default base branch (`DEFAULT_BASE`)** — the branch new worktrees are created from and `grove sync` rebases onto (e.g. `origin/staging` or `origin/main`).
3. **Default editor (`DEFAULT_EDITOR`)** — the editor `grove code`/`grove switch` opens. The wizard auto-detects which of `cursor`, `code`, `phpstorm`, `subl` and `vim` are on your `PATH`.
4. **Database settings** — `DB_HOST`, `DB_USER`, `DB_PASSWORD` and whether to auto-create databases. The wizard runs a live MySQL connection test and reports whether it succeeded (a failure is just a warning — you can fix credentials later). Leave the fields empty to skip database features.
5. **Branch naming pattern (`BRANCH_PATTERN`, optional)** — an optional regex new branch names must match. Leave empty to allow any name.
6. **Create directories** — creates `~/.grove`, `~/.grove/hooks`, `~/.grove/templates`, `~/.grove/hooks/post-add.d` and `~/.grove/hooks/post-rm.d`.
7. **Write configuration** — writes `~/.groverc` (with restrictive `0600` permissions) and prints a summary.

The wizard then suggests next steps — clone a repo, add a worktree, and run `grove doctor`. It does **not** run `grove doctor` for you, so run it yourself once setup finishes:

```bash
grove doctor
```

## Your first worktree (step-by-step)

We will use `example-app` as the repo name throughout. Substitute your own URL and repo name.

### Step 1: Create a bare repo

A bare repo is a git-only store (no working files), which lets `grove` create multiple worktrees from one source of truth.

**Recommended (let `grove` do it):**

```bash
grove clone <git-url> <repo-name> [branch]
# Example:
grove clone git@github.com:your-org/example-app.git example-app staging
```

Use `main` instead of `staging` if that is your default branch.

That `<repo-name>` is the handle you will type in most commands (like `grove add example-app ...`). `grove clone` creates the bare repo at `$HERD_ROOT/<repo-name>.git/` (default `$HERD_ROOT` is `~/Herd`) and creates an initial worktree for the branch you asked for.

**Manual option (if you want to create the bare repo yourself):**

```bash
git clone --bare <repo-url> <target-dir>

# Example (inside your Herd root, usually `~/Herd`):
cd ~/Herd
git clone --bare git@github.com:your-org/example-app.git example-app.git
```

> **Important:** The bare repo directory **must** be named `<repo-name>.git` and live directly under `HERD_ROOT` for `grove` to find it. With the example above the repo name is `example-app` (the `.git` suffix and `HERD_ROOT` prefix are how `grove` derives it).

### Step 2: Create a worktree

If you used `grove clone ... staging` in Step 1, you already have the staging worktree — jump straight in:

```bash
cd "$(grove switch example-app staging)"
```

If you did a manual `git clone --bare`, create the staging worktree first:

```bash
grove add example-app staging
cd "$(grove switch example-app staging)"
```

If your default branch is `main`, use that instead of `staging`.

> **What `grove switch` actually does:** it prints the worktree path (which is why it is wrapped in `cd "$(...)"` — `grove` runs as a child process and cannot change your shell's directory itself), **and** it opens the worktree in your configured editor and in your browser, and runs any `post-switch` hooks. If you only want to change directory without launching anything, use `grove cd` instead:
>
> ```bash
> cd "$(grove cd example-app staging)"
> ```

## Where files live on disk

For the example above, with the default `HERD_ROOT=~/Herd`:

```bash
~/Herd/
├── example-app.git/                      # the bare repo
└── example-app-worktrees/                # one folder per worktree
    └── staging/                          # the worktree for the `staging` branch
```

- Bare repo: `$HERD_ROOT/<repo>.git/`
- Worktrees: `$HERD_ROOT/<repo>-worktrees/<site-name>/`, where `<site-name>` is the branch slug (so `feature/login-form` lands in `…/example-app-worktrees/feature-login-form/`).
- The matching local URL (when Herd is serving) is `https://<site-name>.test`.

## Everyday commands

```bash
grove add <repo> <branch>           # Create a worktree
grove switch <repo> [branch]        # Jump to a worktree (opens editor + browser; fzf if branch omitted)
grove code <repo> [branch]          # Open in editor
grove open <repo> [branch]          # Open in browser
grove pull-all <repo>               # Pull all worktrees in parallel
grove sync <repo> <branch>          # Rebase onto base branch
grove rm <repo> <branch>            # Remove worktree
```

> **Run from inside a worktree and `grove` auto-detects the repo and branch** for most commands — `pull`, `sync`, `diff`, `summary`, `log`, `changes`, `code`, `open`, `cd`, `info`, `clean`, `share-deps`, `fresh`, `migrate` and `tinker` — so you can omit the arguments (e.g. just `grove sync`). Auto-detection requires the worktree to be under `HERD_ROOT`. `switch`, `rm`, `add`, `status` and `pull-all` always need an explicit repo (and usually a branch).

## Configuration basics

Your config lives at `~/.groverc`. It is parsed as simple `KEY=value` pairs (never sourced as a shell script), so quoting is optional — `grove` accepts both `HERD_ROOT=~/Herd` and `HERD_ROOT="$HOME/Herd"`. The setup wizard and installer write quoted values using `$HOME`; either style works.

Common settings:

```bash
HERD_ROOT="$HOME/Herd"
DEFAULT_BASE=origin/staging
DEFAULT_EDITOR=cursor
DB_HOST=127.0.0.1
DB_USER=root
DB_PASSWORD=
DB_CREATE=true
DB_BACKUP=true
```

See [`configuration.md`](../reference/configuration.md) for the full list of keys, their defaults, and the matching environment-variable overrides.

## Hooks (optional, but powerful)

Hooks let you run scripts when worktrees are created, removed, switched, pulled, synced or moved.

Common hooks:

- `post-add` — install dependencies, copy `.env`, run migrations
- `pre-rm` — back up the database, or stop you deleting with uncommitted changes (a non-zero exit aborts the removal)
- `post-switch` — update `.env` values when switching worktrees
- `pre-move` / `post-move` — run before and after renaming or moving a worktree

Hooks live in `~/.grove/hooks/` and are executed in this order:

1. Single hook file: `~/.grove/hooks/<hook>`
2. Global hooks: `~/.grove/hooks/<hook>.d/*.sh`
3. Repo-specific hooks: `~/.grove/hooks/<hook>.d/<repo>/*.sh`

For example, a `post-add` hook that only runs for the `example-app` repo lives at:

```text
~/.grove/hooks/post-add.d/example-app/install-deps.sh
```

Repo-specific hooks let you customise behaviour for individual projects without affecting others.

> **Security:** hook scripts must be **executable** (`chmod +x`) and **owned by you**. `grove` skips any hook that is not owner-executable, that is not owned by the current user, or that is group- or world-writable.

See `examples/hooks/README.md` for detailed documentation and example hooks.

## Uninstall

```bash
cd ~/Projects/grove-cli
./uninstall.sh
```

This removes the `grove` symlink and the `_grove` completions, and also sweeps the common alternative locations (`~/bin`, `~/.local/bin`, and both the Homebrew and Intel completion directories). If you previously ran the `wt` compatibility shim, its symlink is removed too. The installer respects `GROVE_INSTALL_DIR`/`GROVE_COMPLETIONS_DIR`, so set the same overrides you used at install time.

It **keeps** your config and data — `~/.groverc`, the `~/.grove/` directory, and your bare repos and worktrees under `HERD_ROOT`. To remove everything, the script prints these for you to run manually:

```bash
rm ~/.groverc
rm -rf ~/.grove
```

## Quick troubleshooting

- **'Bare repo not found'** → Run `grove clone` first, or confirm the bare repo is named `<repo>.git` directly under `HERD_ROOT`.
- **'Worktree already exists'** → Use `grove cd`/`grove switch`, or remove it with `grove rm`.
- **Missing `fzf` picker** → `brew install fzf` and reopen your terminal.
- **Database not created** → Check MySQL is running, that your `DB_*` settings are correct, or set `DB_CREATE=false`.
- **`grove: command not found`** → The install directory is not on your `PATH`. Add `export PATH="/usr/local/bin:$PATH"` (or your `GROVE_INSTALL_DIR`) to `~/.zshrc` and open a new terminal.
- **Completions not working** → If completions went to the `~/.zsh/completions` fallback, add the `fpath`/`compinit` lines (see [What gets installed](#what-gets-installed)) and reopen your terminal.
- **`https://<site>.test` won't open** → Make sure Laravel Herd is installed and running; the local URLs depend on it.

If you get stuck, run:

```bash
grove doctor
```

It will point you at missing dependencies or misconfigurations.
