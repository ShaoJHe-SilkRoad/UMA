# M1A-G2_DBG-C-P1 Shared Evidence Packet

This is the single reconciliation packet for the P1 auditors and implementer.  It records only reproducible, sanitized evidence; no account identity, credential, cookie, token, or raw provider payload is retained.

## Baseline

- Accepted baseline: `85b430ca7df24f169191a53421ffc67c4dd8dde5`.
- Branch: `main`, `origin/main`: `cd62d4b235b5e78a9045a36909aa656948cf54ab`, ahead by six local commits.
- Index was empty and `git diff --check` passed before P1 documentation creation.
- Existing dirty/untracked M1/M1-G5 work remains excluded; see the Scope Lock.

## Auditor sections

### Product usability

- **P1-U01 (confirmed):** a retained, real snapshot could hide all recovery controls when the connection moved to authorization-required or stale-failure state.  The panel therefore gave the human no visible route to check again, retry, cancel, or disconnect while data remained on screen.
- **Repair:** `RetainedSnapshotRecoveryPresentation` and the panel now present a compact, data-preserving recovery state with safe diagnostic detail and no raw provider payload.
- **Focused proof:** four `M1AG2DBGP1UsabilityTests` passed in the clean P1 source archive.

### Codex functional path

- **P1-FUNC-001 (confirmed):** fresh local metadata could incorrectly mark a snapshot fresh while the authoritative account channel was stale.
- **P1-FUNC-002 (confirmed):** owned-child recovery performed and discarded a provider fetch, leaving the connector/store without the fresh recovered snapshot.
- **P1-FUNC-003 (confirmed):** an older cancelled provider-event consumer could clear its replacement after reconnect.
- **Repair:** account freshness is authoritative when present; recovery emits one typed payload-free invalidation that enters the existing connector refresh lane; observation cleanup is generation-guarded.
- **Focused proof:** protocol, connector, dual-source, and P1 functional tests passed; the clean archive full suite passed 66 tests in 10 suites after the compact-header repair.

### macOS UI and accessibility

- **P1-A11Y-01 (confirmed):** Refresh had a hint but no explicit accessibility label.
- **P1-A11Y-02 (confirmed):** the settings close control had no explicit accessibility label.
- **Repair:** both controls now expose localized labels; retained recovery buttons are individually labeled.  Existing unlimited five-hour display semantics remain `♾️`, not a misleading percentage.
- **P1-UI-01 (confirmed during visual validation):** the fixed-width panel ellipsized the English product title next to the plan badge and toolbar controls.
- **Repair:** `UsagePanelHeaderLayout` gives the localized title a minimum scale factor and layout priority, while preserving the plan badge at its intrinsic width.
- **Focused proof:** the compact-header contract test passed; connected Light, Dark, Reduce Transparency, and Increase Contrast captures all show the complete English title without clipping.

### Packaging and human entry

- **P1-PKG-01 (confirmed):** the previous helper built from the dirty root and had no exact P1 human entry.
- **P1-PKG-02 (confirmed):** package provenance could not prove the selected provisional source archive was the archive actually built.
- **P1-PKG-03 (confirmed):** the former launch approach could terminate processes or open a second app instance.
- **P1-PKG-04 (confirmed):** Finder added `com.apple.FinderInfo` after opening a signed provisional candidate, making a subsequent whole-bundle verification fail and preventing a later Finder launch even though the executable had not changed.
- **Repair:** P1 packaging now requires a commit archive or hash-verified provisional archive.  The installer strictly verifies signing and provenance before promotion; immediately before a new launch, `UMA0.9_Enter` removes only Finder's display metadata, never alters resources or re-signs the review copy, and opens only a non-running candidate without Terminal instructions.
- **Static proof:** provisional bundle plist lint and strict deep ad-hoc signing passed.  A negative supplied-hash test failed closed with `Provisional P1 source archive hash mismatch.`

## Parent reconciliation

### Reproducible verification completed

- `bash -n script/package_uma_p1.sh` and `bash -n script/install_uma_p1_review.sh` passed.
- The clean P1 archive full regression passed **66 tests in 10 suites** after the compact-header repair.
- Clean P1 archive release builds passed for `CodexUsageMonitor` and `PreviewRendererTool`.
- A fresh isolated provisional candidate was rebuilt from SHA-256-verified archive `fb1602d94779132852a7bfa5c6e07a01fe0797c30140138e8f6d0f2d2091f1db`; its Info and provenance plists linted and strict deep ad-hoc signing verified.
- The provisional candidate reproduction confirmed that Finder display metadata can later invalidate a second whole-bundle verification without modifying the executable; the installer therefore retains the strict gate on the source candidate before promotion.
- `git diff --check` remains clean; the pre-stage index was empty and the exact P1-only staged audit is retained separately.

### Superseded live-validation block

The earlier platform limitation is superseded by the current direct action-time authorization.  Screen Recording was preflighted as already granted; only tightly cropped candidate-panel captures were retained.  Appearance and accessibility settings were changed only through the authorized matrix and then restored exactly.

## Isolated provisional candidate — live evidence

- Candidate: `precommit-20260718205200/CodexUsageMonitor.app`, bundle ID `com.kevinchen.CodexUsageMonitor.uma0.9.p1.precommit.20260718205200`, provisional revision `provisional-fb1602d94779132852a7bfa5c6e07a01fe0797c30140138e8f6d0f2d2091f1db`, executable SHA-256 `63d0c7e5415a4b67b22b35d194a282cdac17eb515c28c408434afcf4dc12d51f`.
- The post-repair visual candidate was rebuilt from SHA-256-verified archive `53387bbe5256a3c416075963848b6446755973a173c599ad1f9ccf98ac0d7961` as `precommit-20260718213600/CodexUsageMonitor.app`; plist lint and strict deep ad-hoc signing passed before bounded use.
- Status item was present and opened an on-screen `370 × 456` panel.  The panel presented sanitized live values, exactly one five-hour row in the authoritative `♾️` state, exactly one seven-day row, and a visible update timestamp.
- One visible Refresh action advanced the visible update time.  Fifteen additional distinct Refresh actions completed with retry-on-transient-AX handling; deterministic burst coverage passed in `M1AG2RefreshCoordinatorTests`, including `burstOfFiftyRequestsUsesOneProviderOperation`.
- Three restart checks and a post-restart check observed exactly one candidate app, one status item, and one direct owned `codex app-server --stdio` child.
- Five deliberately terminated direct owned children were each replaced in-process; each replacement recovered the visible five-hour infinity and seven-day rows before the next cycle.
- Fifty status-item panel toggles completed and ended with no panel left open.
- Simplified Chinese was exercised through the candidate's own restored language preference: Chinese panel labels and the `♾️`/seven-day semantics were present; English was restored afterwards.

## Completed visual matrix

- Original settings: Appearance `Light`, Reduce Transparency `0`, Increase Contrast `0`.
- Final restored settings: Appearance `Light`, Reduce Transparency `0`, Increase Contrast `0`; original and final match.
- Scoped sanitized candidate-only capture set (ignored local evidence):
  - `visual-20260718/light-panel-final.png`
  - `visual-20260718/dark-panel.png`
  - `visual-20260718/reduce-transparency-panel.png`
  - `visual-20260718/increase-contrast-panel.png`
- Light and Dark baselines showed intact glass material, readable labels, one five-hour `♾️` row, one seven-day row, visible update time, and no clipping after P1-UI-01.
- Reduce Transparency was captured with Appearance Light and Increase Contrast off; the panel remained legible with visible card and panel boundaries.
- macOS couples Increase Contrast to Reduce Transparency on this system.  The Increase Contrast capture therefore records the required combined compatibility state `1/1`; System Settings reported the Reduce Transparency control disabled while contrast was enabled.  Turning contrast off returned both controls to `0` before final verification.
- No unrelated screen, browser, account identity, credential, or uncropped desktop capture is retained.  Temporary capture helpers were P1 evidence-only and will be removed before the delivery audit.
- The required 20-minute process/memory/CPU continuous-run monitor completed 21 one-minute samples.  Every sample retained one candidate app and one direct owned child; candidate RSS ranged from 17,632 KiB to 70,208 KiB and the P1 package remained 14,964 KiB.  No crash or unexpected child duplication was observed.
- Final live postcheck retained one candidate app, one status item, and one direct owned child.  This packet must not claim P1 PASS, a final Finder entry, or a commit-exact candidate until the remaining staging, commit, and commit-exact delivery gates pass.
