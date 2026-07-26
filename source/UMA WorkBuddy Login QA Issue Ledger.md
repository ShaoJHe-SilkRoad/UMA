# UMA WorkBuddy Login QA Issue Ledger

Version: 1.0
Goal: M2WLOGIN-G1

## WBLOGIN-001 — WorkBuddy login settings overflow

- Severity: major during implementation
- First evidence: the first Light renderer showed the Settings content using an
  unconstrained ideal width; long login copy and the labeled segmented picker
  extended outside the 306-point Settings card.
- Root cause: the expanded WorkBuddy login section introduced a horizontal
  minimum larger than the Settings content proposal, while the existing
  adaptive container was optimized for shorter sections.
- Repair: use a fixed 278-point content proposal for the WorkBuddy-login
  ScrollView, separate the picker label from its segmented control, make
  confirmation rows wrap, and stack the secondary actions.
- Focused retest: Light English and Dark Simplified Chinese renderer captures
  show the section inside the existing card, with wrapped copy and no
  horizontal clipping.
- Regression retest: 193-test full suite passed; Light/Dark, Reduce
  Transparency, and Increase Contrast renderer matrix passed.
- Final status: repaired.

## WBLOGIN-002 — Unverified renderer flag skipped login content

- Severity: test-fixture defect
- First evidence: the Dark warning capture showed ordinary Settings but no
  WorkBuddy login section.
- Root cause: the renderer recognized `--workbuddy-login` but not the separate
  `--workbuddy-login-unverified` flag when constructing its in-memory
  coordinator.
- Repair: accept either flag and explicitly keep login fixtures out of the
  synthetic WorkBuddy Credit-card path.
- Focused retest: the Dark capture shows the exact macOS verification warning
  and official-install confirmation without introducing a WorkBuddy usage
  card.
- Regression retest: all four final renderer variants passed and the package
  helper contract test passed.
- Final status: repaired.

## WBLOGIN-003 — Trust check needed vendor identity

- Severity: major during implementation
- First evidence: initial code treated any strictly valid signature on the
  expected bundle identifier as trusted.
- Root cause: signature validity alone does not establish the expected
  WorkBuddy signer.
- Repair: a trusted result now requires strict static-code validation and Team
  ID `FN2V63AD2J`; other valid, rejected, or unverifiable states require the
  explicit official-vendor-install confirmation.
- Focused retest: deterministic discovery/trust-state tests cover trusted,
  rejected, and unverifiable states.
- Regression retest: Debug, Release, strict-concurrency Release with warnings
  as errors, and the full suite passed.
- Final status: repaired.

## WBLOGIN-004 — Vendor-install confirmation outlived the reviewed install

- Severity: major during independent staged-index review
- First evidence: the first runtime index persisted the official-install
  confirmation as a bare timestamp, so it could apply to a later unverified
  installation.
- Root cause: the persisted warning state was not bound to the exact
  installation that the person reviewed.
- Repair: schema 2 persists only an opaque installation identity with the
  confirmation. Restore and discovery clear the confirmation when the app is
  missing, trusted, or has a different identity.
- Focused retest: replacement-install and relaunch cases passed.
- Regression retest: 193-test full suite and strict-concurrency build passed.
- Final status: repaired; independent re-review passed.

## WBLOGIN-005 — Same bundle identifier could activate another app copy

- Severity: major during independent staged-index review
- First evidence: activation selected the first running application with the
  expected bundle identifier without comparing its bundle URL to the reviewed
  installation.
- Root cause: process activation used bundle identity alone.
- Repair: running-process activation and launch completion now require the
  exact reviewed bundle URL after standardization and symlink resolution. A
  different running copy fails closed.
- Focused retest: exact-path, different-path, and missing-path cases passed.
- Regression retest: 193-test full suite and all builds passed.
- Final status: repaired; independent re-review passed.

## Final automated verification

- Focused login-assistance suite: 12 tests passed.
- Full suite: 193 tests across 28 suites passed.
- Debug build: passed.
- Release build: passed.
- Strict-concurrency Release with warnings as errors: passed.
- `git diff --check` and cached-index check: passed.
- Independent staged-index re-review: passed.

## Open acceptance note

`HUMAN PHYSICAL LOGIN NOT EXECUTED`

This does not block the goal. No real WorkBuddy login, browser/WeChat
automation, credential handling, or Credit spend is required or permitted.
