# M1A-G2_DBG-C-P2 Visual Matrix

Fixture evidence is generated outside the repository under `/private/tmp/codexusage-p2-previews` and is intentionally not staged. It contains synthetic values only.

| State | EN | zh-Hans | Result / evidence |
|---|---:|---:|---|
| Light, collapsed | Pass | Pass | 740 × 804 fixture; complete `More info` row and no clipping |
| Light, expanded | Pass | Pass | 740 × 1552 fixture; Recent Tasks and Token Cost expand together |
| Light, settings | Pass | Pass | 740 × 860 fixture; settings overlays the permanent core and exposes no card-hiding switches |
| Dark, collapsed | Pass | Pass | Explicit dark color-scheme fixture; readable hierarchy and translucent card separation |
| Dark, expanded | Pass | Pass | Explicit dark color-scheme fixture; secondary cards remain legible |
| Fresh | Pass | Pass | Green text-and-dot state, `Synced HH:mm` |
| Refreshing with retained values | Pass | Pass | Last values remain visible; successful provider timestamp remains the sync authority |
| Stale | Pass | Pass | Red text-and-dot state, exact English `Outdated`; recovery actions remain available |
| Reconnecting / authorization recovery | Pass | Pass | Existing deterministic recovery presentation tests and rendered retained-data path |
| Finite five-hour | Pass | Pass | Five-hour remains finite and distinct; five macro segments render partial fill |
| Unlimited five-hour | Pass | Pass | Deterministic model fixture: seven-day first; five-hour infinity secondary with no bar |
| Low Pro / Prolite | Pass | N/A | Strict `<10%` red; `10%` blue |
| Low Plus | Pass | N/A | Strict `<20%` red; `20%` blue |
| Unknown plan / infinity | Pass | N/A | Never threshold-red |
| Normal detailed background | Pass | Pass | Blue detailed gradient fixture remains visible between cards |
| Bright detailed background | Pass | Pass | Light fixture maintains card readability without a full-panel opaque tint |
| Dark detailed background | Pass | Pass | Dark fixture maintains contrast without a second outer perimeter |
| Reduce Transparency | Contract pass | Contract pass | Native-host test verifies the accessibility branch; the system setting was not changed in this run |
| Increase Contrast | Source/semantic pass | Source/semantic pass | System colors and text labels remain semantic; the system setting was not changed in this run |
| Reduce Motion | Contract pass | Contract pass | AppKit applies final geometry immediately and does not run competing SwiftUI frame animation |

## Perimeter and material conclusion

The P1 outer SwiftUI tint and full-panel stroke are absent. The one AppKit material host owns the rounded surface. On macOS 26 the public `NSGlassEffectView` branch is active; earlier systems preserve the `NSVisualEffectView` fallback. Fixture images validate content hierarchy and clipping, while the native-host contract validates the AppKit relationship.

## Settings restoration

Observed starting state was Light, Reduce Transparency off, Increase Contrast off. No system appearance/accessibility setting was changed, so restoration was not required.
