# UMA WorkBuddy Login Package Closure

Version: 1.0
Goal: M2WLOGIN-G1
Runtime implementation: `6db1abed7baded7beae9be89507eb8bf6259fb29`

## Package contract

- Output:
  `/private/tmp/uma-workbuddy-login-final-<short-final-commit>/UMA.app`
- Marketing version: `0.10.1`
- Internal build: `202607250005`
- Bundle identifier: `com.kevinchen.CodexUsageMonitor`
- Architecture: arm64
- Signature: strict deep ad-hoc verification required
- Source state: one immutable `git archive` of the exact final commit

The bundle may contain only the executable, app icon, Info.plist, and
WorkBuddy-login provenance plist. It must not contain manual WorkBuddy records,
connector snapshots, synthetic values, tests, renderer evidence, logs,
governing documents, source records, or the renderer executable.

## Required smoke

- Launch the exact package with a task-owned HOME.
- Confirm one UMA process and one status item.
- Open and close the main panel and Settings.
- Confirm WorkBuddy login assistance is present only in Settings.
- Confirm manual WorkBuddy remains hidden from main, Assistant, and status
  summary.
- Confirm no saved WorkBuddy record and no automatic WorkBuddy network,
  browser, private-file, or Credit read.
- Confirm clean shutdown and no orphaned UMA process.

## Final evidence

Final commit, executable SHA-256, package audit, runtime smoke, and repository
cleanliness are recorded in the M2WLOGIN-G1 final report after completion.

The physical-login result is intentionally:

`HUMAN PHYSICAL LOGIN NOT EXECUTED`

The package smoke must not launch WorkBuddy or perform a real login.
