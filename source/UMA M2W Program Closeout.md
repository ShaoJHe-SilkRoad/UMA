# UMA M2W Program Closeout

Date: 2026-07-25

## R3 authoritative production supersession

```text
manual Credit infrastructure:
retained

manual WorkBuddy production visibility:
disabled

current visible provider:
Codex only when active, authenticated, and locally readable

WorkBuddy:
hidden until source admission

Chinese-agent login:
optional only after source admission and only when login is the sole missing condition

scan triggers:
application launch and Manual Refresh/Check Again only

M2W-LIVE:
dormant
```

M2WADBG-R3 supersedes the historical visible manual-provider behavior recorded
later in this file. It does not delete the exact Decimal Credit model, manual
schema, saved record, Settings workflow, migrations, or tests. Manual data is
compatibility/fallback infrastructure and is not production display authority.

One provider-neutral scanner produces one current admission set. The main panel,
status item, and Desktop Assistant derive only from it. When no provider is
admitted, the panel presents the neutral local-Agent guidance, the status item
has no fabricated percentage, and the Assistant hides its shell without
changing its enabled preference.

## Historical manual-program status

```text
M2W:
CLOSED

Accepted source:
Manual user confirmation

Automatic structured source:
NO-GO

Official-source migration:
M2W-LIVE-G1 dormant

Historical M2W providers:
Codex
WorkBuddy manual presentation (superseded by M2WADBG-R3)

Future provider order:
Codex
Claude Code
WorkBuddy
Manus
Cursor
Kimi+
Doubao / later approved providers

WorkBuddy connector ID:
workbuddy.manualAvailability

Shared pool identity:
buddyAI.sharedCredits

WorkBuddy/CodeBuddy duplicate display:
prohibited
```

## Accepted program result

M2W added one provider-neutral, versioned, overflow-safe availability/Credit
model and one manual WorkBuddy adapter. The accepted manual record has explicit
provenance, bounded primary/recovery persistence, safe validation, native Credit
formatting, localized Settings, a detailed main-panel card, and a presentation-
only Desktop Assistant row.

The current visible provider order is `Codex → WorkBuddy`. Stable provider
identity priorities reserve the future Claude Code slot before WorkBuddy and
place Manus, Cursor, Kimi+, Doubao, and later approved providers after
WorkBuddy. No future provider is implemented by this program.

Both visible surfaces consume the same `AgentCardViewModel`. They do not
independently read persistence, infer totals, recalculate fractions, select
absolute warning thresholds, change provenance, or advance confirmation time.
Credit values never masquerade as percentages. A proportional severity fraction
exists only when a total is valid in the same observation.

## Accepted ownership

```text
1 host app
1 status item
0 or 1 reused Assistant panel
1 Codex connector
1 WorkBuddy manual connector
no more than 1 owned Codex app-server child
0 WorkBuddy provider children
0 WorkBuddy network clients
0 WorkBuddy polling timers
0 WorkBuddy private-file observers
0 Assistant-owned sources, stores, or connectors
```

Shared Refresh remains a Codex operation. WorkBuddy Save/update, Confirm
unchanged, disable/re-enable, and clear/reconfigure remain explicit bounded
Human operations.

## Closed implementation sequence

- M2W-B0: closed
- M2W-G1 Credit value model: closed
- M2W-G2 manual WorkBuddy source: closed
- M2W-G3 main-panel visibility: closed
- M2WDBG-G1 / R1 main-app validation and repair: closed
- M2WA-G1 Desktop Assistant presentation: closed
- M2WADBG-G1 combined closeout: closed
- M2WADBG-R3 local-live admission and Chinese login contract: closed

The runtime repair is commit
`3140623a798f721afa0202f13269bccaebbdc75e`. The final closeout revision is
the commit containing this record; its exact hash, tree, package path, and
digests are recorded in the final task report and embedded in the commit-exact
package.

## Acceptance summary

- M2WADBG-R3 focused scanner/package suites: `12 / 12` PASS.
- M2WADBG-R3 full suite: `181 / 181` PASS across 27 suites.
- M2WADBG-R3 Debug, Release, and strict-concurrency warnings-as-errors Release
  builds: PASS.
- M2WADBG-R3 renderer matrix: PASS for zero-provider and Codex-only states,
  English and Simplified Chinese, Light and Dark appearances, Reduce
  Transparency, Increase Contrast, and the qualified synthetic Chinese-Agent
  login option.
- M2WADBG-R3 bounded 40-minute task-owned resource window: PASS with one host,
  one status item, zero owned provider children, no open network socket, 0.0%
  CPU and 26,000 KiB RSS at the final sample, and clean shutdown.
- Focused combined closeout tests: `5 / 5` PASS across 2 suites.
- Affected WorkBuddy/Assistant regressions: `51 / 51` PASS across 4 suites.
- Full suite: `163 / 163` PASS across 23 suites.
- Debug, Release, and strict-concurrency warnings-as-errors Release builds:
  PASS.
- Renderer matrix including Light, Dark, low Credit, enterprise shared, unknown
  scope, lifecycle, accessibility, Regular, and Minimalist states: PASS.
- Founder isolated `500 / 0 / 500` Experience personal-shared record: PASS on
  both surfaces, with no `3.6k` leakage and no fake percentage.
- Shared Refresh, manual operations, child recovery, relaunch, visibility,
  density, navigation, localization, accessibility, persistence, process,
  network, privacy, fixture, package, and 31-minute resource checks: PASS.
- Original UMA preferences restored byte-for-byte after task-owned physical
  validation.

## Completion boundary

`M2WADBG-R3 PASS — LOCAL-LIVE PROVIDER ADMISSION AND CHINESE LOGIN CONTRACT CLOSED`

The former `M2WADBG-G1` result below remains historical evidence only; its
manual WorkBuddy visibility is superseded by R3.

`M2WADBG-G1 PASS — M2W MANUAL WORKBUDDY PROGRAM CLOSED`

`M2W-LIVE-G1` remains dormant. Claude Code, Manus, Cursor, and other provider
implementation remain separate Founder decisions. No external governing
document was changed. No WorkBuddy account/provider/browser/private data was
accessed. No fetch, push, tag, release, notarization, deployment, publication,
or Desktop installation occurred.
