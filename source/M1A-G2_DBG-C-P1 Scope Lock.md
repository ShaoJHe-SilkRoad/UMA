# M1A-G2_DBG-C-P1 Scope Lock

## Authority and stop rule

This packet executes only **P1 — Obvious Defect Sweep, Basic Usability Closure, and Human Review Entry**.  It begins from accepted Task-B commit `85b430ca7df24f169191a53421ffc67c4dd8dde5` and stops after the P1 human-review candidate and guide are complete.  P2 and P3 are explicitly out of scope until separately accepted.

The authorized P1 commit message is:

```text
fix(uma): close first-pass usability defects
```

No history rewrite, broad staging, remote operation, release, notarization, or access to credentials, cookies, Keychain, browser data, or account mutation is permitted.

## Baseline observed 2026-07-18

| Item | Observed value |
| --- | --- |
| Branch | `main` |
| P1 starting commit | `85b430ca7df24f169191a53421ffc67c4dd8dde5` |
| `origin/main` | `cd62d4b235b5e78a9045a36909aa656948cf54ab` |
| Ahead/behind | `ahead 6` / no reported behind commits |
| Staged index | empty |
| Git whitespace check | passed before P1 edits |

## Preserved non-P1 worktree material

The pre-existing M1/M1-G5 changes and untracked material listed by the baseline audit are preserved and excluded from P1 staging unless a later line-level audit proves a specific P1 hunk is both necessary and separable.  In particular, workspace `Package.swift`, app-shell/menu-bar work, M1-G5 sources/tests/scripts, `.swiftpm/`, and the prior DBG-A evidence packet are not a P1 starting edit set.

## P1-owned edit set

P1 may change only the minimum app lifecycle, status item/panel, Codex session/connector, usage-store/freshness/snapshot, localization/accessibility/glass, package/launcher, focused test, and P1 documentation files required to close an observed usability defect.  The compact-header layout contract is P1-owned because it repairs verified title clipping at the fixed panel width.  All changes require a focused test and manual retest record in the P1 ledger.

## Candidate and safety invariants

- Candidate and launcher must be P1-owned, isolated from the dirty workspace, and use no credentials or account mutation.
- Human entry name is exactly `UMA0.9_Enter`; the candidate is launched without Terminal use.
- The candidate must maintain one monitor app, one status item, and at most one active owned app-server child.
- Temporary build state uses only P1-named workspace-local paths or the separately authorized P1 `/private/tmp` fallback paths.
- Appearance and accessibility settings are recorded before any bounded validation transition and restored exactly before P1 stops.
