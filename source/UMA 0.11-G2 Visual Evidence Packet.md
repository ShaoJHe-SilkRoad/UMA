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

The final source-state matrix is stored under:

`/private/tmp/uma-g2-final-evidence`

Its `manifest.tsv` records each image's SHA-256, pixel dimensions, and exact
renderer arguments. `provenance.txt` records committed HEAD/tree plus the
unstaged repair-diff SHA-256. `all-evidence-sha256.txt` indexes the other 84
payload files; its own SHA-256 is reported separately so the manifest is not
recursively self-referential.

The 61-image matrix covers:

- zero through eight providers;
- collapsed, one-expanded, and all-expanded states;
- ready, refreshing, stale, failed, warning, critical, exhausted, unavailable,
  unlimited, login-required, and extraction-failure states;
- Light and Dark over bright, dark, colorful, photographic, and flat
  wallpapers;
- Reduce Transparency, Increase Contrast, their combination, and Reduce Motion;
- English, Simplified Chinese, long copy, and large text;
- global, Codex, WorkBuddy disconnected, connected, sign-in, and
  unverified Settings;
- Regular and Minimalist Assistant layouts with one, two, and five rows;
- 0%, 56%, and 100% plus compact Credit values 999, 1.1k, 98.4k, and 999B.

Accepted-G1/current-G2 comparison images:

- `/private/tmp/uma-g2-final-evidence/side-by-side-main.png`
- `/private/tmp/uma-g2-final-evidence/side-by-side-settings.png`

## Physical review

The task-owned interactive renderer was launched without account access or
Desktop installation. Bounded Accessibility-API interaction proved Show All,
Hide All, one-provider disclosure, global Settings, provider navigation, and
Settings close/back actions. The AX tree exposed combined provider labels,
percentage/Credit values, freshness, Show/Hide action names, Agent Settings
actions, and the single Settings scroll-region identifier.

Tightly scoped physical captures include:

- `/private/tmp/uma-g2-final-evidence/physical-show-all.png`
- `/private/tmp/uma-g2-final-evidence/physical-hide-all.png`
- `/private/tmp/uma-g2-final-evidence/physical-expanded-one.png`
- `/private/tmp/uma-g2-final-evidence/physical-expanded-bottom.png`
- `/private/tmp/uma-g2-final-evidence/physical-settings-workbuddy-top.png`
- `/private/tmp/uma-g2-final-evidence/physical-settings-bottom.png`
- `/private/tmp/uma-g2-final-evidence/physical-native-panel.png`
- `/private/tmp/uma-g2-final-evidence/physical-keyboard-focus.png`
- `/private/tmp/uma-g2-final-evidence/physical-voiceover-focus.png`

Observed result: natural compact Settings height, bounded
scrolling for long WorkBuddy Settings, no stale hierarchy after provider
navigation, no clipped segmented option, one contour per component, compact
equal provider shells, and readable Light/Dark/CJK/large-text output. The
large-text pair uses a renderer-only 1.35x point-size layout stress without
changing the user's system text settings.

A separate task-owned native bundle captured the production
`AdaptivePanelMaterialHostView` at 370 x 200 over the current real desktop
background. The bright/dark/colorful/photographic matrix remains controlled
synthetic wallpaper stress evidence rather than a claim that the user's actual
wallpaper was changed.

Full Keyboard Access was originally off/mode 0, temporarily enabled through
System Settings for bounded Tab traversal, and restored off/mode 0. VoiceOver
was originally off, temporarily enabled through System Settings, advanced to
the candidate's Show Settings control, visibly captured, and restored off. The
two focus captures demonstrate transient system-owned focus contours rather
than a permanent component border.

## Verification

- Affected UMA 0.11 matrix: 39/39 PASS across 4 suites.
- Full suite: 304/304 PASS across 37 suites in 7.774 seconds.
- Debug: PASS.
- Release: PASS.
- Strict-concurrency Release with warnings as errors: PASS.
- Review-runtime startup proof: a fresh directory with no `work` child is
  created automatically and produces the default PNG; an invalid scenario
  exits 1 through the bounded diagnostic without an error escaping async main.
- Exact proprietary-serif availability remains the documented accepted risk;
  no private font or application dependency was admitted.
- Final package/privacy and commit-exact smoke remain downstream of fresh Git
  authority for the repair set.
