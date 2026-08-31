# UMA 0.14 B0 Product Map

Status: accepted B0 planning baseline

Task: `GN-UMA014-B0-01`

Target: `0.14.0` (`Aesthetic`)

Frozen source baseline: `0.13.0` at commit `f6dd617bb736d49b444dda4945d55e5b4606c915`, tree `16223ec6b1e3b3c1bf5a80191c97e9887498d622`

## Baseline and authority

UMA 0.13.0 is the released, notarized, production baseline. This record maps that exact source. It does not reopen the release, change product behavior, or treat historical plans as newer than the final signed provenance.

Protected installed artifacts:

- Production application: `/Users/juliushe/Desktop/UMA_0.13.0.app`
- Production Safari Host: `/Users/juliushe/Applications/UMA Safari Bridge.app`
- Rollback: `/Users/juliushe/Desktop/UMA_0.11.app`

The 0.14 development line is isolated on branch `codex/uma-0.14-aesthetic`. Production packages, provider sessions, signing assets, and the 0.13 branch are outside this B0 task.

## Product identity

UMA 0.13 is a macOS menu-bar usage monitor with three user-visible surfaces:

1. a transient menu-bar panel that currently carries both quick usage and detailed configuration;
2. an optional floating Desktop Assistant;
3. provider-specific setup and diagnostics embedded in the menu panel.

There is no canonical main application window and no native Settings window. The application uses an AppKit lifecycle and SwiftUI-hosted content rather than a SwiftUI `WindowGroup` application model.

## Admitted provider set

| Provider | 0.13 status | Primary product role |
|---|---|---|
| Codex | admitted | usage and reset windows through the established connector |
| Claude | admitted | Local Smart sources plus explicit one-shot Safari Accuracy Sync |
| WorkBuddy | admitted | provider-specific usage/credit presentation |
| Google Antigravity | admitted | read-only usage presentation through the accepted connector |
| Cursor | unsupported | scaffolding/order constants do not constitute admission |
| Kimi | unsupported | no production runtime admission |

Future ordering constants or historical source-admission experiments do not expand the production provider set.

## Usage semantics

- All displayed percentages mean **remaining usage**.
- `82%` means exactly 82 percent remaining.
- `≈82%` means an estimated 82 percent remaining.
- Missing, unsupported, signed-out, stale-without-value, and error states are never normalized to `0%`.
- Maximum Decrement remains the accepted protection against implausible downward movement.
- Provider values are resolved into shared provider-neutral presentation before the panel or Assistant renders them.

## Runtime ownership map

### Application lifecycle

- `CodexUsageMonitorApp` starts `NSApplication`, installs an application delegate, and sets accessory activation policy.
- `LSUIElement` and the runtime activation policy jointly define the menu-bar-only shell.
- `AppShellCoordinator` is the natural composition root but does not yet own a main-window or Settings-window controller.
- Closing transient UI does not terminate monitoring. Reopening the application primarily restores menu-bar visibility rather than a main window.
- Launch at Login is governed through the existing `SMAppService` path and must remain separate from any future Dock/window policy.

### Status item and quick panel

- `StatusBarController` owns the status item, title/icon state, panel presentation, contextual commands, and shell coordination responsibilities.
- `TransparentUsagePanelController` owns a nonactivating transient panel and its close/escape/outside-click behavior.
- `UsagePanelView` renders header state, provider cards, expanded details, recent activity/cost sections, footer actions, and embedded Settings.
- The panel is 370 points wide and may grow to approximately 776 points high; it has become a dashboard and Settings container rather than a strictly quick surface.
- The status-item text can show the primary connector percentage without an explicit provider label. It is not an aggregate and must not be presented as one in 0.14.

### Settings

- `UsageSettingsCard` is a large SwiftUI view embedded inside the transient panel.
- It owns global settings, provider-specific branches, connection/setup controls, privacy explanations, source details, and diagnostic language.
- `AgentSettingsCoordinator` and provider settings models mediate runtime actions, but the visual hierarchy exposes different structures for different providers.
- Preferences are distributed across `AppStorage`, `UserDefaults`, and typed settings models. One injected preference authority does not yet cover every testable setting.

### Desktop Assistant

- `DesktopAssistantPanelController` owns the always-on-top nonactivating panel, positioning, one native drag recognizer, click arbitration, show/hide, and mode changes.
- `DesktopAssistantView` consumes the shared resolved presentation and does not implement an independent usage source.
- Regular and Minimalist are the only Assistant density modes. Automatic density forces the full Minimalist presentation at five or more active agents (`>4`).
- The accepted single-contour, universal-drag, control-click, Light/Dark, and always-on-top contracts are protected.

### Shared usage truth

- `UsageStore` is the central presentation store and publication boundary.
- `SharedUsageCardPresentation` and related provider-neutral models carry remaining value, precision/estimate state, freshness, reset/source information, and severity.
- `AgentConnectorRegistry` aggregates connector streams. Individual connectors own provider transport and refresh lifecycle; the registry is not a provider polling engine.
- Missing values are represented as unavailable (`—`), not numeric zero.

### Refresh and wake ownership

- Manual refresh is coalesced through the existing store/registry path.
- Provider connectors own their supported schedules and transport behavior.
- Claude Safari Accuracy Sync is explicit and one-shot; retired recurring Safari automation remains off.
- `UsageStore.handleApplicationWake()` is currently a no-op, while an unused `CodexWakeRefreshObserver` describes a different intent. The 0.14 plan must define one privacy-safe wake contract before promising wake-driven freshness.
- A second global scheduler must not be added.

### Claude source architecture

- Claude Code terminal/IDE surfaces can use the official status-line relay and privacy-bounded local activity metadata.
- Claude Desktop uses the separately authorized estimated cache source; it is not falsely treated as an exact per-response status-line source.
- Safari Accuracy Sync uses the immutable production Host and Companion architecture, the production App Group, owned temporary-tab receipts, sanitized exact anchors, and explicit user consent.
- Browser Sync does not restore continuous automatic Safari polling.

### Design system

- `DesignSystem.swift` owns panel dimensions, typography, spacing, radii, materials, contours, shadows, and accessibility-sensitive material fallbacks.
- Current visual language uses glass/material surfaces, restrained blue accent, serif-led labels, tabular numeric values, and one intentional contour owner.
- Reduce Transparency, Increase Contrast, and Light/Dark adaptation have established implementations.
- Production typography still relies heavily on fixed point sizes. Large-text renderer fixtures do not prove real production semantic scaling.
- Reduce Motion is not applied consistently to provider expansion and custom Settings switches.

### Packaging and release ownership

- The mutable UMA app and immutable Safari Host/Companion are produced by the split production packaging pipeline.
- Production identities are `com.silkrd.uma`, `com.silkrd.uma.safarihost`, `com.silkrd.uma.ClaudeBrowserCompanion`, and App Group `group.com.silkrd.uma.bridge`.
- Version `0.13.0` is duplicated in the package script, signing plist templates, and extension manifest rewrite. This is a confirmed source-of-truth defect for the next release line.
- Commit/build-qualified external package retention is intentional provenance, not repository clutter to purge automatically.
- Internal names such as `CodexUsageMonitor` remain compatibility names for Swift targets, executables, and support directories; a mass rename is not required for 0.14.

## Current surface assessment

### Confirmed UX problems

1. No canonical main window or native Settings window.
2. The quick panel owns too much information and configuration.
3. The header reports active-provider count instead of the limiting or actionable state.
4. Configured-but-unavailable providers can disappear, preventing truthful differentiation among disabled, unsupported, signed-out, setup-required, and failed states.
5. Provider settings structures are inconsistent and leak implementation terminology.
6. Fixed production typography does not establish a semantic text-scaling contract.
7. Reduce Motion behavior is inconsistent.
8. There is no application-wide command, focus, and keyboard-navigation model.
9. Assistant card selection lacks an ordinary keyboard path; equivalent actions must exist in the main application even if the Assistant remains nonactivating.

### Design preferences, not defects

- Permanent Dock presence versus a menu-bar utility with a summonable real window.
- Sidebar versus toolbar navigation.
- Exact use of serif typography, material, radii, and provider accent colors.
- Whether Activity/History is a first-class destination.
- Whether a cross-provider limiting state is emphasized visually or textually.

### Not actually problems

- Shared usage truth is not duplicated between panel and Assistant.
- Missing usage is not converted to zero.
- The Assistant drag/click/single-contour repair remains intact.
- Quick-panel close/escape/outside-click behavior is intentional.
- AppKit and SwiftUI coexistence is not itself a defect.
- Existing provider-card nesting and outer-contour ownership already prevent the previously reported double-border pattern.

## Direct distribution and App Store capability

| Capability | Classification | Reason |
|---|---|---|
| Main presentation surfaces and shared state | `DIRECT_AND_APP_STORE_COMPATIBLE` | Native AppKit/SwiftUI UI can operate in either channel. |
| Existing provider connectors as a group | `DIRECT_ONLY_CURRENTLY` | Current direct-distribution contracts include external tools and local filesystem sources. |
| Claude local filesystem/status-line sources | `REQUIRES_SANDBOX_REDESIGN` | Current bounded home-directory and external executable integration is not a drop-in App Sandbox contract. |
| Independently installed immutable Safari Host | `REQUIRES_SANDBOX_REDESIGN` | Distribution and inter-app architecture need a separately qualified App Store design. |
| Future ThreadOS integration | `UNKNOWN` | No runtime product contract exists in 0.14. |

0.14 must not weaken admitted 0.13 functionality to claim theoretical App Store parity.

## Protected 0.13 behavior

- Four admitted providers only: Codex, Claude, WorkBuddy, Antigravity.
- Cursor and Kimi remain unsupported.
- Remaining-percentage semantics, exact/estimated notation, and missing-not-zero.
- Maximum Decrement.
- One Desktop Assistant Minimalist Mode and automatic full Minimalist at more than four active agents.
- Provider-neutral shared resolved usage truth.
- Privacy allowlists and sanitized provider boundaries.
- Claude one-shot Accuracy Sync with no automatic continuous Safari refresh.
- Immutable Safari Host/Companion and owned-tab safety architecture.
- Assistant always-on-top, drag, click preservation, one contour, Regular/Minimalist, and Light/Dark behavior.

## B0 conclusion

The safest 0.14 direction is an incremental native Mac application migration: preserve AppKit lifecycle and panels, add explicit main-window and Settings controllers, centralize commands and provider product state, narrow the quick panel, and decompose the existing Settings/Claude ownership without rewriting provider truth or transport.
