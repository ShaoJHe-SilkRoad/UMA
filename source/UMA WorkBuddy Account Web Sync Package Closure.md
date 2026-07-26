# UMA WorkBuddy Account Web Sync Package Closure

Version: 1.0
Date: 2026-07-25
Goal: M2WACCOUNT-G1

Status: `PENDING HUMAN PHYSICAL BALANCE COMPARISON`

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

Final hashes, commit IDs, validation counts, and privacy findings will be added
only after the runtime and Human gates pass.
