# UMA 0.14 QA Issue Ledger

Status: M1 execution complete; B0 planning evidence retained

Current task: `GN-UMA014-M1-01`

Planning baseline task: `GN-UMA014-B0-01`

Baseline: UMA 0.13.0 commit `f6dd617bb736d49b444dda4945d55e5b4606c915`, tree `16223ec6b1e3b3c1bf5a80191c97e9887498d622`

## Ledger rules

- B0 records evidence and implementation gates; it does not repair production code.
- `CONFIRMED` means frozen-source evidence proves the issue.
- `REPRODUCTION_REQUIRED` means a bounded live or deterministic reproduction is required before repair.
- `PROTECTED` means changing the contract requires separate evidence and authorization.
- An issue closes only after its implementation milestone supplies focused old-fail/new-pass evidence plus affected regression coverage.
- Aggregate test counts do not substitute for product, accessibility, lifecycle, privacy, or release evidence.

## Product and UX issues

| ID | Severity | State | Finding | Required proof to close | Target |
|---|---|---|---|---|---|
| UMA014-UX-01 | Major | CLOSED / M1 | The 0.13 baseline had no canonical main application window or native Settings window. | Native singleton Main and Settings windows; real close/reopen/quit lifecycle; menu/shortcut tests; content-free machine diagnostic; bounded physical macOS UI qualification. | M1 |
| UMA014-UX-02 | Major | CONFIRMED / OPEN | Quick Panel owns dashboard, activity/cost, provider detail, and configuration. | Quick Panel contains only glance/frequent actions; full details and setup are reachable in native windows; no duplicated usage logic. | M3 |
| UMA014-UX-03 | Major | CONFIRMED / OPEN | Header emphasizes active-provider count rather than limiting/actionable quota. | Deterministic limiting comparison that excludes incomparable native units; truthful attention hierarchy; zero-provider and unavailable fixtures. | M2–M3 |
| UMA014-UX-04 | Major | CONFIRMED / OPEN | Unavailable snapshots can be filtered away, obscuring disabled/setup/signed-out/failure states. | Complete admitted-provider inventory and explicit support/availability/connection/action classifications; Cursor/Kimi remain unsupported. | M2 |
| UMA014-UX-05 | Moderate | CONFIRMED / OPEN | Provider Settings structures differ and ordinary UI leaks implementation terminology. | Shared provider settings schema; bounded diagnostics disclosure; no bridge/App Group/generation codes in normal UI. | M4 |
| UMA014-UX-06 | Major | M1 COMMAND MODEL CLOSED / M4 ACCESSIBILITY OPEN | M1 now has one application-wide command router and native menu/shortcut model; deeper Full Keyboard Access and focus qualification remains in M4. | Native menu graph and live shortcut routing passed in M1; Full Keyboard Access traversal and focus restoration/deep-link tests remain required in M4. | M4 |
| UMA014-UX-07 | Major | CONFIRMED / OPEN | Fixed point typography and preview-only scaling do not prove production accessibility scaling. | Semantic/relative production typography; English/Chinese accessibility-size qualification without loss of meaning. | M3–M4 |
| UMA014-UX-08 | Moderate | CONFIRMED / OPEN | Reduce Motion is not consistently applied to provider expansion and Settings switches. | Central motion policy; deterministic reduced-motion behavior; no nonessential transitions when enabled. | M4 |
| UMA014-UX-09 | Moderate | DECISION_REQUIRED / OPEN | Assistant card tap has no ordinary keyboard path because the panel is intentionally nonactivating. | Founder chooses pointer/deep-link plus equivalent keyboard command, or display-only; tests preserve drag/click/nonactivation. | M4 |

## Technical issues

| ID | Severity | State | Finding | Required proof to close | Target |
|---|---|---|---|---|---|
| UMA014-TD-01 | Critical | CONFIRMED / OPEN | Claude connector stores one stream continuation; later UI subscribers can displace earlier consumers. | Multi-subscriber tests with Registry, Settings, main window, cancellation, duplicate delivery, and deterministic termination. | M2 |
| UMA014-TD-02 | Major | CONFIRMED / OPEN | Smart-anchor load rejection collapses to an empty store without content-free reason. | Typed load outcomes for absent, unsafe, corrupt, incompatible, rewrite failed, repaired, and accepted; privacy scan. | M2 |
| UMA014-TD-03 | Major | CONFIRMED / OPEN | `UsageStore.setLanguage` bypasses injected defaults and can mutate process preferences in tests. | Injected preference authority; old-fail/new-pass pollution test; clean defaults before/after parallel suites. | M5 |
| UMA014-TD-04 | Major | CONFIRMED / OPEN | Fixed `Task.yield`/sleep synchronization appears throughout affected tests. | Replace affected waits with observable-state/task-start handshakes; individual, parallel, and load stability without larger sleeps. | M2–M5 |
| UMA014-TD-05 | Major | CONFIRMED / OPEN | Wake path is contradictory: inert store handler, unused observer, and connector wake triggers. | One documented privacy-safe wake contract; no duplicate scheduler, provider discovery, consent bypass, or refresh burst. | M5 |
| UMA014-TD-06 | Major | CONFIRMED / OPEN | Version/build is duplicated across package script, three plists, and manifest rewriting. | One source populates main app, Host, Companion, manifest, and runtime metadata; mismatch rejection tests. | M5 |
| UMA014-TD-07 | Major | CONFIRMED / OPEN | Claude connector owns too many independent domains in one large type. | Incremental extraction with parity tests for source selection, anchor reduction, Accuracy Sync orchestration, privacy, and shared presentation. | M2–M5 |
| UMA014-TD-08 | Moderate | REPRODUCTION_REQUIRED / OPEN | Effective Claude status-line scope may differ from the hard-bound user settings path. | Content-free reproduction across supported active surfaces and precedence classes; no prompts/session content captured. | M5 or later |
| UMA014-TD-09 | Moderate | REPRODUCTION_REQUIRED / OPEN | Translocated launch may persist an ephemeral relay path. | Signed candidate reproduction proving canonical versus translocated behavior; repair only if reproduced. | M5 or later |
| UMA014-TD-10 | Moderate | REPRODUCTION_REQUIRED / OPEN | Same family-set key may conceal changed mixed-model weighting. | Deterministic estimator fixtures or bounded requalification; fail closed until accepted. | Separate estimator task |

## Protected behavior guards

| ID | State | Contract | Regression evidence required in every affected milestone |
|---|---|---|---|
| UMA014-GUARD-01 | PROTECTED | Codex, Claude, WorkBuddy, and Antigravity are the admitted providers; Cursor/Kimi remain unsupported. | Provider registry, ordering, settings inventory, and unsupported-state tests. |
| UMA014-GUARD-02 | PROTECTED | Percentages mean remaining; exact is `82%`, estimated is `≈82%`; missing/error/unsupported never become zero. | Shared value/presentation fixtures and accessibility labels. |
| UMA014-GUARD-03 | PROTECTED | Maximum Decrement remains unchanged. | Existing deterministic quota movement tests. |
| UMA014-GUARD-04 | PROTECTED | One Assistant Minimalist Mode; more than four active agents forces full Minimalist. | Existing density contract plus new shared-state surface parity. |
| UMA014-GUARD-05 | PROTECTED | Main window, Quick Panel, Settings, and Assistant consume provider-neutral shared truth. | Cross-surface parity test; no connector construction inside views. |
| UMA014-GUARD-06 | PROTECTED | Privacy allowlists and sanitized source boundaries remain strict. | Secret/raw-content scans and exact source allowlist tests. |
| UMA014-GUARD-07 | PROTECTED | Assistant universal drag, click preservation, one contour, always-on-top, Light/Dark, Regular/Minimalist remain accepted. | Focused Assistant contracts and bounded Human interaction check when its view changes. |
| UMA014-GUARD-08 | PROTECTED | Claude Accuracy Sync remains explicit and one-shot; no automatic continuous Safari refresh. | Scheduler/consent tests and source audit. |
| UMA014-GUARD-09 | PROTECTED | Immutable Safari Host/Companion and owned temporary-tab safety are not redesigned by aesthetic work. | Package identity, tab ownership, cleanup, and protocol regression only when touched. |
| UMA014-GUARD-10 | PROTECTED | Claude Code and Claude Desktop retain distinct exact/estimated source semantics. | Source selection, precision, and fallback-state tests. |

## Design and accessibility gates

| Gate | Acceptance requirement |
|---|---|
| IA-01 | Main window, Quick Panel, Settings, and Assistant have non-overlapping primary responsibilities. |
| IA-02 | Provider details use one shared conceptual schema: identity, status, source, setup, quota, action, privacy, diagnostics. |
| STATE-01 | Precision, freshness, availability, connection, and health remain orthogonal; implementation codes stay in diagnostics. |
| STATE-02 | Limiting-provider logic compares only compatible normalized quantities. |
| VISUAL-01 | One surface hierarchy and one contour owner; no nested glass/card decoration for each datum. |
| VISUAL-02 | Light/Dark/Increase Contrast/Reduce Transparency pass independently. |
| A11Y-01 | Semantic text scales in production; no critical meaning truncates in English or Simplified Chinese. |
| A11Y-02 | Every main/Settings action has keyboard access and visible focus. |
| A11Y-03 | VoiceOver exposes provider, remaining semantics, window, precision, freshness, and action. |
| A11Y-04 | Reduce Motion suppresses all nonessential application animations. |
| A11Y-05 | State is never communicated by color alone. |

## App architecture gates

| Gate | Acceptance requirement |
|---|---|
| SHELL-01 | `AppShellCoordinator` is the explicit composition root for main window, Settings, status item, Assistant, and commands. |
| SHELL-02 | `StatusBarController` no longer owns full application navigation/settings responsibilities. |
| SHELL-03 | Main window close, reopen, restoration, Dock/application activation, launch at login, and quit contracts are deterministic. |
| SHELL-04 | Quick Panel and Assistant retain their accepted nonactivating behavior and do not enter main-window restoration. |
| CMD-01 | One command router backs menu, shortcuts, status item, and window actions; shortcut meaning is focus-aware. |
| THREADOS-01 | ThreadOS remains an inert documented seam, not a visible placeholder or runtime dependency. |
| STORE-01 | Direct distribution remains fully supported; App Store-incompatible sources are classified rather than silently removed. |

## Milestone exit evidence

### M1 — Native shell and lifecycle

- main-window and Settings-window controller tests;
- activation policy/`LSUIElement` contract;
- close/reopen/quit/restoration and launch-at-login tests;
- native menu and shortcut tests;
- shell smoke with provider reads disabled;
- no provider/source diff.

#### `GN-UMA014-M1-01` execution record

- one `AppShellCoordinator` owns Main, Settings, Status Item / Quick Panel, Assistant, and application commands;
- one shared `UsageMonitorRuntime` / `UsageStore` is attached to all four presentation surfaces;
- ordinary launch is a normal Dock / Cmd-Tab application; verifier modes remain accessory-only;
- Main and Settings are retained singletons with safe frame restoration; closing either is not quitting;
- Dock/application activation reopens the canonical `UMA` Main window without duplication;
- UMA, Refresh, View, and disabled ThreadOS menus route through shell actions; ThreadOS runtime activity is zero;
- focused native-shell and product-isolation verification: 23/23 passed;
- affected shell, presentation, Assistant, Maximum Decrement, and multi-provider verification: 76/76 passed;
- final deterministic verification: 938/938 UI tests plus 56/56 bridge tests passed;
- the isolated unsigned `UMA 0.14 Dev.app` machine diagnostic passed native lifecycle and 50/50 Quick Panel toggles with provider startup disabled;
- bounded physical macOS UI qualification passed canonical title, Overview / Providers, Settings, Quick Panel, close/reopen, Cmd-comma, Cmd-1, Cmd-2, disabled ThreadOS, and Cmd-Q;
- no provider connector, Safari Host / Companion, authentication, privacy, Maximum Decrement, or release package source changed.

### M2 — Provider product state and inventory

- old-fail/new-pass multi-subscriber tests;
- provider-state reducer fixtures across admitted/unsupported/setup/signed-out/stale/error cases;
- exact/estimated/missing-not-zero parity;
- typed anchor diagnostic tests;
- privacy allowlist audit.

### M3 — Main window and Quick Panel

- surface responsibility/visibility tests;
- limiting comparison and incomparable-unit tests;
- Full/Minimalist shared-state parity;
- production semantic text/layout checks;
- Light/Dark and zero-provider fixtures;
- bounded Human UX validation.

### M4 — Settings, Assistant, accessibility

- five-pane Settings navigation and provider schema tests;
- keyboard/focus/VoiceOver/Full Keyboard Access evidence;
- Reduce Motion/Transparency/Contrast evidence;
- English/Chinese large-text evidence;
- Assistant drag/click/contour/density regression and equivalent-action proof.

### M5 — Debt closure and release-candidate hardening

- preference isolation;
- explicit wake policy;
- single version/build authority;
- affected timing tests stable individually, in parallel, and under load;
- bounded Claude ownership extraction parity;
- one final deterministic full suite and independent examination;
- direct-distribution package/signing qualification under a separately authorized release goal.

## Founder decision ledger

| Decision | Required by | Options to arbitrate | Status |
|---|---|---|---|
| FD-01 Application presence | M1 | permanent Dock app / accessory app with summonable normal window | RESOLVED — normal Dock / Cmd-Tab app |
| FD-02 Status-item value | M3 | limiting comparable provider / selected provider / icon only / explicit alternative | OPEN |
| FD-03 Main navigation | M1–M3 | sidebar / toolbar / Overview-first drill-down | RESOLVED FOR M1 — Overview / Providers sidebar; M3 expansion remains bounded |
| FD-04 Activity scope | M3 | omit until cross-provider truth / explicitly source-limited Activity | OPEN |
| FD-05 Unavailable-provider visibility | M2 | always visible inventory / user-selected hiding with discoverability | OPEN |
| FD-06 Assistant interaction | M4 | pointer deep-link plus equivalents / display-only | OPEN |
| FD-07 Diagnostics placement | M4 | provider disclosure under Privacy & Data / later Advanced pane | OPEN |

## B0 examinations

| Role | Evidence contract | Verdict |
|---|---|---|
| Product / IA Examiner | ownership map, hierarchy, surface responsibilities, state vocabulary, Founder decisions | PASS FOR B0 |
| macOS Architecture Examiner | lifecycle, AppKit/SwiftUI migration, windows, commands, refresh ownership, distribution feasibility | PASS FOR INCREMENTAL MIGRATION |
| Technical Debt Auditor | exact 18-claim arbitration and required/unnecessary backend changes | PASS WITH REPRODUCTION GATES |
| UX / Accessibility Examiner | problem/preference/non-problem split, design system, keyboard/focus/motion/scaling | PASS FOR B0 |
| Repo / Release Baseline Guard | frozen commit/tree, release artifacts, remotes, isolated branch/worktree, hygiene | PASS AFTER ISOLATED WORKTREE CREATION |

The roles used one frozen-source evidence baseline and divided responsibility rather than duplicating a full-repository scan.

## B0 close condition

B0 closes when:

- these four planning records are the only repository changes;
- classifications and protected contracts agree across records;
- no 0.15 material is fabricated;
- independent staged review finds no product/runtime/package mutation;
- at most one local documentation commit is created;
- worktree is clean and index empty afterward.

No M1 work begins without an explicit Founder `START / 开始`.
