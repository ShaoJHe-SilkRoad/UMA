# M1A-G2_DBG-C-P2 Human Feedback Ledger

| ID | Human-reported issue | P1 reproduction / source evidence | P2 acceptance |
|---|---|---|---|
| HF-01 | Panel appears double bordered | Native glass host contour plus a full-panel SwiftUI rounded stroke; Differentiate Without Color adds another dashed full-panel stroke | Exactly one panel contour, owned by the native host |
| HF-02 | Material looks opaque instead of like native glass | Full-panel `BalancedPanelTint` overlays high-opacity light/dark color; cards add material, tint, stroke, and shadow | Native macOS 26 glass remains visibly translucent; no opaque full-panel SwiftUI tint |
| HF-03 | Settings can collapse the app | Three persisted card toggles can remove all primary content; measured collapse from `370 × 776` to `370 × 135` | Core quota summary cannot be removed; settings remain usable and reversible |
| HF-04 | Repeated toggles corrupt layout | SwiftUI preferred-height animation and AppKit frame animation both drive geometry | One AppKit frame-animation owner; cancellation/replacement and Reduce Motion behavior |
| HF-05 | Typography and hierarchy feel non-native | Custom Chinese typeface and rounded system face override native weight behavior; competing large values | Native system typography with quota-first hierarchy |
| HF-06 | Unlimited five-hour quota dominates useful weekly data | Five-hour row is ordered first and renders infinity with a fully filled blue bar | Seven-day quota first; five-hour infinity is dim secondary text with no dominant bar |
| HF-07 | Recent Tasks and Token Cost crowd the default panel | Both cards are visible by default and independently configurable | Both are hidden by default under one `More info` disclosure |
| HF-08 | Refresh/reset information is duplicated and unclear | Generic header status plus a separate reset/update footer | Integrated `Synced HH:mm` / `Outdated` state using provider capture authority; no duplicate footer |
| HF-09 | Refresh feels stale | P1 defaults are 120 seconds visible and 900 seconds hidden; panel open is not an age-gated trigger | 15 seconds visible, 30 seconds hidden, immediate age-gated panel-open, wake/reconnect/manual through one coordinator |
| HF-10 | Panel resizing is jumpy | SwiftUI transitions and AppKit `setFrame(animate:)` compete without cancellation | Smooth, top-anchored, single-source resizing; immediate when Reduce Motion is enabled |
| HF-11 | Quota bar is visually coarse and threshold color can mislead | One capsule bar; unlimited treated as full; no plan-aware threshold model | Five macro segments, stable total width, accurate partial fill, correct Pro/Prolite and Plus thresholds, unknown/unlimited never false-red |

## Evidence note

The request refers to five screenshots, but the supplied attachment directory contained only the pasted request text. Screenshot capture was not performed because the required current approval preflight was denied. Human observations are therefore preserved as requirements, while reproduction evidence in this ledger is accessibility-tree and source based.
