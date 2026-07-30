# UMA M5 Claude Sanitized Snapshot Contract

Date: 2026-07-30

## Purpose

The Claude local status-line source is event-driven. UMA may show the last
trustworthy Claude quota state on a later UMA launch without starting Claude,
submitting a prompt, reading provider-private content, or treating restoration
as new usage.

## Ownership and location

`AgentConnectorSnapshotStore` owns one Claude-specific sibling record named:

`claude-last-valid-quota.json`

The record uses the existing UMA Application Support directory. It is not a
database, general cache framework, history, or backup. The directory is owner
only (`0700`), the file is owner read/write only (`0600`), and both are excluded
from backup where supported. Replacement is atomic. At most one current record
exists.

## Exact allowlist

Schema version 1 admits only:

- `schemaVersion`;
- `sourceIdentifier`, exactly `claude.statusLine`;
- optional `fiveHourRemainingPercent`;
- optional `fiveHourResetEpoch`;
- optional `sevenDayRemainingPercent`;
- optional `sevenDayResetEpoch`;
- `observationTimestamp`;
- optional bounded safe `sourceVersion`;
- optional `selectedWindowIdentifier`, restricted to a surviving known window.

Percentages are normalized remaining values in the finite range zero through
100. Reset values are integral Unix seconds and must be strictly later than the
current validation instant. The encoded record is limited to 4 KiB. Unknown
root fields, unsafe owner metadata, invalid schema versions, oversized input,
and future observation times fail closed and delete the record.

## Explicit denylist

The record never stores raw status-line JSON, used percentage, session or prompt
identifiers, transcript paths, workspace, repository, branch or worktree data,
prompt, response, task or tool content, token details, account identity,
credentials, authentication data, prior commands, payload history, cookies,
Keychain data, or provider files.

## Lifecycle

```text
No valid record
→ Waiting

First valid current event
→ validate each provider window
→ convert used to remaining exactly once
→ atomically save one sanitized record
→ Fresh

Later UMA launch
→ validate and prune each window independently
→ recent record: Cached
→ older record with a future reset: Stale
→ no Claude launch, prompt, provider read, or usage event

Next normal Claude event
→ validate and normalize once
→ atomically replace the record
→ Fresh

Both windows expired or record invalidated
→ delete record
→ Waiting
```

An expired or malformed five-hour window cannot hide a valid seven-day window,
and the converse is also true. An exact reset boundary is expired. Clock
rollback beyond the small transport-skew allowance fails closed.

## Presentation and activity safety

Cached and Stale cards remain main-panel eligible only through the explicit
`sanitizedLastValidRestore` capability. Other stale providers keep their prior
admission behavior. Restored windows hold remaining values directly, so no
second subtraction occurs. Selected-window restoration is only a presentation
hint and cannot create a Maximum Decrement sample. Cached and Stale states use
neutral severity and do not emit low-quota or exhaustion alerts.

Settings and expanded details disclose the official local status-line source,
Fresh / Cached / Stale state, observation age, surviving window and reset
information, and the copy:

“Updates automatically the next time Claude Code is used.”

No copy asks the Human to send a prompt merely to refresh UMA.

## Invalidation

The record is deleted on Disable Integration, explicit reconnect/repair,
authentication/configuration failure, unsupported configuration, source
ownership loss, invalid root schema, both-window expiry, or explicit disconnect.
A malformed new provider event may mark the in-memory last valid state Stale but
must not overwrite the valid stored record.

Normal UMA termination preserves the record for the next launch.

## Package and privacy boundary

The commit-exact application bundle contains code only. Package audits reject
JSON runtime records, the exact Claude cache filename, databases, fixtures,
sockets, backups, logs, and evidence. Task-owned tests use synthetic records in
`/private/tmp` and remove them after each case.

## Delivery boundary

M5DBG-N1 does not authorize Claude Desktop Assistant integration, provider
startup, provider tasks, account-web fallback, API access, manual quota entry,
installed Desktop UMA replacement, push, release, notarization, deployment, or
publication. The separate physical Appearance and accessibility matrix remains
required before staging and final M5DBG delivery.
