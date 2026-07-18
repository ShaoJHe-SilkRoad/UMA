# M1A-G2_DBG-B Glass Compatibility Report

## Public API decision

The Task-B material host uses only public AppKit APIs from the macOS 26.5 SDK:
`NSGlassEffectView`, `contentView`, `cornerRadius`, and `.regular`. It uses
`NSVisualEffectView` only as the macOS 14–25 fallback and an opaque system
window background when Reduce Transparency is active. No private backdrop,
filter, dynamic-selector, or accessibility-bypass API is used.

| Environment | Material branch | Contract status |
| --- | --- | --- |
| macOS 26+ / normal transparency | One `NSGlassEffectView`, rounded clipped content | Deterministic active-branch test plus Light and Dark fresh-launch inspection passed |
| macOS 14–25 / normal transparency | One `.underWindowBackground` `NSVisualEffectView` fallback at 0.44 | Source contract tested; older-runtime execution pending |
| Reduce Transparency | Opaque `NSColor.windowBackgroundColor`; no material view | Source contract and fresh Dark/Reduce Transparency launch passed |
| Increase Contrast / Reduce Motion | Preserve normal geometry and border; use only conditional semantic accessibility behavior | Fresh Dark/Reduce Transparency/Increase Contrast launch passed; Reduce Motion remains source/fixture-only |

## Frozen visual invariants

- Panel frame: `370 × 776 pt`
- Corner radius: `28 pt`, continuous
- Status-bar gap and screen margin: `8 pt`
- Content insets: horizontal `16 pt`, top `14 pt`, bottom `12 pt`
- Stack spacing: `12 pt`
- Normal outer panel border: existing 0.8-pt gradient stroke

The dirty 836-pt panel, provenance footer, broad M1-G3 card changes, altered
outer border, and M1-G5 package split are excluded from Task-B staging.

## Verification boundary

`M1AG2DBGNativeGlassContractTests` proves the public host relationship and
frozen geometry; the repaired exact source snapshot additionally built, tested,
and packaged with strict deep codesign. A direct authorization then covered the
global setting matrix. Four fresh candidate launches covered Light/normal,
Dark/normal, Dark/Reduce Transparency, and Dark/Reduce Transparency/Increase
Contrast. The candidate also changed from Light to Dark in place, demonstrating
automatic appearance adaptation. Each panel-only capture showed the frozen
370 × 776 pt frame, retained layout, an authoritative ∞ five-hour row, and one
ordinary 66–67% seven-day row. All captures are temporary, sanitized, and
excluded from Git.

Before the matrix, Appearance was Light, Reduce Transparency was off, and
Increase Contrast was off. After it, the values were respectively Light, off,
and off again; restoration was queried through System Settings and matched the
original values exactly. No other macOS setting was changed.

The focused test target must depend on the committed `CodexUsageMonitor`
executable target so its `@testable` import resolves in an archive-only build.
This is a one-line Task-B manifest dependency; the dirty M1-G5 AppShell target
split and every other `Package.swift` hunk remain excluded.

The amended archive passed the focused native-glass contract test and the full
suite. No glass or UI source changed during this repair, so the completed
Light/Dark and accessibility matrix remains valid without repetition.
