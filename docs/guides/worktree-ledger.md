# Worktree Ledger integration

Grove can ask [Waypoint](https://github.com/dannyharding/notes)'s Worktree
Ledger whether a worktree still holds work nobody has recorded, and refuse to
remove it if so.

The integration is **optional**. Without `way` installed, or with
`LEDGER_INTEGRATION=off`, grove behaves exactly as it always has.

## What it prevents

On 4 August 2026 a cleanup pass came close to destroying a day's work: a
worktree held the only copy of an uncommitted change, another held commits that
existed on no remote, and a third had valuable work parked in a stash that
`git status` reported as nothing at all. None of that was visible at the point
of removal.

With the integration on, each of those refuses removal and says exactly why.

## Turning it on

```bash
# ~/.groverc
LEDGER_INTEGRATION=auto      # auto (default) | off | required
GROVE_WAY_BIN=/opt/way       # optional: an explicit path to `way`
```

| Mode | Behaviour |
|---|---|
| `auto` | Use the ledger when `way` is available. This is the default. |
| `off` | Never consult it. Grove behaves as it did before the integration existed. |
| `required` | Consult it, and **refuse removal** when the ledger cannot answer. Use this once every worktree is registered. |

Waypoint also needs a ledger root — see its own documentation. Without one,
`way` reports that it could not answer, and in `auto` mode grove carries on.

## What happens on removal

```text
$ grove rm -f app scooda-1784

REMOVAL BLOCKED — wt_019fce00 holds work that is not safely recorded.

  [CRITICAL] dirty-uncheckpointed
      0 staged, 0 modified and 1 untracked file(s) are not covered by any
      checkpoint. Run `way worktree checkpoint` to record this state before
      removing anything.
  [CRITICAL] local-only-commits
      1 commit(s) exist only on this machine — no remote-tracking ref reaches
      them. Push the branch, or record an explicit acknowledgement.

To proceed anyway, issue a one-use token with
`way worktree removal-check --acknowledge`.

✖ ERROR: removal blocked by the worktree ledger (see above).
```

**`-f` does not bypass this.** Forcing git and accepting the loss of work
nobody has recorded are different decisions, and grove keeps them separate.

## Proceeding anyway

```bash
cd ~/Herd/app-worktrees/scooda-1784
way worktree removal-check --acknowledge     # prints a token
grove rm -f --ledger-ack ack1.ack_019f… app scooda-1784
```

A token is:

- **scoped** to one worktree, one exact state and one set of risks;
- **single-use** — a second attempt is refused;
- **invalidated by any change** to the worktree between issuing and using it, so
  it can never authorise the loss of work that arrived in between;
- **recorded** as an immutable `risk-acknowledged` event, so the ledger shows
  what was accepted and by whom.

Issuing a token changes nothing on its own. It only prints what you would be
accepting.

## Exit codes

| Code | Meaning |
|---|---|
| 6 | `LEDGER_BLOCKED` — the ledger refused this removal |

`way worktree removal-check` itself exits `0` when clear, `1` when blocked, `2`
on a usage error and `3` when it could not answer (the worktree is not
registered, or no ledger root is configured). Grove treats `3` as "not
consulted" in `auto` mode and as a refusal in `required` mode. **A worktree
grove could always remove does not become unremovable merely because Waypoint
has nothing to say about it.**

## What else grove does

| Command | Ledger action |
|---|---|
| `grove add` | Registers the new worktree. Best effort — a failure never undoes the add. |
| `grove rm` | Gates removal, before the confirmation prompt and before git touches anything. Then archives the record once the worktree is gone. |
| `grove move` | Reconciles the recorded path. The worktree's identity is unchanged. |
| `grove status --json` | Adds an optional nested `ledger` object. |

### Archiving on removal

The worktree's ledger id is read **before** git touches anything — once the
folder has gone there is nowhere to stand and no sidecar to read, so the id is
the only handle left on the record. After the removal succeeds, grove issues
`way worktree archive --worktree-id <id>`.

This is best effort in both directions, and deliberately so:

- No id (an unregistered worktree, or `way` could not be asked) means grove
  leaves the record alone rather than guessing which one to close.
- A failed archive never fails the removal. The worktree is already gone by
  then; reporting a successful removal as a failure would be worse than a
  stale record.

Archiving retains every ref — it records that the work is finished with, it
does not delete anything. Without it, a removed worktree stays `active` for
ever and `way worktree doctor` keeps counting folders that no longer exist.

## The `ledger` object in JSON

Additive and nested, so every existing consumer keeps working. It appears on
**both** `grove ls <repo> --json` and `grove status <repo> --json` — Grove
desktop reads `ls`, so an overlay present only on `status` reaches nobody:

```json
{
  "branch": "scooda-1784",
  "path": "/Users/danny/Herd/app-worktrees/scooda-1784",
  "sha": "1111111",
  "dirty": true,
  "ledger": {
    "available": true,
    "worktree_id": "wt_019887c4",
    "workstream_id": "ws_2fa_enrolment",
    "risk": "critical",
    "risk_available": true,
    "risk_unavailable_reason": null,
    "removal_blocked": true,
    "lease_available": true,
    "lease_unavailable_reason": null,
    "lease_held": true,
    "lease": {
      "tool": "claude",
      "session_id": "01H…",
      "machine_id": "machine_019fcd4d",
      "acquired_at": "2026-08-06T08:00:00Z",
      "last_heartbeat_at": "2026-08-06T08:20:00Z",
      "expires_at": "2026-08-06T08:50:00Z"
    },
    "checkpoint_at": "2026-08-04T14:30:00Z",
    "next_action": "Run focused UAT on the 2FA enrolment path",
    "narrative_status": "present",
    "drift": true,
    "unavailable_reason": null
  }
}
```

The key is **absent entirely** when the integration is off or `way` is not
installed. When `way` is present but could not answer, the object appears with
`"available": false` and an `unavailable_reason`.

> `available: false` means **unknown**, not "nothing at risk". A consumer must
> never render it as safe. That distinction is why this is a nested object
> rather than flat fields that would default to `false`.

### Where each field comes from, and why there are three calls

No single `way` command answers everything, so building one overlay runs three,
concurrently (sequentially they would more than double `grove ls`):

| Command | Fields |
|---|---|
| `way worktree resume --format json` | `worktree_id`, `workstream_id`, `checkpoint_at`, `next_action`, `narrative_status`, `drift` |
| `way worktree removal-check --json` | `risk` (its `highest_risk`), `removal_blocked` |
| `way worktree lease status --json` | `lease_held`, `lease` |

`resume` is the identity source, so only a failure there makes the **whole**
overlay unavailable. Risk and lease carry their own flags instead:

- `risk_available: true` with `risk: null` means **checked, nothing found**.
- `risk_available: false` means **unknown** — render it as unknown, never as
  clear, and `removal_blocked` stays `null` rather than being inferred.
- `lease_available: false` means **unknown**, not "nobody is working here".
- `lease_held: false` with a `lease` object means the claim **expired**; the
  holder it names is still a fact worth showing.

`removal-check` prints its document to stdout **and exits 1** when it blocks, so
a block is an answer and its risk is kept. Only exit 2 (usage) and exit 3 (could
not answer) leave the risk unknown. None of these calls ever passes
`--acknowledge` or `--override-token`: issuing or spending an override is a
deliberate, recorded command-line act and must never be a side effect of listing
worktrees.

The schema is owned by Waypoint at
`docs/contracts/grove-worktree-status-v2.schema.json`.

## The base ref sidecar

Grove used to store a worktree's base ref with `git config --local grove.base`.
On a bare-repository layout — exactly how the Herd worktrees are set up —
`--local` resolves from the **common** config, so every linked worktree read the
same value and a worktree's real base was silently replaced by whichever one was
written last.

The base now lives in each worktree's own git administrative directory, resolved
with `git rev-parse --git-path grove-base`. Nothing needs migrating: the legacy
config is still read when no sidecar exists, and is still written so an older
`grove` keeps working for at least one release. `extensions.worktreeConfig` is
never enabled.

## Hook environment

Lifecycle hooks receive two additional variables:

| Variable | Meaning |
|---|---|
| `GROVE_FORCE` | `true` when `-f` was passed. For **reporting** that a removal was forced — never for skipping your own checks. |
| `GROVE_LEDGER_ACK` | The acknowledgement token, when one was supplied. |

## Turning it off

```bash
# ~/.groverc
LEDGER_INTEGRATION=off
```

Grove reverts to its previous behaviour immediately. Nothing in the ledger is
deleted, and turning it back on picks up exactly where it left off.
