# UMA M5DBG-G1 Acceptance

## Scope and privacy lock

M5DBG-G1 validates the main-app composition:

`Codex → Claude Code → WorkBuddy`

Claude Code remains excluded from Desktop Assistant. This record contains only
sanitized classifications and aggregate counts. It contains no live quota
value, reset time, provider payload, account identity, prompt, response,
session, transcript, task, tool, workspace, credential, token, or settings
backup.

## Accepted evidence

- one Human-controlled normal Claude response produced a current official
  status-line callback without DEV reading the prompt or response;
- five-hour and seven-day window classifications and reset classifications
  were valid, with used-to-remaining conversion owned once by the shared model;
- stable main-panel ordering was Codex → Claude Code → WorkBuddy;
- the 50-event sanitized matrix contained 45 connector-accepted packets,
  three connector-rejected packets, and two relay-rejected inputs;
- two identical valid packets were accepted without duplicate snapshot
  publication;
- one separate sanitized recovery control restored fresh state;
- 30 global Manual Refresh actions each performed at most one Codex read, one
  WorkBuddy read, and one Claude configuration health check, with no synthetic
  Claude provider request;
- 50 main-panel open/close cycles and 30 global Settings / Agent Settings
  cycles completed without crash, duplicate listener, or provider reorder;
- 20 task-owned candidate relaunches completed, followed by an exact-path
  LaunchServices clean-shutdown proof with one process, one status item, no
  more than one owned Codex child, and no stale relay socket;
- repeated Show All / Hide All transitions and close/reopen expansion
  persistence passed;
- the bounded 31-sample resource run retained one Claude listener, two Unix
  sockets while enabled, no relay helper, no extra owned child, and no
  monotonic CPU, RSS, thread, descriptor, or file-write trend;
- Repair Relay and Disable Integration passed through the actual candidate
  controls; exact settings restoration preserved the original bytes, original
  `0644` permissions, theme-only structure, and no integration directory or
  socket;
- English and Simplified Chinese Settings presentation passed and the
  original English preference was restored;
- the synthetic main-panel renderer covered three-provider collapsed ordering,
  Claude-only expansion, independently absent five-hour and seven-day windows,
  stale and failed states, Light and Dark appearance, Reduce Transparency,
  Increase Contrast, Reduce Motion, and Simplified Chinese; all captures were
  readable, retained one exterior contour, and showed no clipping or overlap;
- focused M5DBG: 3/3 PASS; combined M5: 87 PASS; full suite: 412 PASS; Debug,
  Release, strict-concurrency Release, and strict relay-helper Release: PASS;
- the authorized physical macOS matrix completed Light → Dark → Light,
  Reduce Transparency Off → On → Off, Increase Contrast Off → On → Off, and
  Reduce Motion Off → On → Off with the real task-owned panel and Settings
  surfaces remaining readable, correctly sized, and free of clipping or
  overlap; the VoiceOver attempt opened the macOS Accessibility Tutorial, so
  that case was immediately restored and then explicitly bypassed by the
  Founder;
- the final package must be commit-exact, privacy-bounded, arm64-only,
  strictly deep signed, fixture-free, and dependency-clean.

## Runtime repair

The provider-neutral eligibility scanner previously called both Claude's
configuration-aware probe and its refresh action during one shared Manual
Refresh. Passive local connectors now use the completed probe as their sole
health check. Active connectors retain their one current source read. Focused
coverage locks 30 scans to 30 Codex reads, 30 WorkBuddy reads, 30 Claude health
checks, and zero generated Claude provider events.

## Natural Claude startup repair

Before M5DBG-N1, a current Claude card was runtime-only. Relaunching UMA returned
Claude to Waiting until a later normal Human Claude use produced another
status-line event. M5DBG-N1 preserves one strictly sanitized last-valid quota
record after the first valid event. A later UMA launch restores that record as
Cached or Stale immediately, starts no Claude process, submits no prompt, and
counts no provider read or usage event. The next normal Claude status-line event
replaces the record atomically and returns the card to Fresh.

The persisted schema is limited to:

- schema version and the `claude.statusLine` source identifier;
- optional five-hour remaining percentage and future reset epoch;
- optional seven-day remaining percentage and future reset epoch;
- observation timestamp;
- bounded safe source version;
- selected-window identifier only when it names a surviving quota window.

It never stores used percentage, raw status-line JSON, session or prompt
identifiers, transcript paths, workspace or repository data, prompt, response,
task or tool content, tokens, account identity, credentials, authentication
data, command history, or payload history. Each reset window expires
independently. Both expired returns Claude to Waiting and deletes the record.

Cached and Stale values retain a neutral severity, cannot create a decrement
sample, and cannot trigger low-quota or exhaustion alerts. Settings and expanded
details disclose source, state, observation age, surviving windows, reset text,
and: “Updates automatically the next time Claude Code is used.”

Automated M5DBG-N1 acceptance is complete:

- focused sanitized-snapshot suite: 8/8 PASS;
- M5-G2 connector and Settings regressions: 18/18 PASS;
- combined M5 suites: 95/95 PASS across seven suites;
- full regression suite: 420/420 PASS across 47 suites;
- Debug, Release, and strict-concurrency warnings-as-errors Release builds:
  PASS;
- eleven synthetic Cached/Stale/failure/single-window/appearance/accessibility/
  localization renders: PASS with no clipping or overlap;
- package syntax and contract, explicit cache-record exclusion, privacy and
  secret scans, arm64 executable checks, and Release dependency audit: PASS.

The physical Appearance and accessibility matrix is complete under the
Founder-approved VoiceOver bypass. The original macOS state was Light
appearance with Reduce Transparency, Increase Contrast, Reduce Motion, and
VoiceOver all Off. The final verified state exactly matches those values.

The physical task-owned candidate also proved immediate Cached restoration
without a Claude prompt or provider read, natural Cached-to-Stale aging,
collapsed and expanded disclosure geometry, Settings open/close behavior, and
stable panel sizing under each completed system transition. The temporary
Claude integration was disabled through UMA, leaving the provider-owned
settings file theme-only, no relay socket, and no task-owned process.

Exact staging, the authorized local commit, and the final commit-exact package
audit remain the delivery gates.

## Delivery lock

The final package path is:

`/private/tmp/uma-m5dbg-final-<commit>/UMA.app`

No Desktop application replacement, provider task generation, push, release,
notarization, deployment, or publication is authorized.
