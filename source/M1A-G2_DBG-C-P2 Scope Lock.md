# M1A-G2_DBG-C-P2 Scope Lock

## Locked baseline

- Accepted P1 commit: `f1da999cf518433d108867d14ea1476678911ebf`
- P1 commit message: `fix(uma): close first-pass usability defects`
- P2 branch: `codex/m1a-g2-p2`
- P2 isolated worktree: `/private/tmp/CodexUsageMonitor-P2`
- Human-review candidate: `/Users/juliushe/Desktop/UMA0.9_Review/CodexUsageMonitor.app`
- Launcher: `/Users/juliushe/Desktop/UMA0.9_Enter.app`
- Required P2 commit message: `fix(uma): repair human-reported panel and usage display`
- Push authority: none
- P3 authority: locked

The existing `/Users/juliushe/Desktop/CodexUsageMonitor` checkout is intentionally dirty. Its unrelated tracked and untracked M1/M1-G5 work is outside this gate and must remain untouched. All P2 implementation, tests, documentation, and commit work are isolated from the exact accepted P1 commit.

## Locked product repair

P2 is limited to the human-reported panel defects and their direct regression coverage:

1. Remove the duplicate full-panel contour.
2. Use the native macOS 26 translucent glass host without opaque SwiftUI panel tinting.
3. Keep the core usage summary permanently present.
4. Make settings reversible without geometry corruption.
5. Restore native macOS typography and a clear information hierarchy.
6. When five-hour usage is unlimited, present the seven-day quota first and the five-hour infinity state as dim secondary information without a dominant progress bar.
7. Hide Recent Tasks and Token Cost by default behind one disclosure labeled exactly `More info`.
8. Integrate refresh state into the header: green `Synced HH:mm`, red `Outdated`, and retained values during refresh. A successful provider capture timestamp is the display authority.
9. Use one refresh lane with 15-second visible and 30-second hidden cadence, an age-gated panel-open refresh, wake/reconnect/manual triggers, coalescing, backoff, and stale handling.
10. Give AppKit sole ownership of panel-frame animation, including Reduce Motion behavior.
11. Replace the quota bar with five stable macro segments, modest active/depleted weighting, accurate partial fill, and plan-aware low-quota red thresholds.

## Explicit exclusions

- No live Codex-account access or credential/token work.
- No push, pull request, release, or publication.
- No P3 work.
- No unrelated M1/M1-G5 cleanup.
- No screenshot capture in this run unless the user grants fresh, direct approval. The screenshot preflight was denied, so visual evidence is limited to source inspection, fixture rendering where available, and accessibility-tree observations.
- No temporary system appearance or accessibility-setting change is required for the initial repair.

## Evidence boundary

The P1 candidate was inspected through macOS Accessibility. It opened at `370 × 776`. Turning all three card switches off reduced the settings-open panel to `370 × 430`, then closing settings collapsed the panel to `370 × 135`. Closing and reopening the status panel preserved the broken `370 × 135` state. Re-enabling all three switches restored the candidate to `370 × 776`; the original user preference state was restored.

The system appearance observed before repair was Light with Reduce Transparency off and Increase Contrast off. No system setting was changed.
