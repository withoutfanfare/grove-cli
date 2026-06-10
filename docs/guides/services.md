# Service Management Guide

> Grove includes optional service management for Laravel apps that use Supervisor, Horizon, Reverb, or scheduled tasks. This is entirely opt-in -- if you don't register any apps, the feature stays invisible.

If you've never heard of Horizon or Supervisor, a quick summary: Laravel Horizon is a dashboard and queue manager that runs as a background process. Supervisor is the system tool that keeps it alive if it crashes. Reverb is Laravel's WebSocket server. Grove can start, stop, and restart all of these for you -- which is especially useful when switching between worktrees.

This guide is for Laravel users who run Supervisor, Horizon, Reverb, or the scheduler and want grove to manage them per worktree. (A *worktree* is a separate working directory checked out from the same git repository; a *bare repo* is a repository with no working tree of its own, which grove keeps under your Herd root.) It covers prerequisites, registering apps, managing and monitoring services, viewing logs, the Horizon dashboard, the `apps.conf` config-file format, integration with `grove switch`, migrating from DevCTL, and troubleshooting.

## Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Registering Apps](#registering-apps)
- [Managing Services](#managing-services)
- [Monitoring](#monitoring)
- [Configuration](#configuration)
- [Integration with `grove switch`](#integration-with-grove-switch)
- [Migrating from DevCTL](#migrating-from-devctl)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before using service management, make sure you have:

- A Laravel app using Horizon, Reverb, or scheduled tasks
- [Supervisor](https://supervisord.org/) installed via Homebrew:
  ```bash
  brew install supervisor
  brew services start supervisor
  ```
- Redis running (Horizon requires it):
  ```bash
  brew services start redis
  ```
- PHP available in your terminal (it will be if you're using Laravel Herd)
- Laravel Herd for local `.test` domain routing

If you're unsure whether your environment is ready, run `grove services doctor` after installing -- it will tell you exactly what's missing.

---

## Quick Start

Three steps to get going:

```bash
# 1. Register your app
grove services add myapp

# 2. Check that dependencies are in order
grove services doctor

# 3. View the status of your services
grove services status
```

That's it. Once an app is registered, grove knows how to start, stop, and restart its services.

---

## Registering Apps

### Basic Registration

```bash
grove services add myapp
```

This registers an app called `myapp` with sensible defaults:

- **System name:** `myapp` (the directory name in `~/Herd`)
- **Services:** `horizon` (Horizon queue worker via Supervisor)
- **Supervisor process:** `myapp-horizon`
- **Domain:** `myapp.test`

### Registration Options

If your Herd directory name differs from the name you want to use in commands, or if you're running Reverb, pass additional flags:

```bash
# App named 'crm' but lives in ~/Herd/company-crm
grove services add crm --system-name=company-crm

# App running both Horizon and Reverb
grove services add myapp --services=horizon:reverb

# Override the local domain
grove services add myapp --domain=myapp.local.test

# Set a custom Supervisor process name
grove services add myapp --supervisor=myapp-worker
```

You can combine any of these:

```bash
grove services add myapp \
  --system-name=myapp-repo \
  --services=horizon:reverb \
  --domain=myapp.test
```

**What `--system-name` does:** Grove uses the system name to locate the Herd symlink at `~/Herd/<system-name>-current`. If your repo is checked out as `myapp-repo` and Herd serves it from that directory, pass `--system-name=myapp-repo`.

**What `--services` does:** Controls which background processes grove manages. See [Service Types](#service-types) below. An unrecognised value is rejected:

```text
Invalid services: foo (must be horizon, horizon:reverb, or none)
```

**Confirmation output:** A successful registration prints a summary so you can see exactly what was stored (`Supervisor` shows `none` when the process field is empty, e.g. for `services=none`):

```text
✓ Registered app: myapp

  System name: myapp
  Services:    horizon
  Supervisor:  myapp-horizon
  Domain:      myapp.test

Config: /Users/you/.grove/services/apps.conf
```

### Validation

Grove validates every value before it is written to the registry, because the config file is a strict pipe-delimited format (see [Config File Format](#config-file-format)) and an invalid value would corrupt it or the `services apps --json` data contract:

- **App name** is run through grove's repository whitelist -- no path traversal (`../`), no leading dash, and no shell or pipe metacharacters.
- **System name** and **supervisor process** must not contain a `|` or a newline.
- **Domain** must be a valid hostname: only alphanumerics, dash, and dot. An invalid value dies with `Invalid domain: '<value>' (only alphanumeric, dash, and dot allowed)`.

### Updating an App

There is no in-place update. Re-running `grove services add` for a name that already exists is rejected:

```text
App 'myapp' is already registered. To update, remove first: grove services remove myapp
```

To change any setting, remove the app and add it again:

```bash
grove services remove myapp
grove services add myapp --services=horizon:reverb
```

### Viewing Registered Apps

```bash
grove services apps
```

Shows a table of every registered app with its system name, services, Supervisor process, and domain.

For machine-readable output (useful in scripts or the grove desktop app):

```bash
grove services apps --json
```

Returns a JSON array:

```json
[
  {"name":"myapp","system_name":"myapp","services":"horizon","supervisor_process":"myapp-horizon","domain":"myapp.test"}
]
```

Add `--pretty` to colour and indent the output, exactly as with every other grove JSON command:

```bash
grove services apps --json --pretty
```

### Removing Apps

```bash
grove services remove myapp
```

This removes the app from the registry only. Your worktrees, Supervisor configs, and `.env` files are left untouched.

---

## Managing Services

### Checking Status

```bash
# Status of all registered apps
grove services status

# Status of a specific app
grove services status myapp
```

The status view shows:

- Whether the Supervisor daemon is running (`Running` / `Not running`)
- Whether Redis is reachable (`Running` / `Not running`)
- For each registered app:
  - The active worktree (via the `-current` symlink)
  - Supervisor process state — `RUNNING` for a healthy process; otherwise grove echoes the raw state word reported by `supervisorctl` (e.g. `STOPPED`, `FATAL`, `BACKOFF`); or `Not configured` when `supervisorctl` has no matching process. (Apps registered with `services=none` show no Supervisor line at all.)
  - Horizon status — `Running`, `Inactive`, or `Unknown` when PHP or the app's `artisan` binary is unavailable to query
  - Whether the scheduler LaunchAgent is loaded (`Loaded` / `Not loaded`)

Running `grove services` with no subcommand is a shortcut to `grove services status` when at least one app is registered.

### Starting Services

```bash
# Start a specific app
grove services start myapp

# Start all registered apps
grove services start all
```

Starting an app does two things:

1. Sends `supervisorctl start <process>` to bring up the Horizon (and optionally Reverb) worker.
2. Calls `launchctl load` on the scheduler LaunchAgent plist at `~/Library/LaunchAgents/com.<app>.scheduler.plist`, if it exists.

If the Supervisor daemon itself isn't running when you call `grove services start`, grove will start it automatically before proceeding.

### Stopping Services

```bash
# Stop a specific app
grove services stop myapp

# Stop all registered apps
grove services stop all
```

Stopping is the reverse: `supervisorctl stop` for the queue worker, and `launchctl unload` for the scheduler.

### Restarting Services

```bash
# Restart a specific app
grove services restart myapp

# Restart all registered apps
grove services restart all
```

Restart sends `supervisorctl restart <process>`. Note that restart does **not** touch the scheduler LaunchAgent -- only the Supervisor process.

`grove services restart` is also deliberately a no-op in two cases, so it is safe to call from a hook for any repo: with **no argument** it returns silently, and with an **unregistered** app name it returns silently too. (See [Integration with `grove switch`](#integration-with-grove-switch).)

---

## Monitoring

### Service Health Check

```bash
grove services doctor
```

Doctor checks the following and flags anything that needs attention:

| Check | What it looks for |
|-------|-------------------|
| Homebrew | `brew` is on your PATH |
| PHP | `php` is available (required by Horizon status checks); on success doctor prints the detected PHP version |
| Redis | `redis-cli ping` returns a response |
| Supervisor | Supervisor daemon is started via `brew services` |
| Supervisor configs | `/opt/homebrew/etc/supervisor.d/` exists and lists config count |
| Symlinks | Each registered app has a valid `-current` symlink in `~/Herd` |
| Supervisor processes | Each app's named process is RUNNING in `supervisorctl` |
| Scheduler LaunchAgents | Each app's `com.<app>.scheduler.plist` is loaded in `launchctl`; apps without a plist are noted as having no scheduler configured |

For each failed check, doctor shows a fix command. Run `grove services doctor` after any infrastructure change -- it's the fastest way to find out why a service stopped working.

**Common fixes shown by doctor:**

```bash
brew services start redis
brew services start supervisor
```

### Viewing Logs

```bash
# Tail Horizon logs for an app
grove services logs myapp

# Specify a log type
grove services logs myapp horizon     # Same as above (default)
grove services logs myapp queue       # Alias for horizon -- same file
grove services logs myapp reverb      # Reverb WebSocket logs
grove services logs myapp scheduler   # macOS LaunchAgent scheduler logs
```

Log file locations:

| Type | Path |
|------|------|
| `horizon` / `queue` | `<worktree>/storage/logs/horizon.log` |
| `reverb` | `<worktree>/storage/logs/reverb.log` |
| `scheduler` | `~/Library/Logs/<app>-scheduler.log` |

`horizon` and `queue` are aliases for the same file -- Horizon writes its log there regardless of what you call it.

The command tails the file with `tail -f` and runs until you press Ctrl+C.

Calling `grove services logs` with no app prints a usage line listing the valid types, and an unrecognised type is rejected:

```text
Unknown log type: foo (valid: horizon, reverb, scheduler, queue)
```

### Horizon Dashboard

```bash
grove services horizon myapp
```

Opens the app's Horizon dashboard at `https://<domain>/horizon` in your browser, where `<domain>` is the app's registered domain (so `myapp.test` becomes `https://myapp.test/horizon`). This only works for apps registered with `services=horizon` or `services=horizon:reverb`; for any other app grove exits with "does not use Horizon". Grove reads the domain from your app registry -- no need to remember the URL.

---

## Configuration

### Config File Format

Apps are stored in `~/.grove/services/apps.conf`. Grove creates this file automatically when you first run `grove services add`. You can also edit it directly.

Each line is a pipe-delimited record:

```text
# app_name|system_name|services|supervisor_process|domain
myapp|myapp|horizon|myapp-horizon|myapp.test
```

The header comment is included by grove when it creates the file for you. Blank lines and lines beginning with `#` are ignored.

> **Editing by hand?** The format is strictly **five** pipe-delimited fields per record. Grove skips any line that doesn't have exactly five fields (or whose app name is empty), printing a warning to stderr: `Skipping malformed registry line (expected 5 fields, got N): <line>`. A stray `|` shifts the columns and the whole line is dropped. The same constraints that `grove services add` enforces apply to hand edits too -- see [Validation](#validation): the domain must be a valid hostname (alphanumerics, dash, dot), and `system_name`, `supervisor_process`, and `domain` must not contain a `|` or newline. Keeping the file valid also protects the `services apps --json` data contract consumed by the grove desktop app. When in doubt, use `grove services remove` + `grove services add` rather than editing the file.

**Field reference:**

| Field | Description | Default |
|-------|-------------|---------|
| `app_name` | Short name used in all `grove services` commands | (required) |
| `system_name` | Directory name in `~/Herd` (bare repo prefix) | Same as `app_name` |
| `services` | Which services to manage -- see below | `horizon` |
| `supervisor_process` | Supervisor process name passed to `supervisorctl` | Set by `grove services add` (see [Supervisor Process Naming](#supervisor-process-naming)) |
| `domain` | Local `.test` domain | `<system_name>.test` |

> **Empty `supervisor_process`?** The defaults in the table below are what `grove services add` *writes* into the file. If you hand-edit a record and leave `supervisor_process` blank, grove instead falls back at runtime to `<app_name>-horizon` -- note this is based on `app_name`, not `system_name`, so it can differ from the add-time default.

### Service Types

| Value | What grove manages |
|-------|-------------------|
| `horizon` | Laravel Horizon queue worker via Supervisor |
| `horizon:reverb` | Horizon + Laravel Reverb WebSocket server |
| `none` | App registered in grove but no queue services to manage |

**What each value enables:**

- `horizon` and `horizon:reverb` enable the full feature set: Supervisor process management on start/stop/restart, Horizon status in `grove services status`, and the `grove services horizon` dashboard command.
- `none` registers the app for symlink checks, scheduler control, and log paths only. With `services=none`, start/stop/restart make **no** `supervisorctl` call, no Horizon status is shown, and `grove services horizon <app>` is rejected with `<app> does not use Horizon`. Use it when you want grove to track an app that doesn't run Horizon.

### Supervisor Process Naming

The `supervisor_process` field tells grove which process name to pass to `supervisorctl`. Grove sets a default based on your chosen service type:

| Services value | Default supervisor process | `supervisorctl` command |
|----------------|---------------------------|-------------------------|
| `horizon` | `<system_name>-horizon` | `supervisorctl restart myapp-horizon` |
| `horizon:reverb` | `<system_name>:*` | `supervisorctl restart myapp:*` |
| `none` | *(empty -- no supervisorctl call)* | — |

The `:*` syntax tells Supervisor to restart every process in the `myapp` group at once -- this covers both the `horizon` and `reverb` workers if they're defined as a group in your Supervisor `.ini` file.

**How grove matches a `name:*` group in `status` and `doctor`:** grove strips the `:*` suffix and matches every `supervisorctl` process whose name starts with `name:` (or is exactly `name`). So a stored process of `myapp:*` matches `myapp:horizon`, `myapp:reverb`, and so on. Define your Supervisor group accordingly, or status/doctor won't find the processes.

If your Supervisor config uses a different naming convention, override it with `--supervisor` when registering:

```bash
grove services add myapp --supervisor=myapp-worker:horizon
```

---

## Integration with `grove switch`

When you run `grove switch` to change the active worktree for a repo, a post-switch hook can automatically restart that app's services so the Horizon worker picks up the new codebase.

Two example hooks work together, and **filename order matters** -- post-switch hooks run in lexical order:

1. `examples/hooks/post-switch.d/01-update-current-link.sh` -- repoints the `~/Herd/<system-name>-current` symlink at the newly switched-to worktree.
2. `examples/hooks/post-switch.d/02-services-restart.sh` -- restarts that app's services:
   ```zsh
   grove services restart "$GROVE_REPO"
   ```

The `01` hook must run before `02`: restart targets whatever the `-current` symlink points at, so if the symlink hasn't been updated first, the restart hits the *previous* (stale) worktree. **Install both example hooks, not just `02`.**

Grove sets `$GROVE_REPO` automatically before running any hook -- it's the short name of the repository being switched. You don't set it yourself.

**Why this is safe by design:** `grove services restart` is idempotent. If `$GROVE_REPO` doesn't match any registered app, the command returns silently with no error (as does calling it with no argument). This means the hook works for every repo without needing any special-casing -- it only does something if the repo is registered.

### Installing the Hooks

Copy **both** example hooks to your global hooks directory so the symlink is updated before the restart:

```bash
cp examples/hooks/post-switch.d/01-update-current-link.sh ~/.grove/hooks/post-switch.d/
cp examples/hooks/post-switch.d/02-services-restart.sh ~/.grove/hooks/post-switch.d/
chmod +x ~/.grove/hooks/post-switch.d/01-update-current-link.sh
chmod +x ~/.grove/hooks/post-switch.d/02-services-restart.sh
```

Or install them for a specific repo only:

```bash
mkdir -p ~/.grove/hooks/post-switch.d/myrepo
cp examples/hooks/post-switch.d/01-update-current-link.sh ~/.grove/hooks/post-switch.d/myrepo/
cp examples/hooks/post-switch.d/02-services-restart.sh ~/.grove/hooks/post-switch.d/myrepo/
chmod +x ~/.grove/hooks/post-switch.d/myrepo/01-update-current-link.sh
chmod +x ~/.grove/hooks/post-switch.d/myrepo/02-services-restart.sh
```

### Skipping the Restart

If you need to switch worktrees without restarting services -- for example, when doing a quick comparison -- set `GROVE_SKIP_SERVICES=true` in your shell before switching:

```bash
GROVE_SKIP_SERVICES=true grove switch myapp feature/my-branch
```

The hook detects this variable and skips the restart, printing a message to confirm:

```text
  Skipping service restart (GROVE_SKIP_SERVICES=true)
```

---

## Migrating from DevCTL

If you previously used DevCTL to manage services, grove's installer handles the migration for you.

### Automatic Migration (via Installer)

When you run the grove installer (`install.sh`), it checks for an existing config at `~/.devctl/apps.conf`. If found, it asks:

```text
DevCTL Migration...
  Found existing DevCTL config at ~/.devctl/apps.conf

  Migrate to grove services? [Y/n]:
```

Answering yes copies the file to `~/.grove/services/apps.conf`. The original file at `~/.devctl/apps.conf` is kept as a backup -- nothing is deleted.

### Manual Migration

If you skipped the migration prompt or installed grove without the installer:

```bash
mkdir -p ~/.grove/services
cp ~/.devctl/apps.conf ~/.grove/services/apps.conf
```

The config format is identical between DevCTL and grove services, so no conversion is needed. Verify the migration worked:

```bash
grove services apps
```

---

## Troubleshooting

### "Unknown app" error

```text
Unknown app: myapp. Run 'grove services apps' to see registered apps.
```

The name you passed doesn't match anything in `~/.grove/services/apps.conf`. Check your registered apps:

```bash
grove services apps
```

Names are case-sensitive. If the app is listed but spelled differently, either re-register it with the correct name or update the config file directly.

### Supervisor not running

If the `Supervisor Daemon:` line in `grove services status` shows `Not running (run: brew services start supervisor)`:

```bash
brew services start supervisor
```

Then verify it started:

```bash
brew services list | grep supervisor
```

If the daemon is up but an app's `Supervisor:` line reports `Not configured`, the daemon is running yet `supervisorctl` doesn't know about that app's named process. Check that your `.ini` files are in `/opt/homebrew/etc/supervisor.d/`, are syntactically valid, and define a process matching the app's `supervisor_process` name (for a `name:*` group, see [Supervisor Process Naming](#supervisor-process-naming) for how grove matches the group prefix).

### Services not restarting on switch

1. Confirm the post-switch hook is installed and executable:
   ```bash
   ls -la ~/.grove/hooks/post-switch.d/
   ```

2. Check that `GROVE_SKIP_SERVICES` isn't set in your shell profile:
   ```bash
   echo $GROVE_SKIP_SERVICES
   ```

3. Confirm the repo name matches a registered app (the hook passes `$GROVE_REPO` to `grove services restart`):
   ```bash
   grove services apps
   ```

4. Run `grove services doctor` to check for broader issues.

### Redis connection issues

If the `Redis:` line in `grove services status` shows `Not running (run: brew services start redis)`:

```bash
brew services start redis
redis-cli ping  # Should return: PONG
```

Horizon won't process jobs without Redis. If Redis is running but Horizon still appears inactive, check your Laravel app's `.env` for `REDIS_HOST` and `QUEUE_CONNECTION=redis`.

### Log file not found

```text
Log file not found: /Users/you/Herd/myapp-current/storage/logs/horizon.log
```

This usually means either:

- The `-current` symlink doesn't exist (run `grove services doctor` to check)
- Horizon hasn't written any logs yet (try `grove services start myapp` first)
- The log file path in your app differs from the default (check `storage/logs/` manually)

---

For general grove usage, see the [README](../../README.md).
