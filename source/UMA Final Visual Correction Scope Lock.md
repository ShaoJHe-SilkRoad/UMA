# UMA Final Visual Correction Scope Lock

## Frozen baseline

- Base commit: `c81fb749359719d1b22fd12e076ad0948fc20385`
- Branch: `codex/m1a-g2-p2`
- Isolated worktree: `/private/tmp/CodexUsageMonitor-P2`
- Original checkout: preserved with unrelated WIP untouched
- Human review candidate: `/Users/juliushe/Desktop/UMA0.9_Review/CodexUsageMonitor.app`
- Finder launcher: `/Users/juliushe/Desktop/UMA0.9_Enter.app`
- Premature account/debug probe: stopped; its evidence is non-governing

## Exact scope

1. Remove the redundant AppKit panel shadow when native macOS glass owns the
   exterior rim and clip the native glass's out-of-bounds Light-mode halo,
   while retaining the shadow for fallback and Reduce Transparency branches.
2. Drive disclosure text, arrow, accessibility label, accessibility value, and
   expanded state from one Boolean source: More info / Less info and
   更多信息 / 收起信息.
3. Register official Roboto Regular, Medium, and Bold before UI construction;
   route application-owned Latin/numeric text through centralized semantic
   roles; use explicit PingFang SC cascade fallback for Simplified Chinese.
4. Package the fonts, OFL license, and provenance with the review candidate.
5. Use one 16-point exterior inset on every side. Size collapsed and expanded
   panels to their presented quota/task rows so top and bottom chrome remain
   equal without changing card heights or internal padding.

Connector behavior, account data, quota semantics, refresh cadence, soak,
fault injection, P3, push, release, notarization, and deployment are locked.

## Exterior surface map

`NSPanel` (clear, borderless; shadow disabled for native glass)
→ `AdaptivePanelMaterialHostView` (clear; continuous radius; clips the native
glass halo at the sole exterior boundary)
→ one `NSGlassEffectView` on macOS 26, one `NSVisualEffectView` fallback, or one
opaque accessibility background
→ clear rounded content clipper
→ clear `NSHostingView`
→ clear SwiftUI root
→ inset internal glass cards.

The two perceived before-state contours were the intended native
`NSGlassEffectView` rim and the redundant outer boundary produced by
`NSPanel.hasShadow` plus the native glass halo extending beyond the host.
Native glass retains its rim; its AppKit shadow is disabled and its external
halo is clipped. Fallback/opaque branches keep one system shadow.

## Three-family defect ledger

- Exterior: native glass rim plus AppKit shadow formed two perimeter contours
  and could retain stale shadow geometry during a 0.18-second resize. Human
  Light-mode review then identified the remaining out-of-bounds native halo;
  the host now clips it while preserving the accepted Dark glass style.
- Exterior spacing: fixed 402/776-point frames centered the unchanged content
  and left oversized top/bottom chrome. The exterior now uses a uniform
  16-point inset and content-count sizing (360–740 points) without altering
  cards, typography, icons, or information hierarchy.
- Disclosure: expanded state retained the collapsed More info / 更多信息 label
  and exposed generic On/Off accessibility values.
- Typography: all application text used system fonts; no Roboto files,
  CoreText registration, semantic role map, explicit CJK cascade, license, or
  package copy existed.
