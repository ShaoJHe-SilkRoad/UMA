# UMA M2W Package Closure

Date: 2026-07-25

## R3 authoritative package supersession

- Product: UMA
- Marketing version: `0.10.1`
- Internal build: `202607250004`
- Bundle identifier: `com.kevinchen.CodexUsageMonitor`
- Architecture: `arm64`
- Signing: strict deep ad-hoc
- Final closeout revision: the commit containing this record
- Final package path:
  `/private/tmp/uma-local-live-final-<first-12-of-final-closeout-commit>/UMA.app`
- Provenance:
  `Resources/UMA-Local-Live-Provenance.plist`

The R3 package admits only currently active, authenticated, locally readable
providers. Manual WorkBuddy remains packaged for Settings, persistence
compatibility, and migration, but it is hidden from the main panel, status
summary, and Assistant and exposes no login action. No manual record is seeded
or bundled. A zero-provider launch uses the neutral panel state and suppresses
the empty Assistant shell while retaining its enabled preference.

The historical M2WADBG package record below remains evidence for its accepted
milestone. R3 supersedes its manual WorkBuddy production-visibility behavior.

R3 pre-package acceptance passed 181/181 tests across 27 suites, Debug,
Release, and strict-concurrency warnings-as-errors Release builds, the
zero-provider/Codex-only/qualified-Chinese-Agent renderer matrix, and a bounded
40-minute task-owned resource window. The final report records the exact R3
closeout commit, tree, source-archive digest, executable digest, dependency and
contents audit, exact-path launch, and clean shutdown.

## Closed delivery

- Product: UMA
- Marketing version: `0.10.1`
- Internal build: `202607250002`
- Bundle identifier: `com.kevinchen.CodexUsageMonitor`
- Minimum macOS: `14.0`
- Architecture: `arm64`
- Signing: strict deep ad-hoc
- Runtime repair commit: `3140623a798f721afa0202f13269bccaebbdc75e`
- Runtime repair tree: `3a1df6090f76add3e7efccb3c3d67559af7c8d42`
- Final closeout revision: the commit containing this record
- Final package path:
  `/private/tmp/uma-m2wadbg-final-<first-12-of-final-closeout-commit>/UMA.app`

The final report records the final closeout commit and tree, executable SHA-256,
source-archive SHA-256, and path-independent bundle-manifest digest after the
commit-exact package is built. The package embeds the same full revision and
source-archive digest in `Info.plist` and
`Resources/UMA-M2WADBG-Provenance.plist`.

## Accepted package behavior

- Normal launch with no manual record presents WorkBuddy as unconfigured.
- The isolated Founder review record presents exactly `500 Credits available`
  and `0 used of 500 active` in the main panel.
- Regular and Minimalist Desktop Assistant modes present native Credit text,
  a manual-state mark, and no fake percentage.
- Both surfaces consume the same immutable shared presentation and expose the
  same scope, tier, provenance, lifecycle, and confirmation semantics.
- No `3.6k` fixture value appears in the Founder acceptance state.
- Codex remains first, connected through its accepted connector path, and uses
  the same status, percentage, selected-window, Refresh, and status-item
  behavior.
- Shared Refresh never reads, writes, or advances the WorkBuddy manual record.
- Clear produces unconfigured state, not zero/exhausted state; reconfiguration
  restores the isolated `500 / 0 / 500` record.

## Package audit

The commit-exact package must pass all of the following before this closeout is
reported as complete:

- readable property lists and exact embedded revision;
- `arm64` executable and macOS `14.0` minimum;
- strict deep ad-hoc signature;
- system-only dynamic dependencies;
- production bundle identity;
- source archive built from the final local commit;
- path-independent bundle-manifest verification;
- one host process, one status item, and no more than one owned Codex
  `app-server --stdio` child;
- zero WorkBuddy provider child, network source, polling timer, or private-file
  observer;
- clean exact-path shutdown.

The bundle contains no WorkBuddy primary or recovery record, preferences backup,
renderer evidence, screenshot, log, test, Swift source, JSON fixture, governing
document, account identity, cookie, token, credential, or provider payload.

## Physical acceptance

A 31-minute task-owned combined run exercised the main panel, both Assistant
densities, Assistant show/hide and Always on Top, Settings, English and
Simplified Chinese, shared Refresh, manual update, Confirm unchanged,
recoverable clear/reconfigure, Assistant-to-panel navigation, Codex owned-child
termination/recovery, and application relaunch.

The final continuous sample window retained one host and one owned Codex child,
zero network sockets, bounded threads and descriptors, and non-monotonic RSS.
The isolated primary/recovery WorkBuddy files were identical `0600` files of
481 bytes, below the 8 KiB bound. Clean shutdown removed the host and owned
child. The pre-validation UMA preference file was restored byte-for-byte.

## Delivery boundary

This is a local, uninstalled package. No Desktop application was replaced.
There was no fetch, push, tag, release, notarization, deployment, or
publication. Automatic WorkBuddy synchronization remains `NO-GO`.
