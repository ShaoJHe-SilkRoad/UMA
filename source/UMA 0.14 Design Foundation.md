# UMA 0.14 Design Foundation

Status: accepted B0 planning foundation

Theme: `Aesthetic — Real Mac App, Usage Experience, User Structure, confirmed 0.13 debt repair`

## Product principles

1. **Remaining quota first.** Answer “How much usable quota is left, and what is becoming the limiting factor?” before exposing implementation detail.
2. **One truth, many surfaces.** Main window, Quick Panel, Settings, and Desktop Assistant consume the same provider-neutral resolved state.
3. **Truthful uncertainty.** Exact, estimated, stale, unavailable, and action-required information are never collapsed into a misleading percentage.
4. **Native Mac behavior.** Windows, Settings, commands, focus, restoration, keyboard operation, and accessibility follow platform conventions.
5. **Progressive disclosure.** Normal users see state and remedy. Protocol codes, paths, generations, and bridge details remain in bounded diagnostics.
6. **Restrained presentation.** Use hierarchy, typography, spacing, and semantic color before adding more cards, glass, gradients, or decoration.
7. **Protected provider behavior.** Aesthetic work must not rewrite quota semantics, privacy boundaries, provider transport, Maximum Decrement, or Claude one-shot Accuracy Sync.
8. **Direct distribution first.** Preserve the working 0.13 feature set. App Store compatibility is a separate architecture track where sandbox redesign is required.

## Information architecture

### Main application window

The main window is the canonical daily-use surface.

- **Overview**: limiting/actionable provider summary followed by compact summaries of all admitted providers.
- **Providers**: complete provider inventory, including disabled/setup-required/unavailable states, with drill-down for quota windows, source, freshness, reset, and repair.
- **Activity**: include only when source data is truthful, privacy-qualified, and useful across admitted providers. Do not create a decorative empty destination for B0.
- **Diagnostics entry**: a bounded support path from each provider detail, not a first-class dashboard of implementation codes.

The full window should use available desktop width without reproducing the current 370-point vertical stack at a larger scale.

### Native Settings window

Initial five-pane structure:

1. **General** — language, launch/login behavior, main-window and Dock policy.
2. **Providers** — provider inventory, setup/connection, provider-specific source and refresh controls, privacy summary, repair actions.
3. **Appearance** — system/light/dark behavior if user-selectable, information density, and display preferences.
4. **Desktop Assistant** — enablement, always-on-top, Regular/Minimalist/Automatic density, and reset position.
5. **Privacy & Data** — consent, source boundaries, retention, cache/reset actions, and support diagnostics.

Do not create a separate Refresh pane until meaningful provider-neutral scheduling controls exist. Do not create an Advanced pane merely to preserve implementation boundaries; bounded diagnostics belong under Privacy & Data or provider details until a real set of advanced user controls emerges.

### Menu Bar Quick Panel

The status-item surface becomes a Quick Panel, not a miniature dashboard.

- limiting/actionable value when comparison is truthful;
- compact rows for admitted providers;
- refresh action appropriate to context;
- Open UMA;
- Settings;
- Show/Hide Assistant;
- no embedded full provider configuration;
- no full activity/cost dashboard.

Raw WorkBuddy credits must not be compared with normalized percentages unless the connector supplies a truthful, same-scope normalized fraction.

### Desktop Assistant

The Assistant remains an optional persistent glance surface.

- Consume the same provider-neutral resolved state.
- Preserve always-on-top, universal drag, click preservation, one contour, Light/Dark, Regular, Minimalist, and Automatic density.
- Automatic density uses full Minimalist at five or more active agents.
- Keep it visually quiet and glanceable; no animated toy behavior and no provider setup inside the panel.
- A provider selection may open the matching provider detail in the main app.
- Because the panel is intentionally nonactivating, every action must also have an ordinary keyboard/menu/main-window equivalent. Decide before implementation whether Assistant cards remain pointer-accessible or become display-only.

## Provider product state model

`Exact`, `Estimated`, `Stale`, `Unavailable`, `Needs Attention`, and `Error` are not one mutually exclusive enum. They describe different axes.

Conceptual `ProviderProductState`:

| Axis | Required values/meaning |
|---|---|
| Identity | provider ID, display name, admitted support class, plan when safely available |
| Availability | supported and configured, setup available, disabled, unsupported, unavailable |
| Connection | connected, disconnected, connecting, signed out, permission required, failed |
| Quota windows | provider-owned window identity, remaining value, native unit, reset when present |
| Precision | exact or estimated; exact has no prefix, estimated retains `≈` |
| Freshness | current, aging, stale, expired, unknown |
| Source | concise user-facing source name plus bounded technical detail |
| Health | healthy, action required, temporarily unavailable, failed |
| Action | optional concrete user action; absent when no action can improve the state |
| Diagnostics | content-free reason code and technical detail available only on demand |

Visible vocabulary:

- **Exact**: precision/provenance. Usually a compact detail badge rather than repeated beside every value.
- **Estimated**: always visible through `≈` and an accessible textual label.
- **Stale**: freshness; may coexist with Exact or Estimated.
- **Unavailable**: no usable value. Never implies zero.
- **Needs Attention**: only when a concrete user action exists.
- **Error**: avoid as the primary user-facing label. Prefer “Couldn’t refresh,” “Sign in required,” or “Companion update required”; retain the code in diagnostics.

Examples:

- `82% remaining · Exact · Updated 2m ago`
- `≈82% remaining · Estimated`
- `Stale exact reading · Updated yesterday`
- `Unavailable · Sign in required`

Provider transport states such as `generationMismatch`, `extensionBackgroundNotAcknowledged`, and `routeRejected` never appear in ordinary UI.

## Main panel concept

### Full presentation

1. **Limiting/action row** — show only when quantities are comparable or an action truly blocks a provider.
2. **Provider summary grid/list** — provider identity, dominant remaining value, window label, precision, freshness when useful, and action only when necessary.
3. **Provider detail** — all admitted quota windows, resets, source, connection, privacy summary, last successful update, and bounded repair.

One dominant remaining value per provider should lead. Precision and freshness remain visible but secondary. Color cannot be the only status signal.

### Zero-provider and unavailable behavior

- Keep admitted providers visible as inventory where useful rather than filtering every unavailable snapshot away.
- Distinguish unsupported, disabled, not configured, signed out, permission required, temporarily unavailable, and failed.
- “No active Agents” is not sufficient when the product knows a more truthful state.
- Unsupported Cursor and Kimi must not be shown as available setup targets.

## Minimalist concept

“Minimalist” remains the protected Desktop Assistant density mode. The Quick Panel is not renamed Minimalist.

The compact provider row should contain:

- provider identity;
- dominant remaining value;
- estimated marker when applicable;
- a small textual/action indicator only when intervention is required.

It should omit expanded source, reset, and diagnostic prose while retaining complete VoiceOver semantics. Values remain tabular. Full and Minimalist presentations must be projections of the same product state, not separate logic.

## Native Mac application model

Use incremental AppKit/SwiftUI evolution.

### Required shell changes

- Expand `AppShellCoordinator` to own a `MainWindowController`, `SettingsWindowController`, `StatusBarController`, `DesktopAssistantPanelController`, and one command router.
- Narrow `StatusBarController` to status-item and Quick Panel ownership.
- Add a normal titled, resizable, closable, miniaturizable main window with frame autosave.
- Add a conventional Settings window backed by shared settings models/coordinators.
- Keep `TransparentUsagePanelController` transient and nonactivating.
- Keep the Assistant a separate nonactivating panel.
- Closing the main window leaves provider monitoring and the optional Assistant running; Dock/application reopen shows the main window.
- Quick Panel and Assistant are excluded from normal main-window restoration.
- Make activation policy and `LSUIElement` consistent. Permanent Dock presence versus an accessory app with a summonable normal window is a Founder decision.
- Preserve launch-at-login behavior; hidden login launch, if desired with a Dock app, needs an explicit product contract.

Do not replace AppKit everywhere or rewrite the application as a ground-up SwiftUI `App` unless implementation evidence later proves incremental controllers unsafe.

## Menu and command model

Candidate native menu contract:

- **UMA**: About UMA, Settings (`⌘,`), Services, Hide, Quit (`⌘Q`).
- **Refresh**: Refresh Current Provider (`⌘R`) when focus/selection makes “current” unambiguous; Refresh All Providers (`⇧⌘R`) with privacy-aware enablement.
- **View**: Show Dashboard, Show Quick Panel, Show/Hide Desktop Assistant.
- **Window**: standard macOS window commands.

Do not assign `⌘1`/`⌘2` until stable numbered destinations exist. Do not expose an inert ThreadOS menu item: reserve the command namespace and integration seam in architecture only. One command router must serve menus, shortcuts, status item, and window controls.

## Design system

### Typography

- Use system semantic/relative text styles for navigation, controls, dense body copy, and accessibility scaling.
- Reserve serif for deliberate branded/display roles, not every small label.
- Preserve system tabular digits for quota values.
- Establish a readable minimum supporting size; critical information must not depend on scale-to-fit.

### Layout and hierarchy

- One surface hierarchy: window background → section → provider row/card.
- Avoid card-inside-card and nested glass for individual data fragments.
- Define a consistent spacing scale and align numbers across providers/windows.
- Use one intentional contour owner per window/card.

### Materials, contours, and shadows

- Use material on top-level surfaces where it clarifies hierarchy.
- Provide opaque system-color fallback under Reduce Transparency.
- Keep shadows restrained and functional.
- Avoid excessive gradients, provider-color washes, giant marketing typography, and debug-dashboard styling.

### Color and icons

- Use semantic system colors for state.
- Limit provider color to a small identity accent.
- Pair all status colors with text/icon semantics.
- Use platform symbols consistently and provide accessible labels.

### Appearance modes

- Qualify Light and Dark independently.
- Preserve current Reduce Transparency and Increase Contrast adaptation.
- Centralize a motion policy used by panel presentation, provider expansion, switches, and future transitions.
- Under Reduce Motion, replace nonessential animation with immediate state changes.

## Accessibility plan

1. Replace fixed production typography with semantic/relative styles and qualify real app surfaces at accessibility sizes.
2. Establish full keyboard traversal and visible focus for the main window, Settings, provider actions, and refresh.
3. Provide a keyboard/menu equivalent for every Assistant pointer action, or formally make the Assistant display-only.
4. Keep VoiceOver labels explicit about remaining semantics, window, precision, freshness, and required action.
5. Announce refresh completion/failure without exposing raw provider data or technical codes.
6. Never encode connection or severity by color alone.
7. Test English and Simplified Chinese at large sizes without truncating provider/action meaning.
8. Test Light/Dark, Increase Contrast, Reduce Transparency, Reduce Motion, VoiceOver order, and Full Keyboard Access.
9. When deep-linking to a provider or Settings pane, move focus to the destination and restore focus on close.
10. Keep destructive and privacy-affecting actions explicit and confirmation-backed.

## Technical-debt plan

### Required before or during 0.14 surface implementation

1. **Multi-subscriber state publication** — prevent Registry, Settings, main window, and other consumers from displacing one another.
2. **Typed provider/anchor diagnostics** — expose content-free load/rejection/repair reasons to the product-state reducer.
3. **Injected preference authority** — eliminate writes to real standard defaults from isolated tests.
4. **Single release version/build authority** — populate main app, Host, Companion, manifest, and runtime metadata from one input.
5. **Explicit wake policy** — define privacy-safe freshness behavior without a second scheduler or unconsented provider reads.
6. **Incremental Claude ownership extraction** — separate source adapters, anchor/state reduction, and Accuracy Sync orchestration while preserving transport/privacy contracts.
7. **Observable-state test synchronization** — replace affected fixed-yield/sleep assumptions.
8. **Bounded status-line/translocation qualification** — required before the UI claims a specific installed-source fault or health state.

### Later or separately qualified

- robust multi-pair estimation;
- estimator shadow validation;
- mixed-model calibration after reproduction;
- App Store sandbox redesign;
- internal compatibility-name migration;
- cross-provider Activity/History if truthful data exists.

## Required backend refactors

| Refactor | Why required | User/product benefit | Risk if omitted | Scope |
|---|---|---|---|---|
| Multi-subscriber connector streams | New main/Settings surfaces add consumers to a currently single-continuation path. | Stable, consistent state everywhere. | A later surface silently disconnects an earlier one. | Connector publication and registry tests only; no transport rewrite. |
| Provider product-state reducer | Existing presentation has useful fields but no complete provider-neutral support/connection/action model. | Consistent wording, actions, and inventory across all surfaces. | Each view reinvents health logic and leaks implementation states. | New derived models over existing truth. |
| Typed anchor/load diagnostics | Empty store and rejected store are indistinguishable. | Truthful health and repair guidance. | UI claims inactivity when local state was rejected. | Smart-anchor store plus content-free diagnostics. |
| Settings model decomposition | A large embedded view owns provider and global structures. | Native Settings with consistent provider presentation and testability. | Old panel boundaries become permanent architecture. | Shared view models/coordinators; preserve provider operations. |
| Shell/window/command decomposition | Status bar currently acts as application shell. | Native windows, menus, focus, restoration, and keyboard behavior. | Continued transient-panel dependence and command duplication. | AppKit controllers and command router. |
| Preference injection | Some code bypasses injected defaults. | Deterministic tests and safe settings state. | Tests pollute real preferences. | Preferences only. |
| Version/build authority | Release identity is manually duplicated. | Reliable 0.14 packaging and support diagnostics. | App/Host/Companion version drift. | Build/package metadata inputs, no identity change. |
| Wake contract | Current source expresses contradictory inert and refresh-capable paths. | Predictable freshness after wake without privacy regression. | Misleading freshness or accidental unconsented reads. | Lifecycle policy and tests; provider-owned scheduling retained. |
| Claude connector extraction | One type owns too many independent concerns. | Safer state UI evolution and bounded diagnosis. | Surface work increases coupling and regression risk. | Incremental internal extraction, not provider redesign. |

## Unnecessary refactors

- Mass rename `CodexUsageMonitor` to UMA across targets and support paths.
- Ground-up provider connector or registry rewrite.
- Replacing AppKit everywhere.
- Rewriting quota parsing, remaining semantics, or Maximum Decrement.
- Rebuilding the accepted Claude Safari Host/Companion architecture.
- Merging Claude Code and Claude Desktop source contracts.
- Restoring recurring Safari automation.
- Weakening privacy allowlists for diagnostics.
- Adding a database merely to create an Activity destination.
- Automatic deletion of commit-exact release packages.
- Blocking the UI migration on estimator research.

## ThreadOS seam

ThreadOS may coordinate development but is not a 0.14 runtime dependency.

- Reserve a future command/menu namespace and protocol seam in architecture.
- Do not show a disabled/inert menu item to ordinary users.
- Do not ship a hidden service, background dependency, or placeholder network behavior.
- Any product integration requires a later explicit user action and accessibility contract.

## Milestones

Use five implementation milestones after B0 rather than B0 plus ten narrow ceremony stages.

### UMA014-M1 — Native shell and lifecycle

Main window, Settings window foundation, command router, activation/Dock decision, close/reopen/restoration contract. No provider behavior change.

### UMA014-M2 — Provider product state and inventory

Multi-subscriber publication, provider-neutral state reducer, truthful unavailable/setup/action states, typed diagnostics, focused regressions.

### UMA014-M3 — Main window and Quick Panel experience

Overview/provider hierarchy, limiting-state rules, compact Quick Panel, Full/Minimalist projections, semantic typography and density.

### UMA014-M4 — Settings, Assistant integration, and accessibility

Five-pane Settings, provider setup consistency, Assistant deep links/equivalent actions, focus, keyboard, VoiceOver, motion, contrast, localization.

### UMA014-M5 — Debt closure and release-candidate hardening

Preference isolation, wake policy, version authority, bounded Claude extraction, timing-test repair, full regression, direct-distribution package qualification. App Store redesign remains a separate future track.

## Founder decisions required

Maximum seven decisions are deliberately left for Founder arbitration before implementation crosses the relevant boundary:

1. **Application presence:** permanent Dock app, or menu-bar utility with a summonable normal main window?
2. **Status-item value:** limiting comparable provider, selected provider, compact icon only, or another explicit non-aggregate contract?
3. **Main navigation:** sidebar, toolbar destinations, or single Overview with provider detail navigation?
4. **Activity scope:** omit Activity until cross-provider truthful data exists, or include a clearly source-limited destination?
5. **Unavailable providers:** always show admitted inventory, or allow user-selected hiding while preserving setup/health discoverability?
6. **Assistant interaction:** pointer-selectable with main-window deep link plus keyboard equivalents, or formally display-only?
7. **Diagnostics placement:** provider detail disclosure under Privacy & Data, or a later dedicated Advanced pane once controls justify it?

## Readiness decision

`READY FOR 0.14 IMPLEMENTATION: YES`, subject to Founder decisions being resolved no later than the milestone that consumes them. M1 may begin only after an explicit `START / 开始`; this B0 task does not implement it.
