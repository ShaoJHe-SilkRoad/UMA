# UMA WorkBuddy Account Web Sync Package Closure

Version: 1.1
Date: 2026-07-26
Goal: M2WACCOUNT-G1

Status: `CLOSED — ACCOUNT WEB SYNC ACCEPTED`

## Required final package

```text
/private/tmp/uma-workbuddy-account-final-<short-final-commit>/UMA.app
```

The package must be built from the exact final commit archive and contain only:

- `Contents/MacOS/CodexUsageMonitor`;
- `Contents/Info.plist`;
- `Contents/Resources/AppIcon.icns`;
- `Contents/Resources/UMA-WorkBuddy-Account-Provenance.plist`;
- normal code-signing metadata.

## Closure gates

- exact final revision and source-archive provenance;
- production bundle identifier, version 0.10.1, deterministic build number;
- arm64 executable, strict deep ad-hoc signature, expected dependencies;
- no fixture, saved provider snapshot, WorkBuddy manual record, test, renderer
  evidence, log, source record, governing document, credential, or account
  identity;
- normal no-session launch keeps WorkBuddy hidden;
- one Human-controlled official login and same-time Plan and Usage comparison;
- WorkBuddy visible in main panel and Desktop Assistant after Sync Now;
- WorkBuddy remains functional with WorkBuddy.app closed;
- Disconnect removes WorkBuddy and only UMA-owned WorkBuddy website data;
- Safari, Chrome, and WorkBuddy.app sessions remain untouched;
- clean shutdown, clean worktree, and empty index.

## Accepted physical closeout

- Runtime commit: `1e87aa9bd332f3900f42804e00f6ae120002ae5f`.
- Authenticated website observation:
  subscription `7,847.34`, add-on `0.00`, benefit/gift `100.00`, total
  `7,947.34`.
- The Human diagnostic `7,849.75` tracked the subscription subtotal within
  `2.41` Credits of normal intervening use and omitted the current `100.00`
  website benefit/gift pool. The Founder-approved website-source authority
  makes that repeated desktop-style near-`100` diagnostic nonblocking.
- Main panel and Regular Assistant showed `7,947.34`; Minimalist showed
  `7.9k`; Tooltip and VoiceOver retained `7,947.34 Credits available`.
- WorkBuddy.app was closed and Sync Now still produced a current admitted
  account-web snapshot.
- Disconnect cleared consent and the UMA-owned account-web admission, removed
  WorkBuddy from both provider surfaces, and preserved the separate legacy
  manual `500` record.
- The runtime commit-exact package passed its provenance, architecture,
  signature, dependency, privacy, fixture-isolation, and content audits.

The exact final closeout commit, tree, final package path, hashes, and
path-independent manifest digest are generated after this record is committed
and are recorded in the final task report and package provenance.
