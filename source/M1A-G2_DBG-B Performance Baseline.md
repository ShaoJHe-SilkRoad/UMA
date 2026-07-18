# M1A-G2_DBG-B Performance Baseline

## Environment

- macOS 26.5.2 (25F84), arm64
- Xcode 26.6 (17F113), macOS 26.5 SDK
- Task-B synthetic HOME, TMPDIR, Clang module cache, SwiftPM module cache, and
  scratch paths under `.build/m1a-g2-dbg-b-*`

## Construction baseline

| Check | Observation | Status |
| --- | --- | --- |
| Focused core compile/test | 16 tests in 4 suites completed in 0.590 s after a 19.12 s cold build | Passed |
| Connector/freshness focused test | 13 tests in 1 suite completed in 0.100 s after a 10.34 s incremental build | Passed |
| Coordinator burst | 50 callers invoked one provider operation | Passed |
| Local observer | Debounced burst at 200 ms; named-tail update and root recovery verified | Passed |
| Provider overload | Explicit-request-only bounded 30-to-300 s backoff | Passed |
| Repaired exact source snapshot regression | 60 tests in 8 suites, 3.808 s | Passed |
| Current-worktree regression | 101 tests in 13 suites, 4.009 s | Passed; includes preserved unrelated M1/M1-G5 WIP |
| Repaired candidate debug builds | App and PreviewRendererTool compiled through the exact-source test build | Passed |
| Repaired candidate release builds | App completed in 16.24 s; PreviewRendererTool completed in 1.27 s | Passed |
| Address Sanitizer focused matrix | 15 tests in `M1AG2ConnectorCoreTests`, 0.103 s after a 18.53 s sanitized build | Passed; no report emitted |
| Thread Sanitizer focused matrix | 15 tests in `M1AG2ConnectorCoreTests`, 0.108 s after a 16.91 s sanitized build | Passed; no report emitted |
| Static package | plist lint, strict deep codesign, no external package dependency, privacy/fixture scans | Passed |
| Compact-status repair regression | One focused test in the working tree and one in the exact source snapshot | Passed |
| Repaired candidate refresh exercise | 20 manual Refresh actions plus five bursts of five actions | Completed with one direct owned child retained |
| Repaired candidate recovery exercise | 10 owned-child terminations, each followed by one replacement direct child | Passed |
| Repaired candidate panel exercise | 50 open/close interactions | Passed |
| Repaired candidate continuous runtime | 30:39; final census had one candidate app, one status item, and one direct child | Passed |
| Native-glass accessibility matrix | Four fresh candidate launches plus live Light-to-Dark adaptation; panel remained 370 x 776 pt with sanitized ∞/ordinary seven-day presentation | Passed; original macOS settings restored |

These are construction-machine observations, not a user-facing performance
guarantee. No Task-C long-run stability or four-hour performance claim is made.

## Resource policy

The product retains one app-server child, one receive task, one client refresh
operation, at most one connector event consumer, at most one local observer,
and one local observer refresh task. Background freshness is conservative; no
timer/event path creates a second child or autonomous retry loop.

## Measurement boundary

The repaired temporary candidate now supplies bounded live UI and lifecycle
evidence, but this document does not claim a Task-C soak, event latency, or a
user-facing performance guarantee. During its 30:39 run the candidate app was
54,064 KiB RSS / 4.7% CPU at the first post-connect sample and 52,048 KiB /
3.8% at the final sample. The deliberately replaced owned child was 32,096 KiB
at the early sample and 32,848 KiB at the final sample; those child values are
not a leak comparison because ten recovery cycles intentionally replaced that
process. No monotonic app RSS growth was observed in this bounded run.
