# UMA M5RMX QA Issue Ledger

**Version:** 1.3

**Opened:** 2026-08-17

**Current task:** `M5RMX-CERT-UI-G1`

## 1. Scope and baseline

```text
Exact parent HEAD: 01b190260da857f55fa5fa9b14da9715cafbc221
Exact parent tree: 49f2af499c86b9b8757da0e9406a0d9e5c24495b
Source branch/worktree: codex/uma-m8-kimi / /Users/juliushe/Developer/UMA-M8-Kimi
New branch/worktree: codex/uma-m5rmx-claude / /Users/juliushe/Developer/UMA-M5RMX-Claude
Accepted predecessor full suite: 683/683 PASS
Accepted predecessor focused M8: 32/32 PASS
```

Current providers are Codex/Claude Code/WorkBuddy/Google Antigravity. Cursor/Kimi
are unsupported/hidden. Claude Safari Browser Sync is current; Chromium is
unverified; status-line is absent from production and retained only in
HISTORICAL / RETIRED records/tests. Current privacy policy:

`Credential existence is not the problem; credential crossing into UMA is the problem.`

## 2. G1 issues

| ID | Severity | Discovery | Root cause / classification | Required repair or control | Verification | State |
|---|---|---|---|---|---|---|
| M5RMXG1-001 | Blocking | Accepted Claude source truth was distributed across historical M5 records and current runtime | Without one current decision, a future Goal could revive status-line or replace Browser Sync without promotion evidence | Create the M5RMX source dossier and decision; retain Safari Browser Sync until every replacement gate passes | focused source-contract tests and independent source review | Closed; QA verification PASS |
| M5RMXG1-002 | Privacy | Provider-owned authentication could be confused with credential access by UMA | Credential existence and credential crossing were not expressed as one normative current contract | Create the M5RMX privacy contract with a closed browser/native allowlist and explicit forbidden mechanisms | protocol/source scan, privacy/identity/secret scan | Closed; QA verification PASS |
| M5RMXG1-003 | Semantic | Current account windows and continuation state needed separate admission | Five-hour/weekly quota is accepted, while continuation, usage credits, billing, and purchase state have no admitted bounded schema | Admit only explicit used-percentage windows with one conversion; classify continuation and usage-credit state unavailable | deterministic semantics and source-decision tests | Closed; QA verification PASS |
| M5RMXG1-004 | Source | Historical status-line callback remains a superficially attractive local source | It required a running CLI and Human-initiated provider response, so it cannot supply automatic no-work account truth | Keep the route HISTORICAL / RETIRED; require current official authority and all promotion gates before reconsideration | Package target/source reintroduction guards | Closed; QA verification PASS |
| M5RMXG1-005 | Protection | G1 could accidentally become a production extension rewrite | Source/privacy admission does not authorize Safari implementation, signing, package, or UI work | Restrict G1 delivery to current records, focused tests, and this ledger; production runtime/extension changes remain zero | exact Git scope and independent staged-index review | Closed; independent staged review PASS after repair |
| M5RMXG1-006 | Privacy / truth | Privacy Steward objected that an early G1 draft described selectors too narrowly and did not explicitly supersede historical toolbar-only records | Current extraction tries explicit selectors first, then bounded exact leaf-text matching across at most 4096 nodes; current Safari uses persistent exact host scope, storage, background ownership, one owned inactive tab, and automatic refresh | State transient in-browser fallback inspection honestly, forbid raw/broad text crossing, and lock the current persistent Safari contract in deterministic tests | manifest/extractor source assertions and privacy-record review | Closed; QA verification PASS |
| M5RMXG1-007 | Source / privacy | Source Examiner confirmed official status-line five-hour/seven-day used/reset fields but objected to treating their existence as promotion evidence | Fields appear only after the first API response, timer rerun freshness is unproven, raw stdin carries broader sensitive context, and documented quota coverage is Pro/Max only | Record exact fields and limitations; keep status-line HISTORICAL / RETIRED; leave Team/Enterprise/unknown unqualified | focused source-contract and privacy assertions | Closed; QA verification PASS |
| M5RMXG1-008 | Trust | Strict read-only verification currently fails for installed CLI 2.1.220 and `/Applications/Claude.app` | Current local executables cannot anchor a promoted local quota source without a valid trust result | Record sanitized arm64 invalid-signature errors; keep local service/CLI candidates unadmitted without changing Safari Browser Sync | exact read-only `codesign --verify --strict` and focused record tests | Repaired; local trust remains unadmitted |
| M5RMXG1-009 | Semantic | Included-plan exhaustion could be misreported as all Claude work stopping | Official usage-credit continuation means `0%` included remaining does not establish overall provider unavailability | Keep continuation/usage-credit state unavailable and overall work availability unknown; do not infer from percentage | deterministic continuation decision tests | Closed; QA verification PASS |
| M5RMXG1-010 | Regression | The B0 test read the mutable QA ledger for B0's former next-task gate | Advancing the current ledger to M5RMX-SAFARI-G1 made the historical B0 assertion stale even though the immutable B0 Scope Lock remained correct | Anchor the B0 next-task assertion only to the immutable B0 Scope Lock; keep the current ledger free to advance with the active Goal | focused B0 and G1 contract tests plus full deterministic regression | Closed; focused 12/12 and full 700/700 PASS |
| M5RMXG1-011 | Privacy / evidence | Independent staged review found the draft privacy contract placed login-landmark absence before the first DOM query and omitted the affected-suite count | The actual extractor correctly gates the exact route before a narrow login-form DOM query, then refuses quota inspection on login; QA evidence existed but was not fully carried into the durable record | Correct the contract to the route-gate → narrow login-landmark → quota-query order; record all focused, affected, and full results | focused source-contract recheck and independent staged-delta review | Closed; independent staged-delta review PASS |

G1 verification evidence:

```text
Focused M5RMX-G1 plus B0 regression: 12/12 PASS
Affected Claude Browser / M5 AUTO / M5RMX: 114/114 PASS
Full deterministic serial suite: 700/700 PASS
Production runtime / extension / package changes: 0
Claude provider operations: 0
```

## 2A. SAFARI-G1 issues

| ID | Severity | Discovery | Root cause / classification | Required repair or control | Verification | State |
|---|---|---|---|---|---|---|
| M5RMXSAFARI-001 | Major / lifecycle | A successful or unavailable automatic cycle retained the inactive extension-owned Usage tab | The prior implementation closed only selected authentication/route failures, even though the accepted automation contract requires one owned tab per cycle | Close the proven extension-owned tab for every terminal cycle; convert closure uncertainty to ownership loss; never query, adopt, navigate, or close a user-owned tab | focused source/lifecycle tests plus Browser/Protocol Auditor; affected 21/21 PASS | CLOSED |
| M5RMXSAFARI-002 | Blocking / privacy | Losing the ownership proof cleared the durable record while leaving the unproven hidden tab open | A later cycle could create a second hidden tab because the first could no longer be correlated safely | Retain the bounded ownership record on proof loss so future cycles fail closed; clear it only when the exact tab is absent or a proven tab is closed | owned-tab loss and no-multiplication tests; affected 21/21 PASS | CLOSED |
| M5RMXSAFARI-003 | Blocking / transport | File handoff used one exclusive pending slot but consecutive native messages could arrive before the app consumed the prior file | `RENAME_EXCL` correctly prevented overwrite, but the second safe message could be dropped by the browser bridge | Serialize local handoff delivery by waiting a bounded two seconds for the prior validated owner-only packet to drain; retain exclusive atomic publication and perform no provider retry | bridge concurrency, three-packet ordering, and pending-slot tests; bridge 20/20 PASS | CLOSED |
| M5RMXSAFARI-004 | Major / provenance | The Browser Sync packet had no replay nonce or explicit source-layout version | Schema/version checks alone could not distinguish a duplicate observation from a current browser result | Advance the closed schema to v2, add a UUID observation nonce and exact source-layout version, reject duplicate nonces in a bounded 64-entry runtime set, and invalidate v1 cache/messages | decoder, connector, packet allowlist and duplicate-replay tests; affected 21/21 PASS | CLOSED |
| M5RMXSAFARI-005 | Major / setup | Safari health returned only enabled/disabled and could not classify a missing, mismatched, or outdated embedded appex | Activation state was treated as sufficient even when the containing app's embedded identity/version was not current | Validate the exact embedded appex identifier, extension point, version 1.3.0, and build 8 before asking Safari for activation state | setup-health and package-contract tests; focused 7/7 PASS | CLOSED |
| M5RMXSAFARI-006 | Blocking / distribution | Existing M5/M6 phases permitted ad-hoc 0.11 packages | A development package could be mistaken for the production-ready 0.12 signed Safari preflight | Add a dedicated M5RMX wrapper and phase requiring explicit Developer ID, commit-exact source, 0.12, child-first Hardened Runtime signing, secure timestamps, Team `C6TUZVJ6SJ`, exact durable output, and no notarization | helper contract, signed package, strict-deep, staple, Gatekeeper and identity audits | CLOSED — exact signed/notarized candidate certified in Phase A |
| M5RMXSAFARI-007 | Major / lifecycle truth | Independent staged review found login/route redirects could not satisfy the exact Usage-route close proof | The truthful `signInRequired` or `routeRejected` terminal status was overwritten as ownership loss even though retaining the record was the required fail-closed behavior | Preserve the original redirected terminal status, retain the ownership record, and refuse a later tab while proof remains unavailable; continue fresh proof and closure for normal exact-route terminals | redirected-terminal classification and no-multiplication regression tests; focused 17/17 and affected 76/76 PASS | CLOSED |
| M5RMXSAFARI-008 | Blocking / lifecycle | Independent staged review found a tab-removal error was swallowed before the ownership record was cleared | A failed removal could leave the tab alive but erase the only bounded ownership correlation, permitting a later duplicate | Treat removal failure as closure failure, retain the ownership record, and clear it only after successful removal | removal-failure ownership-retention regression test; focused 17/17 and affected 76/76 PASS | CLOSED |
| M5RMXSAFARI-009 | Major / lifecycle truth | Final staged review found a stored login/redirect tab was token-proved before its route was classified | Exact-route token proof necessarily fails on a provider redirect, collapsing the next cycle to `ownedTabOwnershipLost` instead of the truthful sanitized login/route status | Classify the stored tab from URL route state only before token proof, retain its ownership record, create no replacement tab, and continue requiring exact-route token proof for an actual Usage route | stored-redirect next-cycle ordering and no-clear/no-multiplication regression tests; focused 18/18 and affected 77/77 PASS | CLOSED |
| M5RMXSAFARI-010 | Blocking / packaging | The first post-commit signed-package attempt reached Developer ID signing but `codesign` reported the confirmed Team `C6TUZVJ6SJ` identity unavailable | The helper intentionally exported a task-owned isolated `HOME` for SwiftPM before signing, which also hid the normal user signing search context from `codesign` | Capture the original user HOME before build isolation and restore it only on each bounded `codesign` signing, verification and inspection command; keep SwiftPM HOME/cache/config/security paths isolated and perform no keychain enumeration or credential export | focused package contract, shell syntax, strict signature, staple and Gatekeeper checks | CLOSED — exact signed/notarized candidate certified in Phase A |
| M5RMXSAFARI-011 | Blocking / privacy | Final signed live preflight stopped before Observation 1 when source review found production Browser Sync constructed `ClaudeLocalActivityReader` and scheduled it from every snapshot publication | The account-quota connector still owned the historical local analytics dependency; publishing connect, cache, callback, refresh, or failure state could scan prompt-bearing records beneath `~/.claude/projects` | Remove all Local Activity ownership, construction, scheduling, merging, capability and allowlist claims from Browser Sync; retain the standalone reader only as a deferred separate feature; lock invocation and projects-access diagnostics to architectural zero | old-fail/new-pass suite covers connect, callback, preseeded cache load/publication, disconnect clear, scheduled/manual refresh/coalescing, reconnect and failure/recovery: 4/4 PASS; affected Claude Browser Sync/M5/M5RMX 116/116 PASS; deterministic full 724/724 PASS; Debug, Release, strict-concurrency Release, native-host arm64, Assistant UIFIX, privacy and provider-protection audits PASS | SOURCE REPAIR VERIFIED — SIGNED LIVE ACCEPTANCE PENDING |

SAFARI-G1 independent verification evidence:

```text
Independent QA full deterministic suite after M5RMXSAFARI-009: 715/715 PASS
  - UI: 695/695 PASS across 71 suites
  - Bridge: 20/20 PASS
Focused SAFARI-G1 suite after M5RMXSAFARI-009: 12/12 PASS
Focused M5-AUTO suite: 31/31 PASS
Debug build: PASS
Release build: PASS
Strict-concurrency Release build: PASS
Native-host strict build: PASS
Extension JavaScript syntax and manifest/plist audits: PASS
Privacy, identity, secret and content audits: PASS
M5 frozen-set audit: PASS
Independent Packaging/Signing Auditor: PASS for the source and packaging/signing contract
Root signing-identity check: exactly one valid Developer ID Application identity for Team C6TUZVJ6SJ
Post-review lifecycle-repair focused B0/SAFARI suites: 18/18 PASS
Post-review affected Browser/automation/bridge suites: 77/77 PASS
```

The exact commit-exact 0.12 candidate passed child-first Developer ID signing,
notarization, staple, Gatekeeper and normal-Safari acceptance. Signed Browser
Sync completed one current sanitized observation and one completion-relative
automatic refresh. The candidate was then disconnected, disabled and
unregistered; the old Desktop 1.2.3 registration and its original inactive
state were restored; task-owned runtime/cache state was removed; Safari
unsigned-extension mode remained OFF. Exact private quota values were not
retained.

That historical candidate remains immutable distribution evidence, but its
live acceptance was superseded when the production account-quota path was found
to schedule the prompt-bearing Local Activity reader. `M5RMXSAFARI-011` must
pass source, fresh signing/notarization, and fresh signed live acceptance before
SAFARI-G1 can close again.

## 2B. CERT-UI Phase A issue ledger

| ID | Severity | Discovery | Root cause / classification | Required repair or control | Verification | State |
|---|---|---|---|---|---|---|
| CERT-01 | Blocking / distribution | The signed 0.12 candidate had been notarized but had not yet been consolidated into one durable certified baseline | Signing, notarization and local runtime acceptance were spread across transient evidence | Freeze the exact candidate/archive and record Developer ID, Accepted submission, strict signature, staple and Gatekeeper evidence without secrets | exact paths/hashes; strict deep signature PASS; stapler PASS; Gatekeeper `Notarized Developer ID`; independent Packaging/Signing Auditor PASS | CLOSED |
| CERT-02 | Blocking / Safari | Old Desktop 1.2.3 and candidate 1.3.0 shared one Safari extension identifier | Duplicate PlugInKit/LaunchServices registration could make Safari expose the old build | Temporarily unregister only the old registration, register and enable the exact signed/notarized 1.3.0 candidate in normal Safari with exact-site access, then restore the old disabled state | Safari visibly listed/enabled 1.3.0; `claude.ai` only; unsigned mode OFF; Browser/Protocol Auditor PASS | CLOSED |
| CERT-03 | Blocking / protocol | Distribution acceptance required the complete signed extension → sanitizer → native helper → UMA chain, including automation | A signed bundle alone does not prove sanitized live handoff or scheduler behavior | Perform at most three sanitized observations with zero prompts/tasks/spend; require one current read and one completion-relative refresh | two successful sanitized observations; automatic refresh PASS; one scheduler/read in flight; native handoff PASS; privacy review PASS | CLOSED |
| CERT-04 | Major / lifecycle | Temporary registration and runtime state could contaminate future Safari debugging | Candidate registration, old-registration displacement, cache, handoff or helper state could survive the certification cycle | Disconnect; clear UMA-owned sanitized state; disable/unregister candidate; restore old registration and inactive state; verify unsigned mode OFF and task-owned processes absent | cache absent; handoff empty; candidate absent; old 1.2.3 restored/inactive; no task-owned process; unsigned mode OFF | CLOSED |

Phase A role evidence:

```text
Packaging / Signing Auditor: PASS — immutable identity, nested payload, archive hash and package permission surface independently verified.
Browser / Protocol Auditor: PASS — exact-site route gate, sanitizer, native handoff, scheduler and owned-tab lifecycle independently verified.
Privacy Steward: PASS — provider-owned authentication stayed outside UMA; no retained credential, identity, raw page or exact quota evidence.
qa_runner: PASS — 102/102 focused and affected tests; exact artifact hashes, strict signature, staple, Gatekeeper, bookkeeping, whitespace and empty-index checks PASS.
examiner: PHASE A PASS — no material certification, distribution, protocol, privacy, cleanup or evidence objection.
Primary live observations: 2/3 maximum; prompts/tasks 0; intentional spend 0; account mutations 0; automatic retries 0.
```

`UMA CERTIFIED DEBUG BASELINE — PASS`

`M5RMX-SAFARI-G1 — PASS`

## M5RMX-UIFIX-G1 issue ledger

| ID | Severity | Reproduction | Root cause | Exact repair | Focused retest | Human physical result | Regression result | Final status |
|---|---|---|---|---|---|---|---|---|
| UIFIX-01 | Blocking / Major | Founder physical evidence: the original Assistant did not drag; the perimeter-only repair also failed because most visible pixels still could not start a drag | The full-size `NSHostingView` consumes events before window-background dragging, while the failed replacement admitted only a six-point perimeter and row gaps. Card centers, labels, icons and percentages were explicitly classified as non-draggable | Keep background dragging disabled and attach exactly one native AppKit gesture recognizer to the full hosting view. A four-point threshold and delayed primary-button delivery preserve stationary/small-wobble clicks, intentional movement translates the native panel, and no SwiftUI drag gesture or overlay competes | PASS — 5/5 focused tests send native mouse sequences through the real four-card SwiftUI Assistant stack in Regular and Minimalist. Fourteen named drag starts cover edge, gap, center, title/mark, percentage, icon and a lower clickable card; every drag moves the panel without selection, while every interactive stationary and 3.5-point wobble sequence selects exactly once without movement | PASS — Founder confirmed universal dragging, three-position movement, and Regular/Minimalist behavior | PASS — 101/101 affected regressions; 720/720 full deterministic suite; Release and strict-concurrency Release PASS | CLOSED |
| UIFIX-02 | Minor regression | Founder physical evidence: the original Assistant and first repair both showed a duplicated outer edge | Renderer-only captures exclude the panel and reproduce both edges: the clipped material/opaque boundary and explicit rounded `strokeBorder` were separate contour producers, while the panel shadow added another edge in the live window | Remove the explicit Assistant `strokeBorder`, disable the panel shadow, and retain the clipped material/opaque boundary as the single contour owner | PASS — composed live-panel assertions verify transparent borderless panel ownership, zero window shadow, zero hosting-layer border/shadow and exactly one root recognizer; 18/18 affected visual-system tests verify one clipped material boundary, no Assistant stroke and frozen geometry | PASS — Founder confirmed exactly one visible outer contour in Light/Dark × Regular/Minimalist | PASS — Light/Dark and Regular/Minimalist contracts plus full deterministic suite and builds | CLOSED |
| UIFIX-03 | Blocking / interaction | Universal drag from interactive cards and control-like surfaces could swallow a click or deliver a trailing click after movement | A full-surface drag owner needs deterministic threshold arbitration rather than a transparent overlay, background-only movement, or two competing gestures | Use one native recognizer with a four-point threshold and delayed primary events: below threshold forwards one click; threshold-crossing movement moves the panel and suppresses the underlying click | PASS — all 12 interactive probes select exactly once when stationary or moved 3.5 points; all intentional drags suppress selection and move the native panel in both densities | PASS — Founder confirmed stationary click preservation and no click after drag | PASS — focused, accessibility, lifecycle, Main Panel, provider-order and full regression gates | CLOSED |

Phase B final evidence:

```text
Founder physical validation: DRAG PASS; CLICK PRESERVATION PASS; DOUBLE BORDER PASS.
Focused UIFIX: 5/5 PASS.
Affected UI/provider regressions: 101/101 PASS across 9 suites.
Full deterministic suite: 720/720 PASS — 700 UI across 72 suites plus 20 bridge.
Release: PASS.
Strict-concurrency Release with Swift warnings as errors: PASS.
M5RMX source/privacy protection: 23/23 PASS.
Light/Dark; Regular/Minimalist; Main Panel; provider order; accessibility; lifecycle: PASS.
Implementer: PASS.
qa_runner: PASS.
examiner: PASS — no remaining pre-Human blocker.
Product UX / Accessibility QA: PASS — no material finding after the 14-region four-card recheck.
```

This bounded repair performed no provider read, provider/source edit, Apple
query, notarization action, package mutation, Desktop installation, or remote
Git action. The current submitted Safari preflight app and frozen notarization
archive remain external read-only evidence.

## 3. B0 issues

| ID | Severity | Discovery | Root cause / classification | Required repair or control | Verification | State |
|---|---|---|---|---|---|---|
| M5RMXB0-001 | Blocking | Founder governing files were present only in Downloads | M5RMX had no installed program authority in the new branch | Install `M5RMX_Plan.md` and `M5RMX_Goal.md` under mutable `source/`, preserving semantic content while satisfying the required repository whitespace gate | source/download semantic comparison, original and installed SHA-256, whitespace audit | Closed; independent staged review PASS |
| M5RMXB0-002 | Blocking | Accepted Claude behavior was distributed across current source and historical M5 records | A new implementation could accidentally rebuild or contradict accepted Browser Sync | Create a current claim-to-code/live/package/commit map and file-ownership inventory | deterministic B0 contract plus independent review | Closed; independent staged review PASS |
| M5RMXB0-003 | Major | Historical status-line records/tests still exist alongside current Browser Sync records | Retained history can be mistaken for current source ownership | Record Browser Sync as current, status-line as historical/retired, active target/source absence, and package reintroduction guards | production/source/package-symbol checks | Closed; source and independent review PASS |
| M5RMXB0-004 | Major | Apple signing readiness and the historical smoke notary backend anomaly are separate states | Treating readiness as Accepted notarization would overclaim distribution | Record Team `C6TUZVJ6SJ`, `UMA-notary`, submission/backend anomaly, support IDs, and protected smoke artifacts; execute no Apple action | record-only audit against Founder evidence | Closed for B0 record truth; Apple workstream remains external |
| M5RMXB0-005 | Major | Live `origin` is `ShaoJHe-SilkRoad/UMA`, while the Founder plan names `ShaoJHe-SilkRoad/CodexUsageMonitor` | Future push could target the wrong repository if the discrepancy is ignored | Preserve live remotes, record discrepancy, require M5RMX-SYNC-G1 identity/divergence gate | `git remote -v` and local ref inventory; no remote mutation | Closed for B0; external decision deferred to SYNC |
| M5RMXB0-006 | Major | Desktop contains a dirty historical development checkout and a pre-existing 0.12 app | Automatic update could destroy Human work or misidentify the final deliverable | Inventory exact states/hashes; preserve both apps/checkouts; require later commit-exact delivery gate | read-only Desktop metadata/hash and Git status | Closed for B0; delivery deferred |
| M5RMXB0-007 | Major | Current M5 package helper still declares marketing version 0.11 and the Safari appex carries a temporary file exception | Current packaging cannot be represented as final accepted 0.12 distribution | Record exact package/entitlement state; defer repair/adjudication to the named M5RMX packaging/Apple Goals | package-source inventory | Open program work; not a B0 blocker |
| M5RMXB0-008 | Privacy | Provider-controlled credential state could be confused with UMA credential access | Earlier formulations focused on credential existence rather than boundary crossing | Adopt the exact current privacy sentence and enumerate closed sanitized packet/prohibited data classes | privacy/identity/secret scans and protocol inventory | Closed; bounded scans PASS |
| M5RMXB0-009 | Protection | `source/reference/**` contains older provider truth | Historical reference material could be rewritten to match current runtime | Classify it as checksum-locked/read-only; add current additive records only | exact reference-tree diff | Closed; unchanged from accepted parent |
| M5RMXB0-010 | Gate | Fresh B0 baseline and build evidence was not available during the docs phase | Accepted 683/683 predecessor evidence could not replace current B0 verification; parallel diagnostic reruns also exposed unrelated historical lifecycle-test timing instability | Run the required deterministic suite serially, plus focused B0, Debug, Release, and strict-concurrency gates; do not upgrade isolated parallel timing failures into B0 source defects | `6/6` focused PASS; deterministic `--no-parallel` full suite `689/689` PASS; isolated timing-test reruns PASS; Debug / Release / strict PASS | Closed |
| M5RMXB0-011 | Gate | Founder Plan/Goal source copies exposed 57 two-space Markdown hard-break lines to Git's required trailing-whitespace gate | B0 initially applied the checksum lock for historical `source/reference/**` too broadly to the new mutable `source/` authority files; neither the Founder objective nor the governing files require byte identity for these installed copies | Preserve the Downloads originals, remove only trailing hard-break spaces from the installed mutable copies, retain all semantic text and line structure, and leave Git whitespace configuration unchanged | Plan 47 / Goal 10 source hard breaks normalized to zero; tabs and three-plus endings zero; installed diff check PASS | Closed |
| M5RMXB0-012 | Evidence | Packaged Chromium companion resources could be mistaken for accepted current Browser Sync | Current accepted live evidence is Safari-only; packaging presence does not prove Chromium runtime acceptance | Mark Safari as current source owner and Chromium as unverified/future | current source/record map review | Closed in records |
| M5RMXB0-013 | Distribution | Apple credential/signing infrastructure readiness could be mistaken for a signed/notarized current product | The historical smoke is blocked by a backend anomaly and the current M5RMX package has not passed final distribution gates | Record infrastructure and protected local smoke presence separately from current product distribution status | local path presence only; no Apple query | Closed in records; final distribution remains unproven |
| M5RMXB0-014 | Evidence | Bounded local verification found both the retained smoke app and an isolated extraction of its archive currently fail strict signature verification as code modified | The current preserved state does not support repeating the historical signature-valid claim; matching executable SHA-256 values show the retained app and archive payload agree | Record the discrepancy without querying Apple or repairing, re-signing, deleting, or mutating either protected artifact; remove only the scratch extraction | protected-path presence, matching executable hashes, strict local signature classification, scratch absence | Closed for B0 truth; external Apple resolution remains open |

## 4. Required B0 verification ledger

| Gate | Required result | Current record |
|---|---|---|
| exact parent HEAD/tree | exact values above | verified before edits |
| branch/worktree | exact source/new branch/worktree above | verified before edits |
| Plan source / installed SHA-256 | source `03dd6167b663022cb615540055231241ab1439d4c0150323d72bd79179c07a67`; installed `b43837b03bea0af20bf67f7fcf3cd83b932450ffcf2c987864adfed695782ffe` | semantic content preserved; only 47 trailing two-space hard breaks removed from mutable copy |
| Goal source / installed SHA-256 | source `5a84f486deb8065732bde965dbbad4e7533720ccf984867419474fc6bde5cf6f`; installed `182f022baaeeca8494adfda888cc5ed6c54df56975966634d62b6dd360487ee8` | semantic content preserved; only 10 trailing two-space hard breaks removed from mutable copy |
| focused B0 contract | PASS | `6/6` PASS |
| full deterministic suite | PASS; legitimate current count reported | `689/689` PASS: deterministic `--no-parallel` run, 671 UI plus 18 bridge |
| Debug / Release / strict Release | PASS / PASS / PASS | PASS / PASS / PASS |
| current Claude mechanism | Browser Sync present; status-line retired | source map and independent examiner PASS |
| protected providers | Codex/WorkBuddy/Antigravity unchanged | source diff empty; no staged production/provider mutations |
| unsupported providers | Cursor/Kimi unsupported/hidden | records/source audit PASS |
| `source/reference/**` | unchanged | exact parent diff empty |
| protected Desktop rollback | executable SHA unchanged | `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` reverified |
| privacy/identity/secret scans | no prohibited retained material | bounded six-file scans PASS |
| whitespace | all six staged files clean | Plan/Goal mutable copies normalized; cached `git diff --check` PASS |
| staged index | exact B0 files; independent cached-diff PASS | exact six-file scope; PASS |

## 5. Apple and Desktop non-operation record

Apple state is record-only:

```text
Team: C6TUZVJ6SJ
Profile: UMA-notary
APPLE-G1: BLOCKED — APPLE NOTARY BACKEND / SUPPORT INVESTIGATION
Feedback: FB24386147
Support: 20000140194585
Protected smoke: /private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.app
Protected archive: /private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.zip
```

Desktop rollback identity:

```text
/Users/juliushe/Desktop/UMA_0.11.app
SHA-256: 88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

B0 performed no production/provider/Apple/Desktop actions. It did not query or
resubmit notarization, touch the profile/private key, launch a provider, read an
account, mutate a Desktop app, or push.

## 6. G1 completion boundary

G1 can close only after the source/privacy decision, focused and affected
Claude verification, full deterministic regression, bounded privacy scans,
exact staging, independent review, local commit, and clean worktree/index gates
pass. This implementer pass used zero Claude observations, zero prompts/tasks,
zero intentional provider spend, and zero production runtime/extension changes.
The sole next task is `M5RMX-SAFARI-G1`. No Safari implementation, package,
Apple action, Desktop delivery, remote synchronization, or later M5RMX Goal
starts automatically.
