# UMA STAB-G1 QA Issue Ledger

Status: runtime and pre-commit qualification complete
Starting commit: `3bb03e865f460154a33b1c23c85496067eb48c05`
Starting tree: `510886c090e0b6641d5ad8ceddfc1b112cc758ea`

Generated images, runtime samples, and logs remain under `/private/tmp` and are
not repository artifacts.

## Issue register

### STAB-001 — Dark-mode white background regression

- First evidence: predecessor dark renderer and black-box views did not show an
  opaque white rectangle; the native-host path lacked explicit ownership.
- Severity: blocking regression lock.
- Root cause: adaptive backgrounds were split across view-specific layers.
- Repair: centralized card material with explicit reduced-transparency behavior.
- Focused retest: Light/Dark/Reduce Transparency renderer matrix.
- Affected regression: R1, R2.
- Final status: PASS — the 18-state renderer set and physical Dark/Light,
  Settings, Regular, and Minimalist checks show no opaque white backing.

### STAB-002 — Main-panel double border

- First evidence: SwiftUI always drew an outer stroke while macOS 26
  `NSGlassEffectView` also owned a native rim.
- Severity: major.
- Root cause: no host-versus-SwiftUI contour contract.
- Repair: production injects native-host ownership; native glass owns its rim,
  while fallback and opaque modes own one AppKit layer contour.
- Focused retest: native-glass contract and edge renderer inspection.
- Affected regression: R2, R5.
- Final status: PASS — native glass owns one rim; fallback and opaque hosts own
  one layer contour, with no second SwiftUI outer stroke.

### STAB-003 — Provider-card double border

- First evidence: `LocalLiveProviderCard` stacked thin material,
  `GlassCardBackground`, and a second stroke.
- Severity: major.
- Root cause: three same-geometry background/edge owners.
- Repair: one centralized `GlassCardBackground`.
- Focused retest: contour ownership source test and two-provider render.
- Affected regression: R2, R14.
- Final status: PASS — source ownership and two-provider edge renders show one
  provider-card contour.

### STAB-004 — Assistant double border

- First evidence: source audit found one Assistant stroke; the native shadow
  could make it look heavier but no second source owner was present.
- Severity: regression guard.
- Root cause: not reproduced as a duplicate owner.
- Repair: retain one row stroke and centralize its contrast width token.
- Focused retest: Regular and Minimalist edge inspection.
- Affected regression: R2, R6.
- Final status: PASS — Regular Assistant renders retain one clear row contour.

### STAB-005 — Minimalist capsule double border

- First evidence: source audit found one capsule stroke.
- Severity: regression guard.
- Root cause: not reproduced in the accepted capsule.
- Repair: preserve one centralized Assistant contour and accepted geometry.
- Focused retest: Light/Dark/contrast Minimalist renders.
- Affected regression: R2, R6.
- Final status: PASS — Light, Dark, low-usage, and contrast renders retain one
  fixed-geometry capsule contour.

### STAB-006 — Inconsistent font families

- First evidence: English `UsageDesign.font` discarded requested weights and
  forced rounded regular; Chinese collapsed the hierarchy into two STHeiti names.
- Severity: major.
- Root cause: call-site sizes were centralized only partially and the family
  helper had incorrect language/weight behavior.
- Repair: centralized system-safe semantic roles using SF Pro/system CJK
  cascade, with visible call sites migrated off the old helper.
- Focused retest: typography role and source-ownership tests.
- Affected regression: R1–R8 visual surfaces.
- Final status: PASS — visible hierarchy now uses centralized semantic system
  roles; the only retained risk is the documented Anthropic-family fallback.

### STAB-007 — Claude font unavailable or unsafe dependency

- First evidence: Anthropic fonts exist only inside Claude.app; no verified
  redistribution authority or complete Chinese glyph coverage was found.
- Severity: allowed exact-font limitation.
- Root cause: requested reference font is not package-safe.
- Repair: `CLAUDE TYPOGRAPHY FALLBACK USED`; no copied font and no Claude path.
- Focused retest: package source/string/font audit.
- Affected regression: package portability.
- Final status: accepted nonblocking risk — package/source scans contain no
  copied font and no Claude application dependency.

### STAB-008 — Chinese fallback mismatch

- First evidence: explicit STHeiti Light/Medium mapping differed from the system
  UI cascade and flattened hierarchy.
- Severity: major.
- Root cause: hard-coded legacy CJK family.
- Repair: native system font cascade with PingFang SC resolution.
- Focused retest: CoreText Chinese fallback plus zh-CN renderer matrix.
- Affected regression: localization and accessibility.
- Final status: PASS — CoreText resolves a real CJK fallback and physical
  Simplified Chinese Settings/rendered surfaces remain readable.

### STAB-009 — Numeric baseline or jitter

- First evidence: scattered rounded fonts and repeated numeric declarations.
- Severity: major.
- Root cause: no shared value roles and uneven tabular-figure ownership.
- Repair: value/menu/Assistant roles plus tabular digits.
- Focused retest: measured `111%`/`888%` equality and value renderer states.
- Affected regression: R6–R8, R11.
- Final status: PASS — tabular-digit width tests and all percentage/Credit
  renderer states show stable baselines without value-dependent resizing.

### STAB-010 — Settings scrolling regression

- First evidence: physical AX tree exposed a Settings scroll area over the main
  panel's second scroll area.
- Severity: blocking.
- Root cause: Settings was an overlay inside an always-scrolling root, and
  WorkBuddy presence forced the inner scroll branch.
- Repair: non-scrolling clipped base while Settings is open; one bounded native
  vertical scroll with size-based bounce suppression when all content fits.
- Focused retest: source contract, AX tree, top/bottom keyboard scroll.
- Affected regression: R3.
- Final status: PASS — the Settings AX tree exposes one bounded scroll owner;
  collapsed content does not need to scroll and expanded content reaches bottom.

### STAB-011 — Extended Settings blank-space regression

- First evidence: connected Settings content could overflow its visual surface
  while the underlying main-panel content remained too visually prominent.
- Severity: major.
- Root cause: the unbounded natural-layout candidate ignored the intended height
  cap, and the overlay surface did not sufficiently separate foreground content.
- Repair: one height-bounded scroll owner, size-based bounce suppression, a
  readability tint inside the existing glass owner, and a noninteractive dimmed
  main-panel context while Settings is open.
- Focused retest: collapsed/expanded Settings renderer and physical fit.
- Affected regression: R3, R5.
- Final status: PASS — connected/disconnected, top/bottom, EN/zh-CN, and
  collapsed/expanded evidence shows no blank overflow or unreachable controls.

### STAB-012 — Manual density fails to disable Automatic

- First evidence: no new failure; accepted preference implementation separates
  automatic and manual states.
- Severity: regression guard.
- Root cause: historical defect only.
- Repair: preserved.
- Focused retest: existing density tests and manual transitions.
- Affected regression: R4.
- Final status: PASS — 20 density switches and 10 Automatic/manual transitions
  preserved the selected manual preference; full regression suite passed.

### STAB-013 — Forced Minimalist preference loss

- First evidence: no new failure; resolution is derived and does not rewrite the
  stored manual choice.
- Severity: regression guard.
- Root cause: historical defect only.
- Repair: preserved.
- Focused retest: 4→5→4 and 0–8 provider matrix.
- Affected regression: R4, R6.
- Final status: PASS — deterministic 0–8-provider coverage and repeated
  Automatic/manual transitions preserve the manual preference across forcing.

### STAB-014 — Codex environment/auth regression

- First evidence: accepted predecessor and baseline connector tests pass.
- Severity: blocking regression lock.
- Root cause: none introduced by the visual/resource repair.
- Repair: connector, HOME, executable resolution, and child ownership untouched.
- Focused retest: focused connector suites and normal-HOME package smoke.
- Affected regression: R9.
- Final status: PASS — 20 read-only Manual Refresh actions and owned-child
  termination/recovery retained one normal-HOME Codex connector and child.

### STAB-015 — Synthetic WorkBuddy data leakage

- First evidence: predecessor package had no saved record or fixture file;
  preview helpers are reachable only through explicit renderer construction.
- Severity: blocking package/privacy guard.
- Root cause: prior package scripts lacked a strict file allowlist.
- Repair: final package helper rejects record/fixture/log/evidence files and
  audits exact contents.
- Focused retest: package-contract test and normal no-record launch.
- Affected regression: R10, R11.
- Final status: PASS — candidate/package-source audits contain no seeded record
  or generated review fixture; the final helper repeats the exact allowlist.

### STAB-016 — WorkBuddy timer/read multiplication

- First evidence: accepted scheduler suite proves one timer and one in-flight
  read; no source regression found.
- Severity: blocking regression lock.
- Root cause: none introduced.
- Repair: preserved source-layer ownership.
- Focused retest: Auto Refresh suite and bounded runtime counts.
- Affected regression: R12.
- Final status: PASS — scheduler/coalescing regression tests prove one timer and
  one in-flight read. The current isolated account session was unavailable, so
  no new live WorkBuddy source claim is made.

### STAB-017 — Main/Assistant provider-set mismatch

- First evidence: both surfaces derive from shared presentation; WorkBuddy is
  intentionally filtered only where its admission contract requires.
- Severity: blocking regression lock.
- Root cause: no new mismatch found.
- Repair: shared store remains authority.
- Focused retest: zero/Codex/WorkBuddy/both/failure/removal matrix.
- Affected regression: R14.
- Final status: PASS — shared-presentation/admission matrices cover zero,
  Codex-only, WorkBuddy-only, both, failure, and removal without divergence.

### STAB-018 — Assistant focus/position regression

- First evidence: lifecycle source is bounded, but unchanged store emissions
  rebuilt hosting content, repaired frames, and reordered the panel.
- Severity: major.
- Root cause: missing semantic equality and visibility guards.
- Repair: content updates only for changed cards/density, frames only for changed
  geometry, and ordering only on hidden-to-visible transitions.
- Focused retest: redraw ownership test and lifecycle runtime.
- Affected regression: R13.
- Final status: PASS — 100 show/hide cycles, 10 position restores, five
  deterministic frame simulations, and no-op update guards showed no drift or
  focus stealing.

### STAB-019 — 0.10.1 visual-parity regression

- First evidence: historical oracle is compact with a single contour; the
  predecessor shows duplicate provider/Settings borders and a two-scroll AX tree.
- Severity: major.
- Root cause: later feature layers acquired separate material/edge owners.
- Repair: centralized typography/contours, natural first height, adaptive Settings.
- Focused retest: matched historical/predecessor/final black-box evidence.
- Affected regression: R1–R8.
- Final status: PASS — matched historical, predecessor, and repaired renders
  preserve compact proportions while removing the later duplicate layers.

### STAB-020 — Launch/open performance regression

- First evidence: baseline static audit found redundant Assistant reconstruction;
  latency baseline is recorded separately under `/private/tmp`.
- Severity: major.
- Root cause: unconditional hosting-view replacement/frame repair/order-front.
- Repair: coalesced store updates, no-op Assistant guards, and reuse of the
  already-configured main-panel tree for repeated selection of the same
  Assistant provider.
- Focused retest: launch, panel-open, Settings-open, and Assistant-show samples.
- Affected regression: R5, R13.
- Final status: PASS — warm panel open, Settings open, and density-switch
  medians meet or beat the accepted predecessor. Assistant show remains below
  one-half second and its absolute delta is within UI-automation stabilization
  noise rather than a user-visible regression.

### STAB-021 — Resource growth

- First evidence: Codex local activity created one file descriptor and dispatch
  source for every historical JSONL file.
- Severity: major.
- Root cause: unbounded watch-set enumeration.
- Repair: 24-file low-latency watch cap plus one 15-second metadata-only
  reconciliation timer that promotes an older resumed session.
- Focused retest: bounded watch-set/resume test and descriptor/runtime samples.
- Affected regression: R9, R13.
- Final status: PASS — the accepted predecessor opened approximately 1,629
  descriptor rows and climbed from about 187 MB to 347 MB RSS during the
  comparison; the repaired candidate settled to 82 descriptor rows, 0–0.1%
  idle CPU, approximately 62–78 MB RSS, 5–7 threads, and one owned child.

### STAB-022 — Package contains generated/private material

- First evidence: predecessor package was clean, but its helper did not enforce
  a complete file allowlist, manifest digest, or explicit generated-artifact scan.
- Severity: blocking package guard.
- Root cause: incomplete final-package audit automation.
- Repair: commit-exact helper with exact file allowlist, dependency, font,
  fixture/record/log/evidence, secret-like string, symlink, signature,
  architecture, provenance, and path-independent manifest checks.
- Focused retest: package-contract test and final package audit.
- Affected regression: R10 and delivery.
- Final status: PASS — helper contract enforces the exact allowlist and all
  prohibited-material scans; commit-exact packaging repeats these gates after
  the authorized local commit.

## Typography risk

The sole permitted PASS WITH RISKS condition remains the exact font limitation:
Anthropic Sans is not admitted for redistribution. All stability, functional,
privacy, resource, and package gates must still pass without qualification.
