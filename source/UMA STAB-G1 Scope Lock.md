# UMA STAB-G1 Scope Lock

Status: implementation boundary locked
Goal: UMA STAB-G1
Branch: `codex/uma-stability`

## Accepted predecessor

- Commit: `3bb03e865f460154a33b1c23c85496067eb48c05`
- Tree: `510886c090e0b6641d5ad8ceddfc1b112cc758ea`
- Source worktree: `/Users/juliushe/Developer/UMA-WorkBuddy-AccountSync`
- Package: `/private/tmp/uma-workbuddy-autorefresh-final-3bb03e865f46/UMA.app`
- Version/build: `0.10.1 / 202607260001`
- Historical black-box oracle: `/Users/juliushe/Desktop/UMA_0.10.1.app`

The historical oracle is read-only and is never packaged, replaced, or modified.
STAB-G1 starts from the exact predecessor commit and preserves Logic 1.3.1,
M2WACCOUNT-G1, and M2WACCOUNT-R1 behavior.

## Regression lock

| ID | Accepted behavior | STAB-G1 lock and evidence |
|---|---|---|
| R1 | No opaque white rectangle in Dark Mode | Light/Dark renderer and physical comparison; centralized adaptive glass |
| R2 | One exterior contour per shell/card | Native-host versus SwiftUI owner, centralized card contour, source and renderer tests |
| R3 | One Settings scroll owner; natural fit when content fits | One bounded vertical scroll owner with size-based bounce suppression when content fits |
| R4 | Automatic and manual Assistant density remain distinct | Existing density tests plus 0–8 and 4→5→4 matrix |
| R5 | Natural main-panel height with no first-show blank slab | Initial minimum height, measured expansion, geometry evidence |
| R6 | Regular `210×60`; Minimalist `58.333333×30` | Existing exact geometry tests and renderer evidence |
| R7 | Exact Regular values and accepted compact Minimalist values | Existing percentage/Credit formatting tests |
| R8 | Connector state and usage severity remain independent | Existing ring/tint semantic tests |
| R9 | Codex uses the official executable and at most one owned child | Connector, recovery, process, and normal-HOME checks |
| R10 | No synthetic record is admitted in production or included as package data | Runtime admission tests and strict package file allowlist |
| R11 | WorkBuddy account-web all-pool Decimal extraction and withdrawal remain exact | Existing account-web suite and surface parity checks |
| R12 | One default-on 60-second WorkBuddy timer/read lane | Existing scheduler/coalescing suite and bounded runtime evidence |
| R13 | One nonactivating Assistant with stable position/focus | Lifecycle, position, screen-repair, and no-op redraw checks |
| R14 | Main panel and Assistant share one admitted provider presentation set | Zero/one/two/failure/removal matrix and shared-store assertions |

## Typography decision

Decision: `CLAUDE TYPOGRAPHY FALLBACK USED`

Claude Desktop 1.24012.1 publicly identifies its UI family as Anthropic Sans,
with Anthropic Serif and Anthropic Mono companions. Those font resources are
bundled privately inside Claude, are not system-installed, have no verified
package-redistribution authority in the installed application, and do not
provide the required Simplified Chinese coverage.

UMA therefore uses the closest package-safe native macOS hierarchy:

- SF Pro Text/Display through the system UI font APIs;
- the macOS system CJK cascade, including PingFang SC;
- SF Mono only for technical content;
- tabular figures for percentages, Credits, counters, and menu-bar values.

No font file is copied. The product has no runtime path, launch, or availability
dependency on Claude.app. Exact-font parity is not claimed.

## Visual evidence plan

Evidence is generated only under `/private/tmp` and is never staged. The matrix
covers Light, Dark, Reduce Transparency, Increase Contrast, Reduce Motion,
English, Simplified Chinese, zero/Codex/WorkBuddy/two-provider states,
Regular/Minimalist Assistant, Settings top/bottom, warning/critical values,
exact Credits, unavailable, stale, and authentication-expired fixtures.

Historical and predecessor candidates run one at a time. Provider pages,
credentials, cookies, tokens, account identity, full DOM/HTML, process
arguments, and environments are excluded from evidence.

## Live-read and privacy boundary

- Maximum live allowance: 120 read-only operations for at most 60 minutes.
- Allowed: existing task-owned candidate, sanitized provider availability,
  Refresh, recovery, cadence, resource, and surface evidence.
- Forbidden: generation or spending, login collection, cookie/token/header
  access, broad DOM/HTML extraction, identity collection, private account-page
  inspection, or seeding a normal runtime record.
- An expired WorkBuddy session does not require reauthentication for this Goal;
  deterministic account fixtures cover visual states without entering a package.

## Test and resource plan

- Focused typography, CJK fallback, tabular-number, border-owner, Settings
  scroll, panel geometry, Assistant redraw, local-watcher, and package tests.
- Existing Codex, WorkBuddy account-web, WorkBuddy Auto Refresh, admission,
  localization, accessibility, density, Assistant, privacy, and package suites.
- Full Debug, Release, and strict-concurrency warnings-as-errors builds.
- Bounded 30–60 minute runtime with one host app, one status item, zero or one
  Assistant, at most one owned Codex child, one WorkBuddy WebView, one
  WorkBuddy timer, no overlapping WorkBuddy reads, bounded local file
  descriptors, and no resource/geometry/focus growth.

## Git and package authority

Authorized:

- bounded source, test, script, and STAB record edits;
- exact-file or exact-hunk staging;
- one local runtime commit:
  `fix(stability): preserve 0.10.1 parity and unify typography`;
- one documentation closeout commit only if materially required;
- one commit-exact package under
  `/private/tmp/uma-stability-final-<short-final-commit>/UMA.app`.

Not authorized:

- `git add .`, `git add -A`, `git add -u`;
- reset, clean, amend, fetch, push, tag, release, notarization, deployment,
  publication, installation, Desktop replacement, or modification of the
  historical oracle.

## Completion Lock

After the final report and commit-exact package, stop. Do not begin another
provider or milestone automatically.
