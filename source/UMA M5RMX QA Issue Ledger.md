# UMA M5RMX QA Issue Ledger

**Version:** 1.7

**Opened:** 2026-08-17

**Current task:** `M5RMX-FINAL — UMA 0.13.0 current-major completion`

## Current-major completion issues — 2026-08-29

The accepted Claude root-repair closeout below is predecessor evidence. It is
not evidence that the production 0.13.0 split-host package, notarization,
Desktop delivery, or Founder-remote synchronization has completed.

| Issue | Severity | Discovery / exposure | Repair | Verification | State |
|---|---|---|---|---|---|
| `M5RMX-FINAL-001` Claude source admission and source truth | Major | Shared presentation admitted every nonnegative reading and several labels collapsed exact local status-line, exact Safari, estimate, and stale states | Centralized provider surface admission, restored the required exact-local → exact-Safari → estimate → stale precedence, and made source labels explicit | Focused product integration, Claude Smart/Desktop, privacy/source, accessibility, and localization tests | CLOSED — source repair verified |
| `M5RMX-FINAL-002` retained last-good provider behavior | Major | Codex and WorkBuddy did not expose one consistent sanitized retained-last-valid contract across transient failure | Added sanitized last-valid restore descriptors and safe transient retention; authentication/disconnect still clears state | Focused provider presentation and WorkBuddy refresh/regression tests | CLOSED — source repair verified |
| `M5RMX-FINAL-003` Settings/Main/Assistant parity | Major | Settings reconstructed provider summaries independently and could drift from the Main Panel/Assistant; Claude source details and resetless copy were incomplete | Settings now consumes the same resolved presentation cards, exposes the admitted Claude detail controls, and omits empty reset separators | Focused four-provider integration, presentation, Assistant, accessibility, and localization tests | CLOSED — source repair verified |
| `M5RMX-FINAL-004` verification/protocol fail-closed boundary | Major | Companion verification could be coupled to provider consent and bridge events could synthesize stale production identity/generation | Kept verification content-free, removed consent coupling, and fail closed when signed runtime identity is absent | Bridge/Host IPC, consent-handshake, generation, privacy, and source-contract tests | CLOSED — source repair verified |
| `M5RMX-FINAL-005` release/version/Test-channel truth | Major | Historical 0.12 and Test-channel statements could be mistaken for current 0.13.0 production delivery; Test cleanup could target production-named artifacts | Declared 0.13.0/0.11 release truth, Founder remote, production/Test isolation, and exact Test cleanup classification | Governance/source tests and Apple Development signing/package-isolation tests | CLOSED — release truth verified; production delivery pending |
| `M5RMX-FINAL-006` production split-host runtime and package | Blocking | Production protocol/IPC constants existed, but the production Safari native handler qualified only the retired combined-app identity and hard-coded the Test App Group; no commit-exact Developer ID split-host release exists yet | Added a fail-closed 0.13.0 split production package/seal/install contract for the Safari-free mutable app and immutable Host/Companion, with exact Developer ID distribution profiles, effective entitlements, one generation, child-first Hardened Runtime signing, joint notary provenance, sealed-artifact hashes, rollback protection, and atomic delivery. Repaired the handler to resolve the exact signed containing-app/appex pair first, route production and Test split hosts through their own App Groups, retain only explicit retired combined channels, and reject mixed identities. | Production packaging contract `8/8 PASS`; production extension/package focused tests `31/31 PASS`; Host IPC focused tests `23/23 PASS`; affected matrix `281/281 PASS`; full deterministic suite `928/928` UI/product plus `56/56` bridge/Host PASS; Debug, Release, strict-concurrency Release, native-host Release, and Safari-host Release PASS. Pending exact Developer ID identity/profiles, source freeze, notary, consolidated Human smoke, delivery, and remote readback | OPEN — source/runtime repair verified; external Apple distribution assets and release acceptance remain |
| `M5RMX-FINAL-007` tracked legacy binary artifact | Major / hygiene | `outputs/CodexUsageMonitor.app.zip` was a tracked obsolete binary with the retired `com.kevinchen.CodexUsageMonitor` identity | After exact Founder authorization, verified its canonical path, current-user ownership, non-symlink state, retired bundle ID, size, and SHA-256 `b984a29d2776b925a224a4057c444d0b3724f0ade940434580af21226d9f5976`, then removed only that tracked artifact; no replacement binary belongs in Git | Exact deletion plus repository generated/private-artifact and staged-hygiene review | CLOSED — authorized legacy artifact removed |
| `M5RMX-FINAL-008` production package scratch bootstrap | Blocking | The first exact frozen-source package attempt stopped before compilation because nested isolated cache directories were created without their parent | Create the complete isolated package workspace with recursive directory creation and retain the coherent Xcode/cache boundary | Focused production packaging contract, shell validation, clean exact-source rebuild, and final artifact audit | CLOSED — release-blocking bootstrap repair verified |

Current pre-freeze evidence: the affected product/provider/Assistant/
accessibility/localization/lifecycle matrix is `281/281 PASS`; the current full
deterministic suite is `928/928 PASS` for UI/product tests plus `56/56 PASS`
for bridge/Host tests. Debug, Release, strict-concurrency Release, native-host
Release, and Safari-host Release builds pass. These results prove the current
repair set but are not final release evidence: the final frozen commit still
requires the governing release verification, notarization, Human smoke,
delivery, and Founder-remote readback sequence.

## 0. Final-closeout issue disposition — 2026-08-29

| Issue | Severity | Discovery / exposure | Repair | Focused and live verification | State |
|---|---|---|---|---|---|
| `M5RMX-FC-01` resetless exact durability | Major | Provider reset timestamps are legitimately optional; rejecting or persisting them without a bound made exact state incorrect | Atomic owner-only anchor store, committed readback, five-minute resetless TTL, purge, no reset fabrication, no calibration | Real Read 1 exact result; atomic commit/readback; Safari quit; UMA relaunch; deterministic expiry tests | CLOSED |
| `M5RMX-FC-02` Host IPC failure misclassification | Major | Mutable adapter collapsed generation/protocol failures into provider `routeRejected` | Added mutable-only terminal classification; protocol, browser and Companion failures retain distinct product state without changing Host protocol bytes | Focused Host product-state and consent/handshake suites | CLOSED |
| `M5RMX-FC-03` misleading Usage action | Minor | The UI said it opened Claude Usage while the retired direct-page action only verified the Companion | Relabeled and localized as `Check Browser Companion`; no provider access is implied | Focused Settings/localization suite | CLOSED |
| `M5RMX-FC-04` implicit Safari launch diagnostic | Major | Content-free CLI verification requested Safari launch without a distinct caller flag | Default is fail-closed; `--allow-safari-launch` is required explicitly | Focused machine-verifier source and behavior contract | CLOSED |
| `M5RMX-FC-05` APP_ONLY metadata gap | Major | Installer verified signatures and hashes but not every signed Host runtime metadata key | Validate Host ID, Companion ID/version/build, generation, Team and App Group before and after install | Packaging contract plus shell syntax/diff checks | CLOSED |

No provider value, raw DOM, identity, credential, cookie, token, diagnostic
payload, package, screenshot, or private receipt is retained in this ledger.
Provider reads used: `1/2`. The immutable Host and Companion were not changed
during final closeout.

Final verification: affected `240/240 PASS`; observable-state/task-start
individual, parallel 10/10, and load 10/10 `2184/2184 PASS`; two full
deterministic suite runs `963/963 PASS` each; mutable/Host/Companion signing
trust `10/10 PASS` each. The historical `CSSMERR_TP_NOT_TRUSTED` result is
closed as a restricted execution-context trust failure, not artifact
corruption; the unchanged artifacts now verify deterministically.

Independent staged-index review passed. The retired, untracked bootstrap HTML
and JavaScript artifacts were excluded from Git and removed under exact Founder
authorization. Final worktree and index cleanliness are mandatory Completion
Lock evidence.

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
are unsupported/hidden. Claude Local Smart Mode is the current implementation
candidate: the bounded status-line relay is the preferred exact local lane,
calibrated local estimates are labeled, and Safari is retained only for an
explicit one-shot Accuracy Sync. Chromium remains unverified. Current privacy
policy:

`Credential existence is not the problem; credential crossing into UMA is the problem.`

### Current forensic authority and freeze

The current source-of-truth task is
`M5RMX-CLAUDE-FORENSIC-CLOSE-G1`. It runs in the canonical workspace
`/Volumes/HE/DEV/UMA/Worktrees/UMA-M5RMX-Claude` from baseline HEAD/tree
`af2317dd510935b440078572150417d81b2aefdb` /
`2256466cd1c098129f2f6d67fb141bc54a66069f`. All pre-existing dirty WIP is
preserved and remains unstaged.

The installed immutable Safari Host build `202608281805`, runtime generation
`e55245ee-7baf-4791-aadc-f13b52209986`, and its Event-Driven Companion are
**not final**. The pending Human enablement is suspended. Until the complete
offline audit, consolidated repair, adversarial/synthetic verification,
privacy review, packaging/signing review, and independent examiner pass, there
must be no Safari enablement request, registration mutation, Safari restart,
site-permission change, Accuracy Sync, or Claude provider read. Earlier
sections remain historical evidence; any claim that the `1805` generation is
ready or that the current live Accuracy Sync has passed is superseded.

## 1A. Authoritative A-U Claude/Safari blocker ledger

The build labels below are exact where retained evidence supplies them and
otherwise identify the development lineage without inventing a build number.
`Human necessary` distinguishes a genuine Apple/Safari security interaction
from an engineering or development-process failure.

| Block | Approximate build / generation | Subsystem and observed symptom | First failing boundary | Root cause classification and eventual cause | Repair and current status | Human necessary / migration / recurrence |
|---|---|---|---|---|---|---|
| A | Original combined UMA + Companion lineage | Multiple same-purpose containing apps/extensions made the active Companion ambiguous | Signed containing-app/appex ownership | `IDENTITY_DEFECT` + `DEVELOPMENT_PROCESS_DEFECT`: production, Desktop, package and Test registrations were not isolated | Dedicated Test identities and exact registration inventory were introduced; later superseded by the immutable Host split | One enable was legitimate for a genuinely new signed Test identity; repeated attempts against ambiguous inventory were avoidable. Prevent recurrence with one canonical Host and one Companion registration |
| B | Historical package and Desktop-app lineage | LaunchServices selected an older Package `.app` instead of the intended candidate | LaunchServices resolution before dispatch | `PACKAGING_DEFECT`: duplicate same-identity apps were left discoverable | Canonical paths, exact bundle/version checks and retirement of task-owned duplicate registrations | No Human action was required. Recurrence is blocked only by exact-path inventory and duplicate rejection |
| C | Apple-signed 0.13 Test-channel migration | Signed Test Companion became visible without unsigned mode, but production and Test state could still collide | Test/runtime identity qualification | `IDENTITY_DEFECT` repaired by dedicated Test bundle identifiers, generation metadata and Team validation | Test and production runtime identities are isolated and mismatches fail closed | One Human enable was legitimate for the new Test extension identity. Ordinary updates must not repeat it |
| D | Combined Test generations, 2026-08-27 | Safari UI showed the extension while preflight returned `extensionUnavailable` or no acknowledgement | Safari state snapshot/dispatch reachability | `SAFARI_STATE_API_LIMITATION` + `ASYNC_LIFECYCLE_DEFECT`: a state query was treated as delivery proof and dispatch acceptance as extension acknowledgement | Machine qualification now requires correlated request/acknowledgement/receipt; state is diagnostic, not a hard reachability oracle | No additional Human action should have been requested solely from this result. Same-class recurrence is prevented by causal acknowledgements |
| E | Pre-Host native bridge iterations | `wakeDispatchAccepted` ended in native unavailable or timeout | WebExtension background to native port | `NATIVE_BRIDGE_DEFECT`: mixed `sendNativeMessage`/`connectNative` assumptions, weak port lifetime and incomplete disconnect handling | One canonical managed `connectNative` transaction with retained port, correlated response and explicit disconnect reason is the required active path | No Human action. Recurrence remains open until the final bridge audit and 10/10 live handshake qualification pass |
| F | Pre-Host handshake iterations | UI reported ready before the native handler and bidirectional response had completed | Readiness receipt | `ASYNC_LIFECYCLE_DEFECT`: dispatch acceptance or early bridge state was promoted to readiness | Ready means only a validated same-request/same-generation terminal receipt after native response and app callback | No Human action. Prevent with phase acknowledgements and state-machine tests |
| G | Pre-Host product-state iterations | Machine handshake was blocked by missing Claude provider consent | Qualification before provider access | `CONSENT_COUPLING_DEFECT`: machine capability and provider authorization shared one connected flag | Machine handshake, consent, site access, provider read, Local Smart and app shell are separate state dimensions | Human consent is legitimate only immediately before a provider read, never for machine qualification |
| H | Pre-Host inventory iterations | `STATE_ERROR`, false-disabled, or false-unavailable results triggered setup loops | `SFSafariExtensionManager` state classification | `SAFARI_STATE_API_LIMITATION`: a bounded enablement snapshot cannot prove delivery, background wake or native-handler entry | Use the API as one read-only state signal; direct content-free acknowledgement is the operational proof | No repeated Human setup from state alone. A real disabled state still requires Human action for a deliberate migration |
| I | Reload-safe tab ownership iterations | Reload/crash could lose the creation-to-tab attachment or close the wrong tab | Durable ownership recovery | `OWNED_TAB_DEFECT`: memory-only ownership, non-atomic creation intent, and later unsafe tab discovery | Save intent before create; correlate request/generation/nonce; attach exact ID; recover only through same-tab proof; never enumerate generally; never close unproven tab; cleanup before success | No Human action. Current consolidated recovery changes are verification-pending |
| J | Future production-package audit | App and appex could be signed with inconsistent runtime-generation/ownership metadata | Package-time substitution/signing | `PACKAGING_DEFECT` + `IDENTITY_DEFECT`: metadata was not one pre-signing package authority | Matching signed app/appex Team, IDs, protocol and per-package generation; mismatch rejected | No Human action. Production runtime qualification is offline evidence only in this Goal; no production package is released |
| K | Full-suite repair iterations | A large suite could fail from orchestration timing and parallel build contention rather than product behavior | Test runner/build coordination | `TEST_INFRASTRUCTURE_DEFECT`: timeout/order assumptions and concurrent SwiftPM use obscured causality | Focused tests during repair, one affected pass, then one final deterministic suite with exact phase diagnostics | No Human action. Avoid repeated full-suite theatre; recurrence controlled by deterministic orchestration |
| L | Menu-bar shell regression | `open -gja` launched a state in which dropdown/Settings/Assistant interaction failed | App activation and shell lifecycle | `PRODUCT_SHELL_DEFECT`: launch method bypassed the normal product activation path | Installer/runtime tests reject `open -gja`; normal launch and shell-independent construction restored | No Human action. Human physical smoke later passed dropdown 5/5, Settings and Assistant |
| M | Main-panel construction regression | App shell could depend on a provider runtime being ready | Panel/root construction | `LOCAL_SMART_COUPLING_DEFECT` + `PRODUCT_SHELL_DEFECT`: provider state leaked into shell construction | Shell, Local Smart and provider/browser states are independently constructed and presented | No Human action. State-matrix regression coverage must remain |
| N | Combined Test app builds `202608271568` → `202608271569` | Replacing only outer app bytes disabled the nested Companion despite frozen appex executable/hash evidence | Safari enablement persistence after containing-app replacement | `PACKAGING_DEFECT` + `DEVELOPMENT_PROCESS_DEFECT`: mutable UMA was still the Safari containing host | Rejected APP_ONLY-with-nested-extension architecture; do not normalize re-enable after a mutable app update | Re-enables consumed here were avoidable. This class must not recur after Host split |
| O | Frozen-appex/outer-host rollback probes | Full appex bytes/CDHash/inode stayed fixed yet outer containing-host changes still lost enablement/reachability | Containing-host signed installation lifecycle | `IDENTITY_DEFECT` + `PACKAGING_DEFECT`: freezing only the nested appex did not preserve Safari's containing-host security surface | Entire signed Safari Host plus Companion must be immutable during ordinary UMA updates | No Human action for ordinary updates. A deliberate Host/Companion migration may require one Human enable |
| P | Immutable Host split, 2026-08-28 | Mutable UMA needed a stable Safari authority | Architectural boundary | `DEVELOPMENT_PROCESS_DEFECT` repaired by separate mutable app and immutable Host products | `Mutable UMA ↔ bounded App Group IPC ↔ immutable Safari Host ↔ Companion`; only Host dispatches and receives native callbacks | One enable is legitimate for the new immutable Host identity. Architecture remains correct subject to final examiner/live proof |
| Q | First immutable-Host signing attempt | Host/Companion profiles lacked the required shared App Group | Effective signed entitlements | `PROVISIONING_DEFECT`: App IDs/profiles did not contain the shared capability | Stop packaging; regenerate exact App Group profiles rather than widen entitlements or fall back to ad-hoc signing | Apple Developer profile action was legitimately Human-controlled; not a Safari re-enable |
| R | Host/Companion v2 plus Mutable App profile | Three installed profiles now include `group.com.silkrd.uma.test.bridge` | Profile/effective-entitlement validation | `PROVISIONING_DEFECT` repaired by exact capability assignment and regenerated profiles | Require profile contents **and** effective signed entitlements for mutable app, Host and Companion before packaging | No recurring Human action if profiles remain valid. Final signed-candidate audit is still pending |
| S | Immutable Host first provider gate | Machine path could work while `claude.ai` access was not granted | Safari website permission | `PLATFORM_SECURITY_RULE`: provider-site access is a distinct Human-controlled permission | Request only `https://claude.ai/new*`; exact hash route is revalidated before DOM; machine handshake remains content-free | One site-access grant is legitimate on first setup or a deliberate security migration. Normal UMA updates target zero prompts |
| T | Pre-`1805` navigation generation | Safari rejected an inactive-tab navigation call containing `active: false` | `tabs.update`/navigation API semantics | `WEBEXTENSION_SEMANTICS_DEFECT`: Chromium-oriented/redundant parameters were assumed valid in Safari | Remove unnecessary state mutation; audit every Safari API rather than patch one call | No Human action. The same class could recur unless the exhaustive API audit and synthetic lifecycle pass |
| U | Installed Host build `202608281805`, generation `e55245ee-7baf-4791-aadc-f13b52209986` | Event-Driven Companion was prepared after navigation repair, but enabling it would consume another migration before the full audit | Development freeze gate | `DEVELOPMENT_PROCESS_DEFECT`: extension-side defects were discovered sequentially after each migration instead of consolidated before a freeze | Suspend enablement; audit responsibility/API/state machine/IPC/tab safety; consolidate every known repair; mint one later final frozen generation only after QA/examiner | Human action is **not yet authorized or necessary**. `1805` is not final; the eventual final frozen generation has one budgeted enablement |

Why progress repeatedly exposed another gate: each repair often proved only the
immediately failing boundary, while the next extension-privileged transition
remained unexercised until a new signed generation was enabled. Mutable code
inside the Safari security surface amplified that workflow defect. The current
forensic Goal replaces sequential live discovery with a complete offline API,
state-machine, IPC, ownership, privacy, packaging and adversarial audit before
one final migration.

## 1B. Current forensic issues

| ID | Severity | Discovery / first boundary | Consolidated repair contract | Verification required | State |
|---|---|---|---|---|---|
| FORENSIC-01 | Blocking / tab safety | Reload recovery used tab-discovery assumptions that Safari does not authoritatively guarantee and could not safely distinguish tab-ID reuse | No general tab enumeration; same-lifecycle exact create ownership; after reload, only a request/generation/nonce-bound challenge from the already-bound exact-route content script may re-prove the tab; unproven tab is never closed | zero/one/wrong/multiple-equivalent proof, reload before/after attachment, user close, redirect, cancellation, expiry and cleanup races | CONSOLIDATED WIP; verification pending |
| FORENSIC-02 | Blocking / Safari semantics | Injection mixed Chromium `scripting` and Safari MV2 assumptions while the signed manifest does not grant `scripting` | Safari active path uses the manifest-authorized MV2 tab injection API; no unused update/reload/query gate; every parameter and error path audited | source/manifest contract, JavaScript syntax, synthetic provider pipeline and Safari review | CONSOLIDATED WIP; verification pending |
| FORENSIC-03 | Blocking / lifecycle | Host/client/content/extension deadlines disagreed and timeout acted as synchronization | Explicit acknowledgement phases with monotonically bounded deadlines; listener ready before dispatch; timeout only bounds a stalled phase | cold/warm/reload/slow/fast/disconnect/late-reply adversarial matrix | CONSOLIDATED WIP; verification pending |
| FORENSIC-04 | Blocking / IPC | Close/cancel commands could reuse the same request identity and terminal files could race or be consumed out of order | Single in-flight request; operation-specific correlation; exact generation/protocol; atomic one-terminal response; stale/duplicate/late responses rejected | Host restart, UMA restart, duplicate request/reply, cancellation, future/stale generation and terminal-order tests | CONSOLIDATED WIP; verification pending |
| FORENSIC-05 | Major / product truth | Browser availability, handshake, consent, site permission, provider read and Local Smart were collapsed into generic setup states | Formal orthogonal state matrix and precise user-visible reason; Local Smart/app shell never depend on Safari | all state combinations and failure-independence tests | CONSOLIDATED WIP; verification pending |
| FORENSIC-06 | Blocking / migration safety | A deliberate second Host migration path could replace the signed Host without first proving no owned-tab receipt remained | Migration-only installer must refuse active/cleanup-pending receipt, preserve canonical ownership, reject duplicate registration and record byte lock | packaging/profile/entitlement checks and safe migration dry run before any install | OPEN; final packaging/signing audit required |
| FORENSIC-07 | Major / diagnostics | Existing machine diagnosis could collapse the causal chain to one generic status | Content-free stage/reason receipts only: request/generation, package/runtime identity, protocol/version, timestamps and fixed failure enums | privacy scan plus first-missing-transition tests | CONSOLIDATED WIP; verification pending |

The current true Human-visible blocker is therefore not merely “extension
disabled.” It is the intentional forensic freeze on a non-final generation.
The underlying Apple cost is one Human enable for a genuinely new final
Host/Companion security identity or generation. Everything else above is UMA
engineering or workflow debt and must be closed before that budget is used.

```text
CURRENT HUMAN-VISIBLE BLOCK:
  Forensic freeze; installed Event-Driven generation 1805 is not final.

UNDERLYING CAUSE:
  Extension-privileged defects were migrated and discovered sequentially;
  current offline repair/verification has not reached the freeze gate.

PLATFORM OR OUR CODE:
  Platform: Human-controlled enablement and exact-site permission for a new
            deliberate Host/Companion security migration.
  UMA:      identity churn, mutable containing-host design, false state gates,
            API/lifecycle/tab/IPC defects and one-boundary-at-a-time workflow.

LEGITIMATE ENABLEMENTS:
  First signed Test identity; dedicated Test identity; first immutable Host
  identity. A later final frozen migration may consume one last enable.

AVOIDABLE ENABLEMENTS:
  Any repeat caused by duplicate inventory, mutable containing-app replacement,
  state-API false negatives, non-final extension rebuilds or sequential defect
  discovery.

CURRENT LATENT BLOCKERS:
  FORENSIC-01 through FORENSIC-07 remain verification/package gates.

FINAL EXPECTED BLOCK:
  One Human enable of the independently reviewed final frozen Companion, plus
  one exact-site grant only if Safari does not preserve it for that deliberate
  migration.

READY FOR ONE FINAL HUMAN ENABLE:
  NO
```

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

The two declarations above are historical Phase A evidence and do not establish
the current forensic candidate, final immutable-Host runtime, or current live
Accuracy Sync. They are superseded for present-tense readiness by Sections 1A
and 1B.

## M5RMX-CLAUDE-SMART-CLOSE-G1 issue ledger

This Smart-close ledger is retained as implementation lineage. In particular,
the ad-hoc/unsigned Test-package path in `SMART-CLOSE-06` is retired: the
current Test architecture requires an Apple Development-signed separate
immutable Host and Companion while Safari unsigned extensions remain off.
Every listed Human/live gate is suspended until the current forensic freeze
gate clears.

### Required closeout matrix

| ID | Required closeout truth | Current evidence / repair | Remaining acceptance gate | Status |
|---|---|---|---|---|
| SMART-CLOSE-01 | Desktop per-response event source NO-GO correctly represented | Source decision, dossier, runtime state, and UI classify Claude Desktop activity as unavailable; the plan cache is not treated as a response event | Full regression and Human product-state confirmation | MACHINE IMPLEMENTED / OPEN |
| SMART-CLOSE-02 | Desktop cache estimated-only | Strict v2 projection publishes newest bounded `fh`/`sd` only as `≈`, with no reset and below both exact sources | Full regression and Human estimate presentation | MACHINE IMPLEMENTED / OPEN |
| SMART-CLOSE-03 | Cache safety/fail-closed | Descriptor-bound `O_NOFOLLOW` reads enforce byte budget plus before/after identity, ownership, type, link, mode, size, and timestamp stability; unsafe data publishes nothing | Privacy review and full security regression | MACHINE IMPLEMENTED / OPEN |
| SMART-CLOSE-04 | Exact-vs-estimate precedence | Selector order is exact local status-line, exact one-shot Safari Accuracy, local/Desktop estimate, stale exact, then missing; window truth remains independent | Full regression and Human mixed-state confirmation | MACHINE IMPLEMENTED / OPEN |
| SMART-CLOSE-05 | Persistent Safari route retired | No scheduler capability or automatic cycle is advertised; legacy `automatic*` compatibility paths are inert unless an explicit one-shot request owns them | Independent source review and live absence check | MACHINE IMPLEMENTED / OPEN |
| SMART-CLOSE-06 | Accuracy Sync one-shot live acceptance | Request correlation, ordered inbound consumption, transactional anchor persistence, single in-flight ownership, and zero automatic retry are deterministic PASS; the temporary 0.13 development package may use truthful ad-hoc signing only while the Human-gated Safari unsigned-extension mode is enabled | Founder-triggered one-shot live acceptance, followed by extension removal and unsigned-mode restoration | HUMAN GATE / OPEN |
| SMART-CLOSE-07 | Temporary-tab cleanup | Extension closes only the freshly created, proven-owned inactive tab and fails closed on ownership uncertainty | Live user-tab preservation and cleanup evidence | HUMAN GATE / OPEN |
| SMART-CLOSE-08 | Exact anchor persistence after Safari quit | Exact Safari anchor is saved before publication; injected save failure rolls back and publishes no success | Live observation, Safari quit, retained-exact relaunch check | MACHINE IMPLEMENTED / OPEN |
| SMART-CLOSE-09 | Relaunch/no repeated setup | Persisted exact-anchor and local configuration tests retain truth without recurring dispatch or repeated setup | Physical relaunch acceptance | HUMAN GATE / OPEN |
| SMART-CLOSE-10 | Current governance supersedes obsolete architecture | Plan conflict fence, Goal/Scope/Decision/Dossier/Privacy truth, and current G2 contract all prohibit recurring Browser Sync restoration | Independent governance review | MACHINE IMPLEMENTED / OPEN |
| SMART-CLOSE-11 | Dirty WIP delivery classification | Starting 43 tracked plus 10 untracked paths were classified A-H; this repair adds only the owned descriptor helper and close-security regression; index remains empty | Final exact-path review, staged audit, commit, and clean delivery after Human PASS | DELIVERY GATE / OPEN |
| SMART-CLOSE-12 | Protected-provider/Assistant regression | Patch is Claude-local and governance-only; no provider action, Safari mutation, Apple operation, Desktop replacement, or protected-provider source repair occurred | Full protected-provider and accepted Assistant UIFIX regression | REGRESSION GATE / OPEN |

No SMART-CLOSE item is CLOSED until its listed full, independent, Human, or delivery gate passes.

| ID | Severity | Evidence / root cause | Implementation | Focused verification | Regression / Human gate | Status |
|---|---|---|---|---|---|---|
| SMART-01 | Blocking | Default connector owned a completion-relative Safari scheduler and persistent browser-source lifecycle | Removed automatic capability/scheduling; local refresh never dispatches Safari | One-shot dispatch test proves launch/timer/manual local refreshes create zero Safari requests | Full suite and Human lifecycle acceptance pending | IMPLEMENTED / OPEN |
| SMART-02 | Blocking | Official status-line input contains exact Pro/Max five-hour and seven-day fields but also broad sensitive context | Added bounded one-shot relay, strict allowlist projection, 4 KiB sanitized protocol, and owner-only atomic state | Projection, strict type/range, over-size, round-trip, and forbidden-field tests PASS | Live first-response callback pending | IMPLEMENTED / OPEN |
| SMART-03 | Blocking | One official status-line slot can conflict with existing Human configuration, while a whole-settings backup would retain unrelated preferences | Persist only the exact prior `statusLine` fragment plus whole-file digests/mode; preserve exact options; use one nonrecursive prior-command bridge; rebase unrelated edits only while field ownership remains exact; fail closed on external status-line drift | Fragment-only backup exclusion, existing-command preservation, unrelated-edit repair, external-status drift, recursive/secret rejection tests PASS | Human existing-configuration matrix pending | IMPLEMENTED / OPEN |
| SMART-04 | Privacy | Local activity records are prompt-bearing even though only usage metadata is needed; whole-file string materialization unnecessarily retained raw content in memory | Stream each bounded line, immediately project only allowlisted usage fields, discard raw bytes, and persist only aggregate token/model/time/coverage fields | Oversized line/file rejection and structural prompt/response/path exclusion tests PASS | Privacy Steward/full scan pending | IMPLEMENTED / OPEN |
| SMART-05 | Major | No accepted deterministic five-hour estimator existed | Added anchor-delta calibration with no fixed denominator, continuity generation, confidence, and monotonic remaining | Two-anchor requirement, deterministic coefficient, monotonic clamp, discontinuity tests PASS | Live same-time comparison pending | IMPLEMENTED / OPEN |
| SMART-06 | Major | Seven-day estimate must not reuse a five-hour denominator/state | Engine calibrates each window kind independently with separate anchors and prior-estimate state | Shared estimator is keyed by window; independent-window connector coverage pending | Full regression/live comparison pending | IMPLEMENTED / OPEN |
| SMART-07 | Major | Exact and estimated percentages were visually indistinguishable | Added source priority, provenance/confidence coverage, and `≈` presentation/accessibility for estimates | Source-order and presentation distinction tests PASS | Light/Dark × Regular/Minimalist Human matrix pending | IMPLEMENTED / OPEN |
| SMART-08 | Blocking | Browser path could accept unsolicited observations or retain recurring ownership | Native connector admits observations only during one explicit request; extension creates/closes one freshly proven-owned inactive tab and suppresses unsolicited callbacks | Unsolicited rejection, single dispatch, completion, no scheduler tests PASS | Signed Safari one-shot live test pending | IMPLEMENTED / OPEN |
| SMART-09 | Major | Legacy permanent-tab record could be adopted/reloaded across cycles | Stale records close only with exact proof; otherwise fail closed; new request always creates a fresh ephemeral tab | JavaScript ownership/static checks pending QA runner | Live user-tab preservation pending | IMPLEMENTED / OPEN |
| SMART-10 | Major | Settings described mandatory Browser Sync and recurring Safari controls | Replaced consent/source disclosure with Local Smart setup, local refresh, explicit Accuracy Sync, repair and restore states | Source/UI compile and focused model tests PASS | Human Settings acceptance pending | IMPLEMENTED / OPEN |
| SMART-11 | Blocking | Disconnect must not overwrite concurrent Claude settings, falsely claim success after restore failure, or leave unsafe UMA state | Disconnect stops listeners/tasks and clears UMA data, then restores only the owned field; it reports disconnected and clears consent only after restore succeeds, otherwise retains repair metadata and surfaces Repair required | Exact fragment restore, unrelated-edit repair, external-status drift, and transactional failure tests | Interrupted/crash/absence matrix pending | IMPLEMENTED / OPEN |
| SMART-12 | Protection | Historical notarization success could trigger an unauthorized development submission | Goal/package records classify Apple submission, resubmission, and polling as forbidden | Source/package diff audit pending examiner | Apple actions in this Goal must remain zero | CONTROL ACTIVE / OPEN |
| SMART-13 | Major / truth | Mixed exact and estimated windows inherited one channel-level estimated marker | Added a per-window estimate marker and made compact/detail presentation derive `≈` from the selected/individual window only | Mixed five-hour exact plus seven-day estimated regression proves independent markers in both presentation projections | Full regression and Human mixed-state inspection pending | IMPLEMENTED / OPEN |
| SMART-14 | Blocking / first-use | Waiting for the first status-line callback hid Accuracy Sync, so a user could not obtain the first on-demand exact anchor | Exposed Accuracy Sync while `waitingForUsagePage` without changing its explicit one-shot lifecycle | Settings contract test proves first-waiting state exposes the secondary action | Human first-setup acceptance pending | IMPLEMENTED / OPEN |
| SMART-15 | Major / transparency | Settings did not state estimate confidence or when exact truth was last observed | Added sanitized confidence and last-exact fields to the account channel and compact localized Settings disclosure | Model/presentation/localization assertions PASS | Human EN/zh-CN acceptance pending | IMPLEMENTED / OPEN |
| SMART-16 | Minor / copy regression | Recovery messages still described retired recurring Browser Sync | Replaced recovery language and residual runtime provenance with one-shot Accuracy Sync wording | Source/localization assertion rejects Browser Sync recovery copy | Full source scan pending | IMPLEMENTED / OPEN |
| SMART-17 | Blocking / continuity | Schema, exact-source class, or unknown/changed model family could be treated as one estimator calibration | Split continuity on source/schema change; require both calibration anchors and the projection anchor to share source/schema and require a known unchanged model family | Deterministic schema/source split and nil/changed model invalidation tests | Full regression/live comparison pending | IMPLEMENTED / OPEN |
| SMART-18 | Privacy / filesystem | Sanitized state, anchor, and local JSONL reads previously used validate-then-reopen or path-based loading that could race replacement or growth | Read through one `O_NOFOLLOW` descriptor; enforce preallocation and actual-byte budgets; compare before/after descriptor identity, UID, regular type, link count, owner-only mode, size and timestamps; revalidate the path identity after reading | Symlink, replacement, post-read mutation/growth, oversize and unsafe-mode old-fail/new-pass tests | Privacy Steward and full regression pending | IMPLEMENTED / OPEN |
| SMART-19 | Blocking / package provenance | The existing `m5rmx-smart-preflight` path names only the accepted baseline HEAD, and that earlier candidate already exists and must not be overwritten by the repaired working tree | Add a distinct `m5rmx-smart-live-link-preflight` phase whose exact durable output and task-owned scratch path include the explicit 12-digit build; retain honest working-tree provenance, Developer-ID/Hardened Runtime/timestamp audits, and the no-notarization gate | Deterministic package contract asserts build-qualified non-overwriting paths, explicit build input, required Developer ID, unchanged audits, and zero notarization | Fresh candidate build remains a later primary-agent gate; the earlier candidate must not be overwritten | IMPLEMENTED / OPEN |


| SMART-20 | Blocking / ordering | Native handoff delivered observation and completion callbacks through independent unstructured tasks, allowing completion to overtake the observation | Route every inbound observation and automation event through one lock-ordered, single async consumer before connector handling | Paired 250-cycle ordering stress regression | Full regression pending | IMPLEMENTED / OPEN |
| SMART-21 | Blocking / truth | Safari exact state could publish even when durable anchor persistence failed because save errors were discarded | Snapshot anchor and continuity state, require anchor-store save success, roll back on error, and increment success diagnostics only after the transaction commits | Injected save-failure regression proves zero exact publication and zero accepted count | Full regression pending | IMPLEMENTED / OPEN |
| SMART-22 | Major / user-tab safety | The Settings website-access action opened a provider page before bounded one-shot work existed | Restrict permission repair to Safari extension settings; only explicit Accuracy Sync may create its freshly owned inactive Usage tab | Source regression and one-shot lifecycle suite | Human one-shot tab-preservation gate pending | IMPLEMENTED / OPEN |
| SMART-23 | Blocking / post-migration packaging | The internal compatibility package path resolves through a symlink and the package helper correctly refused it, but it still named that legacy path as canonical | Move current delivery directly to `/Volumes/HE/DEV/UMA/Packages`; require the exact `/Volumes/HE/DEV` APFS mount, current-user ownership, writable non-symlink base/root, canonical exact output, and existing-artifact refusal | Focused package contract, phase-boundary probes, shell syntax, and diff check | Actual ad-hoc candidate build remains a primary-agent gate | IMPLEMENTED / OPEN |

No issue above is CLOSED until the required full regression, independent
review, Human acceptance, and final clean delivery gates pass.

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
| current Claude mechanism | Local Smart Mode uses the official status line as primary; Safari Accuracy Sync is explicit one-shot secondary | source map and independent examiner PASS |
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

## 7. UMA 0.13 single-active development baseline

### Owned Provider Tab V2 lifecycle issues

| ID | Severity | Discovery | Root cause / classification | Repair or control | Verification | State |
|---|---|---|---|---|---|---|
| OWNEDTAB-V2-001 | Blocking / lifecycle | The real signed Accuracy Sync produced `refreshStarted → receipt save → receipt activate → receipt remove → tabUnavailable` before any provider observation | The old design proved an internal bootstrap and reused its tab ID as the provider authority; Safari retired that identity during cross-origin self-navigation and the global `onRemoved` path deleted the whole receipt | Create the provider tab directly; independently prove the provider document through a top-frame internal Port, one-time nonce digest, exact request/generation and authoritative `sender.tab.id`; retire bootstrap self-navigation | Permanent old-model-fail/new-model-safe regression, event reducer, 937/937 final offline regression and independent examiner PASS; one signed live acceptance remains | OFFLINE CLOSED — signed V2 recovery/live acceptance pending |
| OWNEDTAB-V2-002 | Blocking / privacy | A create result, URL marker, removal/replacement event or one pending request could be mistaken for ownership | None of those observations proves that the extension controls the provider document, and a provider page may observe a fragment | Persist only a nonce digest; require internal Port sender identity, exact top frame/provider surface/current generation; never accept page messaging or caller tab IDs; never close an unproven tab | PASS — spoof, wrong-frame/origin/generation, replay, duplicate-tab, receipt allowlist and raw-content denylist tests; Privacy Steward and examiner approve the content-free ownership boundary | OFFLINE CLOSED — signed V2 recovery/live acceptance pending |
| OWNEDTAB-V2-003 | Blocking / recovery | Background reload and arbitrary `onRemoved` / `onReplaced` ordering were not modeled | The old callback graph mutated receipt state ad hoc and had no replacement semantics | One revisioned durable reducer; bounded content-script reconnect; replacement IDs remain candidates until independent proof; no tab enumeration; ambiguous loss becomes one blocking tombstone | PASS — crash windows A-I plus 32,768 seeded state transitions cover permutations, cleanup-at-most-once, positive receipt removal and no resurrection; examiner PASS | OFFLINE CLOSED — signed V2 recovery/live acceptance pending |
| OWNEDTAB-V2-004 | Blocking / provider-route lifecycle | The signed V2 recovery generation passed its content-free handshake and 10/10 stability, but its sole real Accuracy Sync ended with no exact observation, `tabCleanupFailed`, and an absent receipt | V2 put the nonce after the provider's hash route and waited for asynchronous durable ownership acceptance before removing it. Claude's SPA could canonicalize that non-exact hash first; the later marker finalizer then rejected the already-canonical Usage route, emitted ownership loss, safely closed the proved tab and removed the receipt | Capture the fragment nonce in the isolated content script and synchronously replace the marked hash with the exact Usage hash at `document_start`, before opening the ownership Port. Revalidate the exact canonical route with the same captured nonce after durable ownership acceptance; every different route/nonce still fails closed | PASS — permanent old-deferred-removal-fail/new-document-start-pass race regression; 20/20 focused V2 lifecycle tests; JavaScript syntax and scoped diff checks. A fresh signed generation and one new live probe remain authorization/Human gates | SOURCE REPAIRED — fresh signed live acceptance pending |

The sole authorized V2 recovery generation was packaged and installed for the
next Human gate as build `202608282315`, runtime generation
`2ee91662-ac33-4387-ab58-c7bff6492405`, Host CDHash
`dca2f7356fb74b40aa270fc7ec00e8a5c9720244`, and Companion CDHash
`2b9d9de314b8223903dcb54344fde2922a31fa27`. The exact archive SHA-256 is
`10b527593e9bb716babf2a9786583c7f4782def59f34a96d428bc00553d7586f`.
Strict nested signature verification passed, the provisioning profiles and
effective entitlements contain only the expected shared App Group, PlugInKit
reports one canonical registration, the V2 package contains no bootstrap
resource, and the owned-tab receipt is clear. Content-free handshake and 10/10
stability passed after the Human enabled this generation. Its sole authorized
real Accuracy Sync exposed `OWNEDTAB-V2-004`; no exact quota value or raw page
content was retained, and the provider-read budget is consumed. The issues
remain live-open until a fresh repaired generation is signed, enabled and
accepted through the full one-shot lifecycle.

| ID | Severity | Discovery | Root cause / classification | Repair or control | Verification | State |
|---|---|---|---|---|---|---|
| BASELINE-013-001 | Blocking / environment | Desktop UMA 0.12 and its 1.2.3 Browser Companion were still the active registered development environment | Re-registering legacy 0.12 after every candidate test caused same-identifier ambiguity and made real live evidence non-atomic | Archive exact 0.12 bytes outside Desktop, retire its registration permanently from active testing, preserve 0.11, and install only UMA 0.13.0 | PASS — Desktop 0.12 moved to the unique legacy archive recorded below; pre/post relative-path content-manifest and executable hashes match; Desktop 0.12 is absent; Desktop 0.11 is byte-preserved; exactly one 0.13 process and one 1.4.0 registration remain | CLOSED |
| BASELINE-013-002 | Blocking / package identity | The prior live-link preflight still reported app version 0.12 and extension 1.3.0/build 8 | No package phase represented the Founder-selected single-active 0.13 baseline | Add `m5rmx-smart-0.13-preflight`; report app 0.13.0 and extension 1.4.0/build 9; require a unique persistent output, explicit build, strict nested signing, and zero notarization. Developer ID remains required for signed/final phases; this one temporary development phase alone may use truthful ad-hoc signing while Human-gated unsigned-extension mode is enabled | PASS — the final pre-Human package and Desktop copy report app 0.13.0/build 202608200003 and companion 1.4.0/build 9; package/Desktop executable hashes match; normal-macOS strict nested signature verification passes; no notarization occurred | CLOSED |
| SMART-LINK-001 | Blocking / live local link | Real responses in the active Claude Desktop surface produced no status-line receipt. The first broken boundary is configuration scope: the historical Desktop 1.32885.1 observation embeds Claude Code 2.1.234 but its provider-owned local-agent host loop launches the executable with a session-specific `CLAUDE_CONFIG_DIR` under its own session storage, so the active surface does not resolve UMA's `~/.claude/settings.json`. No active CLI child or current Desktop session config directory existed during the bounded check. | Keep the official `statusLine` integration primary for supported Claude Code surfaces. Remove the permanent diagnostic `Stop` hook/receipt path and migrate an exact older UMA-owned hook away without modifying Human hooks. Do not inject UMA settings into undocumented ephemeral Claude Desktop session directories. When sanitized local activity exists without an exact status-line anchor, report `Activity detected — awaiting exact usage anchor` instead of claiming that Claude is inactive or asking for another response/session. | Local relay projection/write and exact UMA ingestion transport were independently proven, excluding relay, destination, watcher, race, schema, and UI-ingestion failures. Deterministic tests cover status-line-only configuration, Human hook preservation, no permanent Stop hook, pending/rejected/exact recovery, and truthful activity-without-anchor state. The current user integration was migrated in place from schema 3 to schema 4: the exact UMA diagnostic Stop hook count is zero, no Human Stop hook was removed, the official status-line command remains present, owner-only modes remain `0600`, and the receipt file is absent. | EXTERNAL SURFACE LIMITATION PROVEN / PRODUCT STATE REPAIRED; exact status-line quota remains unavailable in this Claude Desktop surface |
| SMART-LINK-002 | Major / settings lifecycle | The installed 0.13 candidate remained indefinitely at `Checking local status-line integration…` before the first callback | `checkCompanion()` mapped an installed configuration with no existing snapshot back to `.checking` without starting a connector sync; the action lifecycle also waited for unrelated global admission refresh work before clearing its local busy state | An installed configuration now performs one local `syncNow()` unless it already has Fresh/Cached/Stale truth. Local action state clears immediately after the connector snapshot is presented, before the global admission refresh completes | PASS — focused Local Smart suite `29/29`; an old-fail/new-pass test blocks the global admission refresh and proves the installed check still leaves `.checking`, clears `activeAction`, and clears `actionInProgress` | CLOSED for source; repaired 0.13 package and physical recheck pending |
| ACCURACY-LINK-001 | Blocking / live Safari link | Prior Accuracy Sync produced no admitted callback | Duplicate registered containing apps made same-identifier dispatch provenance ambiguous; request readiness/correlation also required hardening | Retire every legacy registration; use sole 0.13/1.4.0 registration; require exact version/build/schema readiness and requestID-correlated one-shot callback | deterministic one-shot/protocol tests PASS; single-active live observation pending | OPEN |
| SMART-DESKTOP-001 | Major / source coverage | Claude Desktop does not resolve UMA's user-scope status-line configuration, while the earlier WIP attempted to scan an additional undocumented Desktop JSONL hierarchy | Desktop needs a distinct non-additive source and the Founder authorized only the exact provider-owned `plan-usage-history.json` cache | Removed the Desktop JSONL production root. Added a strict v2 exact-path reader that projects only the newest `fh`/`sd` sample and timestamp, discards `org`, converts used to remaining once, exposes no reset, and publishes only `≈` low-confidence estimates | PASS — dedicated Desktop suite 9/9; focused Desktop + Smart 44/44; final serialized UI 754/754 plus bridge 20/20; Debug, Release, strict-concurrency Release, native host and status-line relay builds PASS; Human product validation pending | IMPLEMENTED / HUMAN GATE |
| SMART-DESKTOP-002 | Major / privacy and truth | An undocumented provider cache could be mistaken for official exact quota or combined with token activity | Cache ancestry is undocumented/private and contains organization plus history fields outside UMA.s allowlist | Version-pin schema 2; reject unknown fields and unsafe files; read through one descriptor with bounded allocation and post-read identity/metadata verification; keep cache estimate separate from JSONL activity and exact anchors; exact status-line and Safari Accuracy outrank it; UI `≈`; no reset/API replay/raw persistence | Focused descriptor-integrity and Desktop source tests added; independent privacy and full regression recheck pending | IMPLEMENTED / OPEN |
| SMART-DESKTOP-003 | Blocking / live activity truth | Repeated real Claude Desktop responses produced no sanitized activity receipt; the plan cache did not provide per-response evidence | Desktop 1.34493.0 still provides no admitted response event; Desktop does not resolve UMA's Claude Code status-line scope, and the authorized plan cache has quota-refresh rather than response-notification lifecycle semantics | Classify Desktop activity as unavailable under the current authorized architecture; retain the cache only as an `≈` estimate, pass no projects reader for Desktop-only installs, label mixed-install activity as Claude Code only, and never treat cache metadata change as response activity | Old-fail/new-pass tests cover fresh-estimate, missing-estimate, Desktop-only deduplication, mixed-surface labeling, maximum-timestamp selection for out-of-order cache samples, tied-newest fail-closed behavior, intermediate-directory symlink rejection, and complete post-read metadata revalidation; focused Desktop 16/16 and combined Desktop + Local Smart 51/51 PASS; affected Safari privacy separation 4/4 PASS | IMPLEMENTED / FOCUSED PASS |

Current development truth:

```text
UMA 0.13.0: current single-active development target
UMA 0.12: legacy archive; not active, registered, or launched
UMA 0.11: protected rollback
Claude default: Local Smart Mode
Safari: explicit one-shot Accuracy Sync only
Persistent Safari Browser Sync: retired
Development notarization: not performed or required per iteration
Final notarization: required only for later frozen release bytes
```

Phase A external evidence:

```text
UMA 0.13 SINGLE-ACTIVE DEVELOPMENT BASELINE — PASS
Legacy archive: /Users/juliushe/Developer/UMA-Archive/legacy-0.12-20260820T002819Z/UMA_0.12.app
Legacy 0.12 main SHA-256: e95e2dac12383016f179564de2cc7e0db2fcccd3d7758a95129f18aa8e8145df
Legacy 0.12 relative content-manifest SHA-256: 6d3e2635f07bd0c3f37de756bea340b9e0612a100caf7afebe20eecdd618de62
Protected 0.11 main SHA-256: 88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
Superseded 0.13 archive: /Users/juliushe/Developer/UMA-Archive/superseded-0.13-202608200001-20260820T012901Z/UMA_0.13.0.app
Superseded repaired-predecessor archive: /Users/juliushe/Developer/UMA-Archive/superseded-0.13-202608200002-20260820T030000Z/UMA_0.13.0.app
Development package: /Users/juliushe/Developer/UMA-Packages/uma-0.13-dev-af2317dd5109-202608200003/UMA_0.13.0.app
Active Desktop app: /Users/juliushe/Desktop/UMA_0.13.0.app
Containing app / companion: com.silkrd.uma 0.13.0 build 202608200003 / com.silkrd.uma.ClaudeBrowserCompanion 1.4.0 build 9
Main / native host / status relay / companion executable SHA-256: 97686d5dccf44f8a69e2670222e9a5b2dba51efcb394681e8d290cdf547ee97b / 267edc9ea55bd4f5d0ce08387e806fe5d064f819f441cbe0014920acce329fb8 / ab825ef8c16d93fb53cb7915ec796c1ef1b0eb14d94035e43fffa58f9981f87f / d537e907717c2bb4c3b547ad956be5c1052f3f68d1406f09f854c1f544d04c5d
Registered companion count: 1, owned by the active Desktop 0.13 app
Active UMA process count: 1, exact Desktop 0.13 executable
Apple submissions / notarizations: 0
```
### OWNEDTAB-V2-005 — transient provider routing terminated the bounded readiness cycle

- Severity: major live acceptance blocker
- Discovery: the first repaired V2 live Accuracy Sync completed proven-tab cleanup but returned `routeRejected` before any exact anchor.
- Root cause: after ownership proof, Claude's SPA could temporarily move within the provider-owned `/new` route family. The extractor treated that transient state as immediately terminal even though a bounded readiness window was already active.
- Repair: exact-route validation remains mandatory before every DOM inspection, while content-free same-origin `/new` routing transitions may wait only within the existing readiness deadline. Non-provider routes still fail immediately; an exact route that never renders landmarks remains `usageUnavailable`.
- Focused verification: old-fail/new-pass routing model proves zero DOM inspection while non-exact, successful exact-route recovery, and terminal `routeRejected` at bounded expiry.
- Privacy: no URL, DOM, quota value, identity, credential, cookie, or token is retained by the routing classifier.
- Live verification: pending a newly signed Companion generation and separately authorized one-shot Accuracy Sync.
- State: REPAIRED OFFLINE / LIVE REQUALIFICATION REQUIRED

### OWNEDTAB-V2-006 — provider readiness and partial-render hardening

- Severity: blocking latent provider-layer risk
- Discovery: the live transient-route failure showed that the earlier static fixtures did not model Claude's SPA event order after ownership proof.
- Root cause: the content script coupled route admission, document readiness and first-success extraction. A single non-exact route, partial card render or transient sign-in landmark could end or misclassify the request before provider state stabilized.
- Repair: one event-driven readiness reducer consumes hash, history/navigation, document and bounded mutation signals. It performs zero DOM access before the exact Usage route and a ready document, requires two equivalent sanitized projections before success, requires two sign-in confirmations, and maps only fixed content-free failure reasons at the existing deadline. No interval, rapid polling or timeout inflation is used.
- Focused verification: the production JavaScript SPA harness covers initial non-Usage route, exact to transient to exact, delayed mount, one final data mutation, partial data, node replacement, transient and persistent sign-in, background reconnect and one-result delivery.
- State: SOURCE CLOSED / FREEZE EXAMINER PENDING

### OWNEDTAB-V2-007 — result delivery could outrun proven cleanup

- Severity: blocking lifecycle/privacy
- Discovery: adversarial causal review found that native observation delivery occurred before tab/receipt cleanup and could hang with `read.finished` already set.
- Root cause: result publication and cleanup were separate asynchronous messages with competing timeout and callback lifecycles.
- Repair: retain the sanitized projection only in extension memory, close the exact proven tab and compare-delete the durable receipt first, then emit one request- and generation-bound terminal packet containing the observation. Any cleanup failure suppresses the observation and overrides the provider classification. Host timeout now issues a correlated close transaction before returning failure.
- Focused verification: protocol, Host IPC, cleanup-failure, stale/duplicate result, cold-start handoff and causal-response tests pass; exact anchor publication requires the single post-cleanup terminal packet.
- State: SOURCE CLOSED / LIVE REQUALIFICATION REQUIRED

### OWNEDTAB-V2-008 — reload and cleanup crash gaps

- Severity: blocking lifecycle
- Discovery: adversarial recovery review found stranded `CLEANUP_REQUESTED` receipts, expired proven receipts, a lost result after background reload, and untested Safari replacement/removal event order.
- Root cause: recovery assumed a live provider Port for every cleanup and rejected a late correlated result once the background had reloaded.
- Repair: exact-ID `tabs.get` may prove tab absence without enumeration; a present tab must reprove the exact request/tab/generation before cleanup-only close. Expired proven receipts use the same path and never extract. One exact sanitized result may replay once after recovery and is stopped by an explicit ACK. The production reducer coalesces both replacement/removal orderings without transferring ownership.
- Focused verification: crash points around removal/confirm/terminal/delete, expiry, both Safari event orders, result replay/ACK, wrong generation and unknown-tab fail-closed cases pass.
- State: SOURCE CLOSED / LIVE REQUALIFICATION REQUIRED
