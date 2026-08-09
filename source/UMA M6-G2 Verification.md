# UMA M6-G2 Verification

**Goal:** M6-G2
**Status:** PASS — integrated verification complete

M6-G2 used deterministic fixtures only and made no live provider read or live
quota claim. The complete final-code suite ran through the frozen test entry
point in SwiftPM's supported deterministic serial execution mode.

| Verification | Required result | Current result |
|---|---|---|
| Focused M6-G2 tests | PASS | 42/42 integrated on the repaired final edit set |
| Codex regressions | PASS; mechanism unchanged | PASS in complete suite |
| Claude/M5 regressions | PASS; frozen manifest unchanged | PASS; frozen 52-file set has no diff |
| WorkBuddy regressions | PASS; mechanism unchanged | PASS in complete suite |
| Full suite through `script/test.sh` | PASS | PASS — 534 UI + 18 bridge = 552/552 |
| Debug / Release / strict-concurrency Release | PASS | PASS / PASS / PASS |
| `git diff --check` | PASS | PASS |
| Privacy, secret and identity scans | PASS | PASS — no live/provider/private values retained |
| Working-tree preflight package audit | PASS | PASS — arm64, strict deep ad-hoc signature, system-only dependencies and exact allowlist |
| Protected Desktop application | byte-identical | PASS — untouched by G2 |
| Independent staged-index review | PASS | PASS — repaired 25-file cached scope; no blocking or actionable issue |
| Final worktree / index | clean / empty | Pending the authorized local commit and post-commit Git audit |

## Toolchain recovery

Bare `swift test` is not accepted evidence on this machine. The frozen
`script/test.sh` was not modified. Apple Command Line Tools 27.0, Apple Swift
6.4, its pinned macOS 26.5 SDK and task-owned writable Clang/SwiftPM caches
restore the supported path. The complete suite passes in SwiftPM's deterministic
`--no-parallel` mode without changing or weakening any assertion. Debug,
Release and strict-concurrency Release also pass with the same SDK selection.

## Privacy and freeze gates

No live raw JSON, exact quota/reset/pool identity, prompt, task, conversation,
credential or account identity may enter Git, the package, logs or evidence.
The 52-file M5 sorted path/blob manifest must retain SHA-256:

```text
cd8cd9623b59cbf03d96b6d92e99b50d833dc4bc1b6bf7479148c4f63df83294
```

The final report must state:

```text
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
```

The G2 package is a preflight only, as required. M6-G3 remains locked until the
M6-G2 local commit, clean worktree and empty index are verified.
