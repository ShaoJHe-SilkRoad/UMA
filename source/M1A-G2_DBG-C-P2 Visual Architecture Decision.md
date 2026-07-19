# M1A-G2_DBG-C-P2 Visual Architecture Decision

## Decision

Use one native AppKit material host as the panel surface, one unconditional SwiftUI core-usage region, one transient `More info` disclosure for secondary information, and one AppKit owner for outer-window geometry.

## Surface and contour

`AdaptivePanelMaterialHostView` owns the rounded native surface and its single contour. The SwiftUI root contributes content only: it does not add a full-panel tint or a second full-panel stroke. Cards use restrained translucent separation without competing outer contours.

On macOS 26, the native `NSGlassEffectView` is the authority. Earlier systems retain the established `NSVisualEffectView` fallback. Accessibility settings continue to select the system-appropriate material behavior.

## Information architecture

The header and core quota summary are permanent. The settings view cannot hide them. Secondary Recent Tasks and Token Cost content begins collapsed and is controlled by one disclosure whose English label is exactly `More info`. Disclosure state is session-local rather than a persisted layout preference, preventing stale defaults from collapsing or unexpectedly expanding future launches.

For an unlimited five-hour entitlement, the validated seven-day quota is the primary row. The five-hour state follows as subdued infinity metadata with no progress bar. Finite quota rows use the same five-segment model.

## Refresh presentation

The provider's successful `capturedAt` timestamp is the authority for a successful sync label. Refreshing retains the last accepted values. Fresh successful state is green and reads `Synced HH:mm`; stale/error state is red and reads `Outdated`. Reset timing stays adjacent to the quota it describes, eliminating the separate duplicated footer.

All refresh causes enter the existing coordinator lane. The production cadence is 15 seconds while visible and 30 seconds while hidden. Opening the panel requests an immediate refresh only when the provider snapshot is old enough. Wake, reconnect, provider events, timers, and manual refresh remain coalesced and honor backoff/stale behavior.

## Geometry

SwiftUI reports semantic target heights without animating the root frame. `TransparentUsagePanelController` is the only outer-frame animator. A new request cancels/replaces the prior animation, preserves the top edge while visible, and invalidates the shadow after completion. Reduce Motion applies the final frame immediately.

## Quota visualization

The bar has five logical 20-point macro segments. Segment gaps and the overall width are stable. Active/depleted weighting is modest and normalized inside the fixed available width; it never changes the bar's total bounds. The current segment supports fractional fill.

Low-quota color is red only when:

- Pro or Prolite remaining quota is strictly below 10%.
- Plus remaining quota is strictly below 20%.

Equality stays blue. Unknown plans remain blue. Unlimited rows never use threshold red.
