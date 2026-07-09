# Grove CLI Cheatsheet

Your day-to-day worktree + services reference. Grove manages multiple git
worktrees per repo and (optionally) points Herd, Supervisor, Horizon and the
scheduler at whichever worktree you're actively working on.

**The one you'll reach for most:** `grove services switch <app> <worktree>`
repoints your queues and scheduler at a different branch folder in one command.

---

## Services: switch the folder your queues + scheduler run against

This is the headline workflow. Each registered app has a `-current` symlink
(e.g. `~/Herd/scooda-current`) that Supervisor, Horizon and the scheduler all
follow. Switching repoints that symlink so your background workers run against
the branch you're testing, not whatever was there before.

```bash
grove services switch scooda gift-aid-auto
```

What that one command does, in order:

1. Stops the app's Supervisor process (Horizon workers, scheduler).
2. Repoints `~/Herd/scooda-current` -> `~/Herd/scooda-worktrees/gift-aid-auto`.
3. Runs `php artisan config:clear` in the new worktree (so nothing serves stale
   cached paths).
4. Restarts Supervisor against the new folder.

After switching, your queue jobs and scheduled tasks run against
`gift-aid-auto`. No manual symlink fiddling, no lingering old workers.

### Everyday services commands

```bash
grove services                       # status of all apps (default)
grove services status                # same, explicit
grove services status scooda         # status for one app
grove services apps                  # list registered apps + their config

grove services start scooda          # start Supervisor for an app
grove services stop scooda           # stop it
grove services restart scooda        # stop + start
grove services start all             # start every registered app

grove services horizon scooda        # open the Horizon dashboard in browser
grove services logs scooda           # tail Horizon/queue log (default)
grove services logs scooda scheduler # tail scheduler log
grove services logs scooda reverb    # tail Reverb log
grove services doctor                # health-check the services setup
```

Log types: `horizon` (default), `queue` (same file), `scheduler`, `reverb`.

### Registering / removing an app (one-off setup)

```bash
grove services add scooda --services=horizon --domain=scooda.test
grove services add myapp  --services=horizon:reverb
grove services add legacy --services=none        # symlink only, no workers
grove services remove scooda
```

Config lives in `~/.grove/services/apps.conf`.

**Gotcha:** switch refuses to run if `~/Herd/<app>-current` exists as a real
directory rather than a symlink (it won't clobber a real folder). If you hit
that, move the folder aside and let grove create the symlink.

---

## Worktree lifecycle

```bash
grove clone git@github.com:org/scooda.git   # clone as a bare repo
grove add scooda feature/login              # new worktree off default base
grove add scooda feature/api main           # new worktree off a named base
grove add --interactive                     # guided wizard
grove add scooda feature/api --dry-run      # preview, create nothing

grove rm scooda feature/login               # remove a worktree
grove rm scooda feature/login --delete-branch --drop-db   # full teardown
grove move scooda feature/login better-name # rename/move a worktree
```

Protected branches (`main`, `master`, `staging`) need `-f` to remove.

---

## Navigation (auto-detects repo/branch when run from inside a worktree)

```bash
grove switch scooda feature/login   # cd + open editor + open URL, all at once
grove code scooda feature/login     # open in editor (fzf picker if branch omitted)
grove open scooda feature/login     # open the app URL in the browser
cd "$(grove cd scooda feature/login)"   # print path, cd into it
grove exec scooda feature/login php artisan migrate   # run a command in it
```

**Shortcuts:** `@1` `@2` `@3` = most recent worktrees. Fuzzy match works too:
`grove code scooda feat-auth` matches `feature/auth-improvements`.

---

## Git operations (auto-detect from a worktree)

```bash
grove status scooda        # dashboard of every worktree
grove pull                 # pull current worktree
grove pull-all scooda      # pull every worktree in parallel
grove sync scooda feature/login main   # rebase onto base branch
grove diff                 # diff vs base branch
grove summary              # summarise changes vs base
grove log -n 10            # recent commits
grove changes              # uncommitted file changes
grove prune scooda         # clean up stale worktrees
grove prune --all-repos    # prune across every repo
```

---

## Laravel helpers (auto-detect from a worktree)

```bash
grove fresh     # migrate:fresh + npm ci + build
grove migrate   # artisan migrate
grove tinker    # artisan tinker
```

---

## Parallel / bulk

```bash
grove build-all scooda           # npm run build on every worktree
grove exec-all scooda "git fetch"   # run a command on every worktree
```

---

## Info + housekeeping

```bash
grove repos                # list all repos
grove ls scooda            # list worktrees for a repo
grove branches scooda      # available branches
grove recent 10            # recently accessed worktrees
grove info                 # detailed info on current worktree
grove dashboard            # overview of everything
grove health scooda        # repo health check
grove doctor               # system requirements check

grove clean scooda         # strip deps from inactive worktrees
grove share-deps status    # share vendor/node_modules across worktrees
grove unlock scooda        # clear stale git lock files
grove repair scooda        # fix common issues (--recovery for aggressive)
grove cleanup-herd         # remove orphaned Herd nginx configs
grove upgrade              # self-update grove
```

---

## Useful flags

| Flag | Effect |
|------|--------|
| `-q`, `--quiet` | Suppress info output |
| `-f`, `--force` | Skip confirmations / remove protected branches |
| `--json` | Machine-readable output (used by grove-app) |
| `--pretty` | Colourised JSON |
| `--dry-run` | Preview `grove add` without creating |
| `-t`, `--template` | Apply a worktree template |
| `--no-cache` / `--refresh` | Bypass / clear the fetch cache |

---

## Typical day

```bash
grove add scooda feature/gift-aid          # spin up a branch worktree
grove switch scooda feature/gift-aid       # jump in (cd + editor + browser)
grove services switch scooda feature-gift-aid   # point queues/scheduler at it
grove services logs scooda                 # watch the queue while you work
# ...code...
grove sync scooda feature/gift-aid main    # keep up to date with main
grove rm scooda feature/gift-aid --delete-branch   # tidy up when merged
```

> Worktree folder names are branch slugs: `feature/gift-aid` becomes
> `feature-gift-aid`. Use the slug form as the `<worktree>` argument to
> `services switch`.

