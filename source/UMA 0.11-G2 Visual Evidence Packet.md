# UMA 0.11-G2 Visual Evidence Packet

Date: 2026-07-27

## Evidence boundary

All synthetic and physical evidence is task-owned. No installed Desktop app was
replaced, no provider was added, and no account, credential, cookie, token, or
private Claude asset was read. Generated images remain outside Git under
`/private/tmp`.

## Ownership result

| Component | Material owner | Contour owner | Shadow owner | Contrast behavior | Transparency fallback |
|---|---|---|---|---|---|
| Production panel | `AdaptivePanelMaterialHostView` | Native host | Native host | Strengthens the same contour | Public opaque fallback |
| Renderer panel | `BalancedPanelTint` | SwiftUI fallback | None | Strengthens the same inset contour | Public opaque fallback |
| Provider card | `GlassCardBackground` | One inset contour | One restrained card shadow | Same contour, increased line width | One semantic fill |
| Expanded details | Owning provider card | Owning provider card | Owning provider card | Inherited | Inherited |
| Settings | One `GlassCardBackground` | Settings card | Settings card | Same contour | One semantic fill |
| Assistant row | One row surface | One inset capsule contour | None | Same contour | One semantic fill |

The Settings root cause was the full provider tree rendered at 14% opacity
behind the Settings card. G2 replaces that tree with the compact header-only
backdrop. The bright card rim came from the combination of a high-opacity white
layer, centered stroke, and shadow; G2 lowers edge mass and uses `strokeBorder`.

## Typography result

- Exact `Anthropic Serif`: unavailable through a registered, licensed,
  package-safe source.
- Label fallback: public macOS system serif design.
- Simplified Chinese: native public CoreText cascade; verified non-LastResort
  glyph resolution and punctuation coverage.
- Exact values: system tabular sans.
- Technical diagnostics: system monospaced design.
- No font file, `Font.custom`, Claude application path, or runtime dependency
  is admitted.

## Deterministic render matrix

Representative evidence:

- `/private/tmp/uma-g2-zero-light.png`
- `/private/tmp/uma-g2-codex-light-v2.png`
- `/private/tmp/uma-g2-workbuddy-only-dark.png`
- `/private/tmp/uma-g2-two-zh-dark-v2.png`
- `/private/tmp/uma-g2-eight-collapsed-light-v2.png`
- `/private/tmp/uma-g2-eight-expanded-dark-v2.png`
- `/private/tmp/uma-g2-codex-stale.png`
- `/private/tmp/uma-g2-codex-refreshing.png`
- `/private/tmp/uma-g2-settings-light.png`
- `/private/tmp/uma-g2-settings-contrast-dark.png`
- `/private/tmp/uma-g2-assistant-regular-two.png`
- `/private/tmp/uma-g2-assistant-minimal-two-dark.png`
- `/private/tmp/uma-g2-assistant-minimal-eight.png`
- `/private/tmp/uma-g2-assistant-100-contrast.png`

The matrix covers zero, one, two, and eight providers; Codex-only,
WorkBuddy-only, mixed and synthetic providers; collapsed and expanded states;
Light, Dark, Reduce Transparency, Increase Contrast and Reduce Motion; English
and Simplified Chinese; stale/refreshing states; Settings; and fixed Regular
and Minimalist Assistant geometry.

## Physical review

The task-owned interactive renderer was launched without account access.
Bounded interaction opened Settings, closed Settings, and collapsed an expanded
WorkBuddy card. Tightly scoped captures:

- `/private/tmp/uma-g2-physical-two-agent.png`
- `/private/tmp/uma-g2-physical-settings.png`
- `/private/tmp/uma-g2-physical-dark-accessibility.png`

Observed result: readable Light/Dark text, perceptible background, one contour
per component, distinct status color, compact equal provider shells, attached
WorkBuddy detail, compact single-shell Settings, and no clipping or overlap.
Source accessibility contracts and the full regression suite preserve button,
Tooltip, VoiceOver, selected-window, and Assistant semantics.

## Verification

- Post-review G2 plus WorkBuddy focused matrix: 26/26 PASS.
- Affected G1/G2/stability matrix: 46/46 PASS across 5 suites.
- Full suite: 300/300 PASS across 37 suites.
- Debug: PASS.
- Release: PASS.
- Strict-concurrency Release with warnings as errors: PASS.
- Visual examiner result: PASS WITH RISKS solely because the exact requested
  proprietary serif is unavailable through a package-safe admitted source.
