# UMA M5 Claude QA Issue Ledger

## M5-OAUTH-G1 issue ledger

| ID | Found by | Severity | Evidence | Acceptance impact | Repair owner | Repair | Focused retest | Regression retest | Final status |
|---|---|---:|---|---|---|---|---|---|---|
| M5OAUTH-001 | Founder / DEV | Blocking | The production Claude path depended on status-line configuration and provider activity | No automatic quota without Terminal or a Claude response | Implementer | Replaced the product path with an isolated signed quota broker, consent controller, completion-relative scheduler, and current-read admission; the historical relay executable target is removed and only reviewable core source remains | Broker build and syntax verification PASS | Full verification pending | Implemented; final verification pending |
| M5OAUTH-002 | Protocol Auditor | Blocking | The candidate endpoint is undocumented and references disagree on low `utilization` scaling | Ambiguous quota could be shown incorrectly | Implementer | Prefer explicit `used_percentage`; interpret zero as zero, values strictly between zero and one as fractions, values above one through 100 as percentages, reject the ambiguous literal one and contradictory dual fields | Decoder-focused source verification PASS | Full verification pending | Implemented; final verification pending |
| M5OAUTH-003 | Privacy Steward | Blocking | Public evidence names a Keychain service and Claude stores the current-user item under the local account name | Broad search or identity leakage would violate the credential boundary | Implementer | The broker performs a two-stage exact-item lookup: fixed service/account to persistent-reference-only results with exactly-one enforcement, then data-only lookup by that opaque reference; no attributes, identity, fallback query, or main-process output | Synthetic Keychain lifecycle, duplicate-result, permission-denied, and source-boundary tests PASS | Full privacy audit pending | Implemented; final verification pending |
| M5OAUTH-004 | QA Runner / Privacy Steward | Blocking | Existing Claude cache behavior could show a prior credential's quota after rotation followed by a transient request failure | Cross-credential stale presentation is forbidden | Implementer / QA | Preserve current-session Cached/Stale only after the session broker proves the currently read exact credential matches the successful-read keyed continuity baseline; all changed or unknown cases withdraw; hard-expire retained data after 30 minutes | Core continuity 15/15 and focused OAuth/UI 98/98 PASS | Full verification pending | Repaired; final verification pending |
| M5OAUTH-005 | Protocol Auditor | Major | Existing package scan treats all authorization and OAuth symbols as globally forbidden | Broker-specific required constants could be hidden or main-process leakage missed | QA | Split main and broker audits: main executable rejects Keychain, endpoint, bearer, token and private-route strings; broker narrowly requires the exact transport constants while rejecting refresh-token and private-data fields | Package-helper syntax PASS | Commit-exact package audit pending | Implemented; final verification pending |
| M5OAUTH-006 | DEV | Gate | Installed `/Applications/Claude.app` trust was disputed during parallel review | Login activator must not target an untrusted provider app | DEV | Re-ran strict deep signature and Gatekeeper assessment; Developer ID team Q6L2SF6YDW and notarized acceptance pass | PASS | N/A | Closed |
| M5OAUTH-007 | Privacy Steward | Blocking | Main process read helper stdout with an unbounded `readToEnd()` before checking the 8-KiB cap | A compromised helper could force unbounded allocation | Implementer | Read helper output concurrently in bounded chunks, drain without retaining overflow, enforce the 8-KiB cap before decode, and reap the child on cancellation/timeout | Process/privacy suite PASS | Full verification pending | Repaired |
| M5OAUTH-008 | Protocol Auditor / QA Runner | Major | Manual Sync Now could bypass an already-established 429 cooldown; disconnect could race official-app activation; credential and quota schema failures shared one message | Retry storm, late state resurrection, and misleading recovery guidance | Implementer | Added an absolute retry boundary checked by every trigger, generation guard after activation, deferred admission refresh during login wait, and distinct safe lifecycle messages | Connector 13/13, refresh 6/6, transport 4/4 PASS | Full verification pending | Repaired |
| M5OAUTH-009 | Privacy Steward | Blocking | A one-shot stateless broker could not compare the current exact credential with the credential used for the prior successful read without exporting credential-derived metadata | Required same-session Cached/Stale could not be proven safe | Founder / Implementer | Founder explicitly authorized one parent-owned session broker with a random memory-only HMAC key, one broker-private credential digest, fixed continuity classifications, mandatory invalidation, and no cross-launch state | Core continuity 15/15 and focused OAuth/UI 98/98 PASS | Full privacy and package verification pending | Repaired; final verification pending |
| M5OAUTH-010 | Independent Implementer Review | Blocking | The packaged broker validated its helper and host only from the parent side; identifier-only parent checks were forgeable under ad hoc signing | IPC lacked broker-side authenticated package provenance | Implementer | Before session creation or Keychain access, authenticate the live parent PID, exact package-relative host/helper paths, owner UID, strict signatures, and equality between the live parent's static identifier/CDHash and the exact packaged host's static identifier/CDHash | Parent-auth decision matrix and source-order checks PASS | Commit-exact package launch pending | Repaired; final verification pending |
| M5OAUTH-011 | Independent Implementer Review / Privacy Steward | Blocking | Raw Keychain data could be aliased, the decoded token object lived across the request, and a second lookup multiplied Keychain access | Credential lifetime and read count exceeded the single-request minimum | Implementer | Move the raw record bytes rather than copy them, clear the moved raw bytes before transport, perform exactly one two-stage lookup, clear the mutable request buffer immediately after transport, release the immutable header projection before suspension, and invalidate the ephemeral session on every path | Credential lifecycle, one-read, disposal-order, and privacy source checks added | Full verification pending | Repaired; final verification pending |
| M5OAUTH-012 | Independent Implementer Review / Protocol Auditor | Major | Stale cutoff originally depended on a later getter or view access | Stale quota might outlive the approved bounded provider interval | Implementer | Added an autonomous retention timer: Stale after five minutes and hard withdrawal after 30 minutes in the current UMA/broker session | Deterministic autonomous Cached → Stale → withdrawn test added | Full verification pending | Repaired; final verification pending |
| M5OAUTH-013 | Protocol Auditor | Major | A queued manual follow-up could bypass the 180-second provider-read cadence | Repeated Refresh could multiply provider reads | Implementer | Apply one completion-relative `readNotBefore` boundary to manual, shared, launch, timer, reconnect, and queued follow-up triggers; retain only one Boolean follow-up | Deterministic manual-during-read and boundary tests added | Full verification pending | Repaired; final verification pending |
| M5OAUTH-014 | Protocol Auditor | Major | Six-second login polling timers contradicted the no-timer interactive-login contract | Login UI could cause background Keychain and quota polling | Implementer | Removed login polling entirely; Check Again, Sync Now, or shared Refresh resumes the existing consented connection without requiring a second Connect | Login-wait and continuation tests added | Full verification pending | Repaired; final verification pending |
| M5OAUTH-015 | Privacy Steward | Blocking | A missing expiry field could be accepted and request completion used a stale clock | Invalid or expired credentials could reach or survive a quota operation | Implementer | Require an expiry field and validate captured expiry again against a fresh post-transport clock before any quota result is accepted | Missing-expiry and expiry-during-transport tests added | Full verification pending | Repaired; final verification pending |
| M5OAUTH-016 | Privacy Steward | Major | The retired status-line relay executable remained buildable | A retired product route could be accidentally repackaged | Implementer | Removed the `ClaudeStatusLineRelay` executable target while retaining historical core source only for reviewable tests and records | Manifest and package-helper source checks added | Commit-exact contents audit pending | Repaired; final verification pending |
| M5OAUTH-017 | Privacy Steward | Major | A predecessor sanitized connector snapshot may already exist on disk while Settings said only preferences were stored | Storage disclosure and cross-launch admission needed an honest fail-closed contract | Implementer | Current OAuth source writes no Claude quota; restore remains disabled so any already-existing sanitized historical record stays hidden and unusable, and Settings explicitly discloses that possibility | Restore-disabled and transparency source checks added | Physical Settings verification pending | Repaired; final verification pending |
Date: 2026-07-28

## Current M5-SETUP-G1R decision

**GO — CLAUDE STATUS-LINE QUOTA SOURCE PROVEN**

## Historical M5-G1R decision

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

## Evidence boundary

The QA program uses current official documentation, sanitized local
presence/type classifications, and synthetic fixtures only. It contains no raw
provider payload, real quota value, credential, account identity, settings
backup, private path, transcript, prompt, response, task, or tool content.

## M5-G1R issue ledger

| ID | First evidence | Severity | Root cause | Repair / decision | Focused retest | Affected retest | Status |
|---|---|---:|---|---|---|---|---|
| M5G1R-001 | Desktop-managed Claude Code 2.1.219 arm64 executable is present | High | Claude Desktop installed a trusted native component without the normal user launcher | Record the exact distribution class; do not install or repair it in M5-G1R | 25/25 PASS | Trust checks PASS | Closed |
| M5G1R-002 | Native signature and Gatekeeper pass while standalone-manifest checksum differs | High | The app-wrapped Desktop artifact is not the standalone release artifact | Trust the notarized Desktop distribution without claiming standalone-manifest equivalence | 25/25 PASS | Temporary manifest artifacts removed | Closed |
| M5G1R-003 | Doctor and auth status both report logged out | Blocker | Provider-managed subscription authentication is inactive | Return `SETUP REQUIRED`; do not open login or install a probe | 25/25 PASS | Secret-route names absent | Open setup condition |
| M5G1R-004 | Local settings sources and `statusLine` are absent | High | No local configuration exists; global policy remains unobservable while logged out | Preserve absence; create no backup and perform no mutation | 25/25 PASS | Exact absence recheck PASS | Closed |
| M5G1R-005 | No provider-generated status-line event is admissible | Blocker | Authentication failed before the event gate | Do not inspect or alter the reported Human task; classify all payload fields unsupported | 25/25 PASS | Payload contract tests PASS | Open setup condition |
| M5G1R-006 | Used values must convert to remaining exactly once | High | Provider semantics and UMA display semantics are opposite | Validate then convert in the shared model; UI and Maximum Decrement consume remaining only | 25/25 PASS | Conversion and affected 48/48 PASS | Closed |
| M5G1R-007 | Delivery must remain documentation/test-only | High | Runtime changes would prematurely begin M5-G2 | Lock the same six paths and independently audit the staged index | 25/25 PASS | Exact-scope and staged-index audits PASS | Closed |

## Required focused coverage

The M5-G1R suite must prove:

- exact allowlist projection;
- trusted-CLI plus logged-out admission returns `SETUP REQUIRED`;
- provider-managed authentication is accepted only when explicitly proven;
- secret and enterprise routes fail closed;
- explicit forbidden and unknown-field rejection;
- exact used-to-remaining examples for 0, 1, 36.25, 99.9, and 100;
- fail-closed negative, over-100, nonnumeric, null, and nonfinite values;
- integral Unix-second reset validation;
- rejection of millisecond-shaped reset values;
- independently absent five-hour and seven-day windows;
- atomic rejection of incomplete windows;
- no inferred zero or full remaining usage;
- conversion occurs once in the shared presentation model;
- UI sources do not repeat the conversion;
- Maximum Decrement consumes remaining values only;
- optional bounded version handling;
- absent, malformed, hook-disabled, managed-policy, and existing-status-line
  settings fixtures;
- owner-only backup fixture permissions;
- byte-exact synthetic restoration preserving formatting and final newline;
- no probe or mutation plan when authentication is absent;
- agreement across all five durable records;
- exactly one next task, M5-SETUP-G1.

## Verification results

Actual pre-staging command evidence:

- Focused source-admission tests: 25/25 PASS
- Affected provider-neutral tests: 48/48 PASS across four suites
- M4 retirement regression: PASS within the affected 48-test run
- Secret-value scan: PASS
- Private-data scan: PASS; private field names occur only in the denylist and
  explicitly synthetic negative fixtures
- Raw-payload/generated-artifact scan: PASS
- Production source/package-configuration unchanged audit: PASS
- Exact settings-absence and temporary-artifact cleanup audit: PASS
- `git diff --check`: PASS
- Independent staged-index review: PASS; no material findings

## Completion rule

M5-G1R may close only when the durable records and focused tests agree on:

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

M5-G2 remains locked. The only next task is M5-SETUP-G1.

## M5-SETUP-G1 completion addendum

The M5-G1R ledger above is retained as historical admission evidence.

| ID | First evidence | Severity | Repair / decision | Verification | Status |
|---|---|---:|---|---|---|
| M5SETUP-001 | Trusted Desktop-managed CLI was logged out | Blocker | Human completed only the official Claude.ai paid-subscription browser login | Sanitized final class: logged in, `claude.ai`, `firstParty` | Closed |
| M5SETUP-002 | Normal shell could not resolve `claude` | Blocker | Ran the official native installer once and added only the documented user PATH line | Fresh login shell resolves `~/.local/bin/claude`; version 2.1.220; doctor PASS | Closed |
| M5SETUP-003 | Setup must not cross into source probing | High | Kept Claude settings absent and performed no prompt, task, status-line, usage, or UMA operation | Secret-route, settings-absence, repository-scope, and privacy checks PASS | Closed |

M5-SETUP-G1 verification:

- official native installer URL and one-attempt limit: PASS;
- installed launcher, arm64 architecture, SHA-256, and strict signature: PASS;
- final provider-managed subscription authentication: PASS;
- API-key, copied-token, setup-token, Bedrock, Vertex, and Foundry routes:
  inactive;
- fresh-shell resolution and version: PASS;
- `claude doctor`: PASS with no installation issues;
- user Claude settings file: absent; no status line created by setup;
- prompt, response, provider task, and quota payload access: none;
- production runtime, tests, package configuration, and UMA application:
  unchanged;
- task-owned backup and temporary setup artifacts: removed;
- independent staged-index and privacy reviews: PASS; no material findings.

M5-G2 remains locked. Exactly one next task is:

**M5-G1R2**

## M5-G1R2 issue ledger

| ID | First evidence | Severity | Root cause / classification | Repair / decision | Focused retest | Affected retest | Status |
|---|---|---:|---|---|---|---|---|
| M5G1R2-001 | Native 2.1.220 launcher, signature, authentication, and doctor checks pass | High | Prior installation and login setup conditions are resolved | Admit trust and authentication only; do not infer quota capability | 26/26 PASS | Trust and auth checks PASS | Closed |
| M5G1R2-002 | User settings and local managed-policy files were absent | High | No existing status line required preservation | Record absence, install one owner-only temporary probe, restore absence exactly | 26/26 PASS | Exact restore PASS | Closed |
| M5G1R2-003 | One normal Human CLI response completed but no probe evidence object appeared | Blocker | Effective official status-line callback was not observed | Return SETUP REQUIRED; classify all quota fields unsupported on current evidence | 26/26 PASS | No provider content accessed | Open setup condition |
| M5G1R2-004 | Used values and reset epochs require strict validation | High | Provider used semantics differ from UMA remaining semantics | Preserve finite range checks, independent windows, and one-time conversion | 26/26 PASS | Affected 48/48 PASS | Closed |
| M5G1R2-005 | Probe received no callback | High | No live object exists to sanitize or classify | Persist no value; retain only the event-absence result in durable records | 26/26 PASS | Raw/private data scan PASS | Closed |
| M5G1R2-006 | Temporary user settings changed original absence state | High | A status-line command was required for the bounded probe | Verify temporary hash, remove the file, prove final absence, delete marker/probe/evidence path | 26/26 PASS | Restoration PASS | Closed |
| M5G1R2-007 | Delivery must remain documentation/test-only | High | Runtime work would prematurely begin M5-G2 | Lock six exact paths and independently audit the staged index | 26/26 PASS | Affected 48/48 PASS | Closed on exact delivery |

Required final verification:

- focused M5-G1R2 admission tests;
- used-to-remaining conversion matrix;
- malformed, missing, nonfinite, and private-field rejection;
- owner-only backup and byte-exact/absence-state restore fixtures;
- affected provider-neutral percentage and Maximum Decrement tests;
- secret, private-data, raw-payload, and generated-artifact scans;
- production runtime and package-configuration unchanged audit;
- `git diff --check`;
- exact staged-index and independent reviews.

The durable result contains no live quota percentage, reset timestamp,
credential, account identity, prompt, response, session, transcript,
workspace path, or raw provider object.

Completed verification:

- focused M5-G1R2 suite: 26/26 PASS;
- affected provider-neutral and retirement suites: 48/48 PASS;
- used-to-remaining, Maximum Decrement, malformed-value, forbidden-field,
  settings, and restoration coverage: PASS;
- exact configuration restoration and temporary-artifact deletion: PASS;
- independent privacy and unstaged-scope audit: PASS, no material findings.

M5-G2 remains locked. Exactly one next task is:

**M5-SETUP-G1**

This is a new status-line activation setup revision under the required task
label. The earlier launcher-installation and subscription-authentication
setup remains closed.

## M5-SETUP-G1R issue ledger

| ID | First evidence | Severity | Root cause | Repair / decision | Focused retest | Affected retest | Status |
|---|---|---:|---|---|---|---|---|
| M5SETUPR-001 | Sandboxed auth classification reported logged out while the normal user context reported provider-managed login | Blocker | Build sandbox could not represent normal authentication visibility | Run authentication classification and the probe only in the normal user context with real home and login shell | Auth continuity PASS | No secret route active | Closed |
| M5SETUPR-002 | First visible CLI launch stopped at first-run onboarding | High | Theme, login-method, and trusted-neutral-directory onboarding had not completed | Complete only provider-owned subscription onboarding and trust the empty task-owned neutral directory | Startup callback PASS | Official CLI trust unchanged | Closed |
| M5SETUPR-003 | Initial command-line session produced no callback before onboarding | High | CLI exited before reaching the interactive session | Run one documented debug classification, observe no status-line error, then use the authorized fresh visible session | Callback activation PASS | Version presence PASS | Closed |
| M5SETUPR-004 | Startup callback omitted quota windows | Expected | Official rate-limit fields appear only after a Claude.ai subscriber receives a response | Obtain one Human-controlled normal response without DEV prompt or response access | Post-response callback PASS | Both windows and resets PASS | Closed |
| M5SETUPR-005 | Provider values use consumed percentages | High | UMA presents remaining percentages | Validate each finite zero-through-100 used value, subtract once with decimal-aware arithmetic, retain no live value | Conversion-validity PASS | Existing conversion matrix PASS | Closed |
| M5SETUPR-006 | Status payload can contain unrelated private fields | Blocker | Official schema is broader than UMA needs | Bound input, allowlist only window/reset/version classifications, and persist no raw payload | Private-field rejection PASS | Secret/private scan PASS | Closed |
| M5SETUPR-007 | Temporary configuration must not become persistent | High | A live callback requires an executable command reference | Use command-line-only owner-readable settings, terminate the task-owned process, and delete every task-owned artifact | Temporary cleanup PASS | Persistent `statusLine` absent | Closed |
| M5SETUPR-008 | Delivery must not begin M5-G2 | High | Admission proof is documentation/test work only | Lock six tracked paths and independently review the cached diff | Exact-scope audit PASS | Runtime unchanged audit PASS | Closed on exact delivery |
| M5SETUPR-009 | Official first-run onboarding created a one-key user preference file | Medium | A legitimate Human-selected theme must survive probe cleanup | Preserve the file byte-for-byte; classify the one-key theme-only content separately from task-owned artifacts | Theme-only and no-`statusLine` verification PASS | Authentication continuity PASS | Closed by Founder decision |

Required final verification:

- focused M5 setup/status-line activation tests;
- authentication-context continuity tests;
- temporary `--settings` contract tests;
- callback activation and post-response capability tests;
- used-to-remaining conversion tests;
- missing, malformed, nonfinite, oversized, and private-field rejection;
- cleanup and persistent-status-line absence tests;
- affected provider-neutral percentage and Maximum Decrement tests;
- secret, private-data, raw-payload, and generated-artifact scans;
- production runtime and package-configuration unchanged audit;
- `git diff --check`;
- exact staged-index and independent reviews.

Durable records contain no real percentage, reset timestamp, credential,
identity, prompt, response, session, transcript, workspace content, or raw
provider object.

The retained official onboarding settings file is classified:

**ACCEPTED PROVIDER-OWNED ONBOARDING PREFERENCE — NOT A PROBE ARTIFACT**

It is unchanged, contains exactly one non-sensitive `theme` preference, and
contains no `statusLine`, credential, session, token, identity, hook, API-key
route, enterprise-cloud route, provider route, or UMA probe configuration.
No other Claude file was modified or deleted.

## M5-G3 live acceptance addendum

The live acceptance record contains classifications only. It contains no real
quota value, reset timestamp, raw payload, credential, identity, prompt,
response, transcript, task, tool, workspace, or repository content.

| ID | First evidence | Severity | Acceptance impact | Repair / decision | Focused retest | Regression retest | Status |
|---|---|---:|---|---|---|---|---|
| M5G3-001 | Visible Disable Integration restored the exact Claude settings but left the last Claude card admitted | High | Relay-disabled and exact-restore state matrix failed | Publish an inactive connector snapshot on disconnect so the registry withdraws Claude immediately without affecting other providers | Disconnect/withdrawal and failure-to-fresh tests PASS | Full 409/409 provider and UI regression PASS | Closed |
| M5G3-002 | One Human-controlled response produced a current Claude card with both plan windows | Blocker gate | Live source admission was previously unproven | Accept only the sanitized provider event and record classifications, never values | Live callback and field classification PASS | Main-panel order and Assistant exclusion PASS | Closed |
| M5G3-003 | WorkBuddy current read briefly failed during shared Refresh | Medium | Cross-provider failure isolation and stable order required proof | Preserve Claude and Codex, use the existing bounded WorkBuddy recovery control, and verify the three-provider order after recovery | Failure isolation PASS | WorkBuddy recovery PASS | Closed |
| M5G3-004 | The preflight package helper only admitted the historical G2 final path | High | Commit-exact M5-G3 preflight/final paths could not be certified | Add exact phase-bound output paths and G3 provenance states while retaining the G2 contract | M5-G3 package-contract test PASS | G2 compatibility contract and preflight package audit PASS; final commit-exact audit remains the delivery gate | Closed |

## M5DBG-G1 issue ledger

This addendum contains no live quota value, reset timestamp, raw payload,
credential, account identity, prompt, response, session, transcript, task,
tool, workspace, or settings backup.

| ID | First evidence | Severity | Root cause | Repair / decision | Focused retest | Regression retest | Status |
|---|---|---:|---|---|---|---|---|
| M5DBG-001 | Source audit showed one shared Manual Refresh called Claude's configuration-aware probe and then its configuration refresh | Major | The provider-neutral scanner treated passive local event sources like active read sources | Use the completed passive-source probe as the sole health check while active providers retain one read | 30 scans produced exactly 30 Codex reads, 30 WorkBuddy reads, 30 Claude health checks, and zero Claude provider events | Physical 30-action matrix and 412-test full suite PASS | Closed |
| M5DBG-002 | The live task required an exact 50-event classification and duplicate-publication proof | High | Prior focused coverage did not lock the combined acceptance/rejection totals | Add bounded diagnostic publication count and an exact synthetic 50-event matrix | Exact 45 accepted / 3 connector rejected / 2 relay rejected matrix PASS | Physical bounded stress and 412-test full suite PASS | Closed |
| M5DBG-003 | M5DBG final output had no phase-exact package contract | High | Package helper ended at M5-G3 | Add M5DBG preflight/final paths and dedicated provenance state | Package contract and preflight audit PASS | Accepted final commit-exact package audit PASS | Closed — PASS |
| M5DBG-004 | Physical Light and macOS accessibility-state transitions were previously denied by the execution permission boundary | Gate | The required temporary system-wide transitions needed explicit Human authority and exact restoration | Run one setting at a time against the task-owned candidate; restore and verify after every case; stop VoiceOver when its Accessibility Tutorial appears | Light → Dark → Light, Reduce Transparency Off → On → Off, Increase Contrast Off → On → Off, and Reduce Motion Off → On → Off PASS with stable panel and Settings geometry, readable content, and no clipping or overlap; actual startup cache restored Cached and aged to Stale without provider activity | VoiceOver was immediately restored after the macOS tutorial appeared and then explicitly bypassed by the Founder; final Light / Off / Off / Off / Off state, theme-only Claude settings, no relay socket, and no task-owned process verified | Closed under Founder VoiceOver bypass |

## M5DBG-N1 natural startup addendum

This addendum records only synthetic fixture classifications. It contains no
live quota, reset value, provider payload, account identity, prompt, response,
session, transcript, task, tool, workspace, repository, credential, token, or
authentication data.

| ID | First evidence | Severity | Root cause | Repair / decision | Focused retest | Regression retest | Status |
|---|---|---:|---|---|---|---|---|
| M5DBGN1-001 | A valid Claude card disappeared on the next UMA launch until another normal Claude response occurred | Major | The relay source was correctly event-driven but no privacy-safe last-valid startup state existed | Persist one bounded, versioned Claude-only remaining-quota record and restore it without launching Claude or generating provider activity | Fresh-to-Cached, Cached-to-Stale, and next-event-to-Fresh fixtures PASS | M5-G2 connector/Settings 18/18, combined M5 95/95, and full 420/420 PASS | Repaired; automated gate PASS |
| M5DBGN1-002 | A whole-record expiry policy could hide one still-valid window | Major | Five-hour and seven-day reset lifecycles are independent | Validate and prune each window independently; delete the record only when neither window remains valid | Both single-window expiry directions, exact reset boundary, missing reset, malformed reset, and both-expired deletion PASS | Combined M5 95/95 and full 420/420 PASS | Repaired; automated gate PASS |
| M5DBGN1-003 | Restored remaining values could be mistaken for provider used percentages | Blocker | The original rate-window shape represented only live used percentage | Add an exclusive normalized remaining field and one normalization owner; cached load never subtracts a second time | Live conversion and cached no-second-conversion fixtures PASS | Restored-selection, no-fake-decrement, neutral-severity, and alert-suppression coverage PASS; full 420/420 PASS | Repaired; automated gate PASS |
| M5DBGN1-004 | General connector persistence was too broad for a Claude startup cache | Blocker | The generic store can retain provider-neutral snapshot fields that are outside the Claude allowlist | Keep generic restore disabled for Claude and add one strict sibling record with exact keys, 4 KiB limit, atomic replacement, owner-only permissions, backup exclusion, and fail-closed deletion | Strict key, schema, type, size, time, permissions, replacement, and deletion fixtures PASS | Package contract, explicit cache-record exclusion, privacy scans, and arm64 Release dependency audit PASS | Repaired; automated exclusion gate PASS |

M5DBG-N1 did not broaden the physical matrix boundary recorded by M5DBG-004.
The later explicit Human authorization permitted the bounded transitions, and
the Founder subsequently bypassed only the VoiceOver case after macOS opened
the Accessibility Tutorial. All completed transitions were restored to their
verified original values before delivery.

M5DBG-N1 automated verification:

- focused sanitized-snapshot suite: 8/8 PASS;
- M5-G2 connector and Settings regression suite: 18/18 PASS;
- combined M5 suites: 95/95 PASS across seven suites;
- full regression suite: 420/420 PASS across 47 suites;
- Debug, Release, and strict-concurrency warnings-as-errors Release: PASS;
- eleven-state synthetic renderer matrix: PASS for Cached, Stale, retained
  failure, independently surviving windows, Light, Dark, Reduce Transparency,
  Increase Contrast, Reduce Motion, and Simplified Chinese;
- script syntax, package contract, explicit cache-record exclusion, secret and
  private-field scans, arm64 executable checks, and Release dependency audit:
  PASS;
- final commit-exact package remains a post-physical, post-commit delivery gate.

## M5A-G1 issue ledger

This addendum records only deterministic shared-presentation fixtures. It
contains no live quota, provider payload, account identity, prompt, response,
session, transcript, task, tool, workspace, credential, token, authentication
material, settings backup, or sanitized production snapshot.

| ID | First evidence | Severity | Root cause | Repair / decision | Focused retest | Regression retest | Status |
|---|---|---:|---|---|---|---|---|
| M5A-001 | The accepted Claude connector still declared the historical Desktop Assistant exclusion capability | Blocking | M5DBG intentionally admitted Claude only to the main panel | Remove only the obsolete Assistant exclusion while retaining one connector, one shared snapshot, one normalization owner, and the stable provider order | Deterministic 0/1/2/3-provider visibility and ordering matrix PASS | Full Desktop Assistant, Codex, WorkBuddy, Claude and 431-test regression PASS | Closed |
| M5A-002 | The Assistant card collapsed shared freshness to a stale Boolean and omitted reset epoch, source identity, and observation age | Major | The predecessor Assistant contract predated Claude Cached and Waiting semantics | Extend only the immutable presentation value with explicit freshness, reset epoch, provider mark, source description, and deterministic observation age | Fresh/Cached/Stale/Waiting/Failed/Unavailable and English/Chinese semantic matrices PASS | Regular/Minimalist, geometry, accessibility and 431-test regression PASS | Closed |
| M5A-003 | Assistant preview and package contracts ended at the two-provider/M5DBG baseline | High | No Claude Assistant fixture or phase-exact M5A package existed | Add in-memory Claude Assistant fixtures and one exact `m5a-final` package phase without changing live settings or installing the Desktop app | Eight-state renderer and package-contract tests PASS | Commit-exact package privacy, signature, dependency and provenance audits remain the post-commit delivery gate | Automated gate PASS |
| M5A-004 | The first Cached renderer shortened the final state word at fixed Regular width | Major | The full reset sentence plus the longer Cached label exceeded the accepted one-line detail width | Keep the full reset sentence in Tooltip and VoiceOver, but use a deterministic compact reset token in the visible Claude detail row | Cached, Stale, Light, Dark, English, Chinese, Reduce Transparency, Increase Contrast and Minimalist renders PASS with no clipping | Accepted Desktop Assistant contract and focused M5A suites PASS | Closed |

Physical VoiceOver interaction remains a bounded M5ADBG-G1 confirmation item.
M5A-G1 performs deterministic accessibility semantics only and does not change
the system VoiceOver setting.

M5A-G1 pre-commit verification:

- focused M5A and accepted Desktop Assistant suites: 23/23 PASS;
- affected Desktop Assistant, Codex, WorkBuddy and Claude suites: 99/99 PASS;
- full regression suite: 431/431 PASS across 48 suites;
- Debug, Release and strict-concurrency warnings-as-errors Release: PASS;
- eight-state synthetic renderer matrix: PASS for Light, Dark, Regular,
  Minimalist, Cached, Stale, Reduce Transparency, Increase Contrast and
  Simplified Chinese, with stable order and no clipping;
- one immutable shared presentation, stable provider-ID routing, 100 Assistant
  cycles, and a 2,000-update burst below the 500 ms target: PASS;
- live Claude settings, provider tasks, relay ownership, socket ownership,
  installed Desktop application and provider cadence: unchanged;
- final staged-index, commit-exact package and clean-Git proofs remain delivery
  gates.

Current M5-G3 verification:

- M5-G3 focused suite: 6/6 PASS;
- combined M5 setup, relay, configuration, connector, Settings, and live
  acceptance suites: 84/84 PASS;
- full regression suite: 409/409 PASS across 45 suites;
- Debug, Release, strict-concurrency Release, and strict relay-helper builds:
  PASS;
- final exact Claude settings restoration: PASS;
- final commit-exact package, staged-index audit, and clean Git proof remain
  delivery gates.

Completed pre-staging verification:

- focused M5-SETUP-G1R suite: 30/30 PASS;
- affected shared percentage and Maximum Decrement suite: 16/16 PASS;
- full regression suite: 355 tests across 41 suites PASS;
- macOS 26.5 SDK compile: PASS;
- known task-owned Testing runtime links: used outside Git only;
- `git diff --check`: PASS;
- production runtime and package configuration: unchanged.

**Admission: GO. Exactly one next task: M5-G2.**

## M5-G2 issue ledger

M5-G2 uses only synthetic fixtures and sanitized classifications. No real
quota value, reset timestamp, raw payload, provider content, command,
credential, account identity, or settings backup is recorded.

| ID | First evidence | Severity | Acceptance impact | Repair | Focused retest | Regression retest | Final status |
|---|---|---:|---|---|---|---|---|
| M5G2-001 | A synthesized packet could bypass validating initializers and accept unknown shape | Blocker | A malformed or expanded schema could cross the socket boundary | Added strict root/window key validation and reconstructed every decoded window through its validating initializer | Strict malformed, private, unknown, range, reset, and packet-size cases PASS | Full suite 403/403 PASS | Closed |
| M5G2-002 | A second listener or a short callback burst could contend for the socket | Major | More than one listener or lost callbacks would violate lifecycle requirements | Probe live sockets before stale replacement, validate peer ownership, use one listener, and set a bounded 32-connection backlog | Active takeover, stale recovery, permissions, burst, and single-listener cases PASS | Full suite 403/403 PASS | Closed |
| M5G2-003 | Prior-command output capture was bounded by failing after reading the whole output | Major | Large valid status output could be suppressed or retained unnecessarily | Stream prior stdout directly to the original output while keeping only a bounded optional test capture; preserve stdin and exit behavior | Success, failure, complex quoting, large streaming output, cancellation, and bounded capture PASS | Full suite 403/403 PASS | Closed |
| M5G2-004 | Settings presentation did not observe connector changes after an action completed | Major | Waiting could remain visible after the first current event | Added one reactive connector snapshot observer with bounded actions | Waiting-to-fresh fixture PASS | Full suite 403/403 PASS | Closed |
| M5G2-005 | A failed passive admission could cancel the path required for later recovery | Blocker | Claude could not recover after one malformed event | Keep passive listeners alive while withdrawing only the current Claude admission | Real socket failure-to-fresh and registry withdraw/recover cases PASS | Full suite 403/403 PASS | Closed |
| M5G2-006 | Settings reads and mutation checks had filesystem race and link hazards | Blocker | Exact restore or unrelated settings preservation could not be certified | Added no-follow bounded reads, owner/type/link checks, before-mutation identity rechecks, exclusive backup creation, atomic replacement, and exact byte/mode restoration | Absent, theme-only, existing command/options, concurrent drift, link, repair, disable, and restore cases PASS | Full suite 403/403 PASS | Closed |
| M5G2-007 | Package scratch permissions and artifact scans were incomplete | Major | A package or scratch directory could retain a backup, socket, fixture, or private field | Added owner-only umask, cleanup trap, commit archive build, helper and app scans, manifest, signature, dependency, fixture, socket, and backup exclusions | Package contract source test PASS | Commit-exact audit pending final gate | Closed |
| M5G2-008 | Tool-level sandboxing blocked Unix-domain socket execution | Infrastructure | A sandbox failure could be mistaken for a product defect | Retained SwiftPM's isolated build sandbox settings and ran only the task-owned socket suite outside the outer tool sandbox | 48/48 focused tests PASS | Full suite 403/403 PASS | Closed |
| M5G2-009 | The first passive-start wiring entered `UsageStore` and violated its neutral source-ownership contract | Major | Provider lifecycle ownership would have leaked into the shared store | Moved passive startup to the composition root and kept `UsageStore` provider-neutral | Exact source-ownership regression PASS | Affected 141/141 PASS | Closed |
| M5G2-010 | Preflight review found Info.plist permission ordering and an overbroad legacy-source private-field scan in the package helper | Major | The final commit-exact package would fail before completing its audit | Apply permissions after plist creation; scan credential/retired routes across production while limiting Claude private-field checks to the relay source/helper | Script syntax and package contract PASS | Commit-exact audit pending final gate | Closed |
| M5G2-011 | Final privacy review found that status-line-only drift could be overwritten during repair or restore | Blocker | A concurrent Human status-line edit could be lost | Require the exact installed settings hash before repair or restore, while still supporting a changed packaged relay from an unchanged installed document | Status-line-only drift and changed-relay fixtures PASS | Full suite 403/403 PASS | Closed |
| M5G2-012 | Final lifecycle review found that shutdown unlinked the socket pathname without proving it still named the listener-owned inode | Blocker | A same-user replacement created during shutdown could be deleted | Record the bound socket device and inode, and unlink only when the current owner/type/identity still match | Replacement-path preservation and socket lifecycle fixtures PASS | Full suite 403/403 PASS | Closed |

Current focused result:

- M5-G2 focused suites: 48/48 PASS across three suites;
- affected Codex, WorkBuddy, registry, shared-presentation, and Desktop
  Assistant suites: 141/141 PASS across 13 suites;
- full regression suite: 403/403 PASS across 44 suites;
- Debug, Release, and strict-concurrency Release builds: PASS;
- decoder, relay, configuration, connector, registry, Settings, localization,
  privacy-source, and package-contract coverage: PASS;
- live Claude configuration mutation: none;
- installed Desktop application operation: none.

Final full-suite, build, package, staged-index, and commit results are recorded
in the shared sanitized evidence packet after those gates complete.

## M5-LIVE-R1 automatic integration repair

M5-LIVE-R1 records only safe configuration classifications, transport-health
counts, and sanitized quota states. It does not record provider content, raw
status-line payloads, prompts, responses, account identity, credentials,
authentication material, settings backups, or live quota values.

| ID | First evidence | Severity | Root cause | Repair | Focused retest | Regression retest | Status |
|---|---|---:|---|---|---|---|---|
| M5LIVE-R1-001 | Repair left Claude configured to execute the relay from the temporary candidate bundle | Blocking | The integration command used `Bundle.main` directly and did not install an independently durable helper | Install a hash-recorded owner-only relay in UMA Application Support, point Claude only to that durable path, and migrate only metadata-proven UMA ownership | Durable install, deleted-candidate survival, package update, mode repair, legacy migration, conflict refusal, and exact disable fixtures | Pending final affected and full-suite gates | Repaired — verification pending |
| M5LIVE-R1-002 | The former Repair action rewrote configuration without proving the relay could reach UMA | Blocking | No transport-only self-test existed | Add a nonce-only health packet and helper self-test that contains no quota fields and can never admit a provider snapshot | Health packet, one-listener, no-fake-quota, and settings-state fixtures | Pending final affected and full-suite gates | Repaired — verification pending |
| M5LIVE-R1-003 | Reconnect discarded or replaced the last valid snapshot before a new provider callback | Major | Reconnect followed the disconnect invalidation path and cache restoration was not guarded against an already-valid in-memory snapshot | Preserve the last valid sanitized snapshot across reconnect and transport failure; restore cache only when no valid snapshot exists | Fresh-to-reconnect Cached retention and stale-to-fresh recovery fixtures | Pending final affected and full-suite gates | Repaired — verification pending |
| M5LIVE-R1-004 | Settings could not distinguish enable, healthy relay, repair, managed-policy, and status-line conflict states | Major | The presentation collapsed safe configuration classifications into generic ready/failed states | Add bounded localized state summaries and rename the action to Repair Integration without exposing configuration contents | English/Chinese source contract and configuration-classification fixtures | Pending final affected and full-suite gates | Repaired — verification pending |
| M5LIVE-R1-005 | The package helper had no phase-exact M5-LIVE-R1 destination or provenance state | High | Packaging ended at M5A | Add one exact `m5-live-r1-final` package phase while preserving earlier package contracts | Script syntax and package-contract fixture | Pending final commit-exact package audit | Repaired — verification pending |

Final Human acceptance remains one normal Claude response after the automated
candidate, self-test, package, privacy, and lifecycle gates pass. The Human
gate observes only Fresh/Cached/Stale presentation and never provider content.

## M5-WEB-G1 account-web addendum

This addendum contains no live usage value, reset timestamp, credential,
cookie, token, session, account identity, raw HTML, DOM dump, provider
screenshot, chat, project, or billing data.

| ID | First evidence | Severity | Root cause | Decision / cleanup | Focused verification | Status |
|---|---|---:|---|---|---|---|
| M5WEB-001 | Google sign-in rejected embedded WebKit | Blocking | Embedded-user-agent incompatibility | Stop; do not retry, bypass, or ask for another factor | Prototype terminated | NO-GO |
| M5WEB-002 | Prototype had no App Sandbox entitlement | Blocking | Research bundle was unsandboxed | Delete prototype; do not admit | Entitlement and filesystem-source audit complete | Closed |
| M5WEB-003 | JavaScript inspected login-page DOM text before verified Usage route | Blocking | Route admission occurred inside the extractor | Reject privacy contract; prohibit login-page DOM inspection | No input-value query or sensitive persistence found | Closed |
| M5WEB-004 | Session-retention risk after failed login | Blocking | WebKit lifecycle required explicit proof | Disconnect & Clear; zero-record check; exact bundle-path audit; exact-root deletion | Website records, persistence paths, crash reports, process, and root absent | Closed |
| M5WEB-005 | System-browser capability lacked provider contract | Gate | No official Claude callback or Usage authorization for UMA | Document only; no implementation or session transfer | Official Apple and Anthropic documentation rechecked | NO-GO |

**NO-GO — SAFE ACCOUNT-WEB AUTHENTICATION NOT AVAILABLE**

## M5-BROWSER-G1 superseding issue ledger

The Founder permanently rejected the OAuth/Keychain broker after the
M5OAUTH rows above were recorded. Those rows are preserved as historical
evidence; any pending or repaired wording in them does not authorize runtime or
count as Browser Sync acceptance. The embedded account-web findings remain
closed NO-GO evidence and are not reused as an embedded login implementation.

This section contains no live quota value, reset timestamp, identity, URL,
credential, cookie, token, authorization header, raw HTML, DOM dump, chat,
project, billing, or screenshot data.

| ID | First evidence | Severity | Acceptance impact | Required repair / control | Focused verification | Status |
|---|---|---:|---|---|---|---|
| M5BROWSER-001 | Preserved dirty implementation still contained the rejected Claude broker and Keychain credential route | Blocking | Rejected secret access could remain executable or packaged | Remove broker products, Keychain reads, credential decoding, continuity state, bearer handling, private endpoint transport, consent text, and package requirements | Production/package forbidden-symbol and target audit | Closed |
| M5BROWSER-002 | Embedded account-web research failed authentication and inspected login-page DOM before route admission | Blocking | Reuse would violate the system-browser and route-first boundary | Keep the prototype deleted and historical; prohibit WKWebView login, session transfer, and login-page injection | Source and manifest negative assertions | Closed |
| M5BROWSER-003 | Browser extensions can easily request broad host or browser permissions | Blocking | Excess permission could expose unrelated browsing or account data | Use only Founder-approved `activeTab`, `scripting`, and `nativeMessaging`; no host permission, static content script, tab inventory/listeners, cookies, history, downloads, `webRequest`, or `<all_urls>` | Safari/Chromium manifest allowlist, source-trigger matrix, and registered extension inspection | Closed |
| M5BROWSER-004 | The current personal Usage route and page landmarks can drift | Blocking | The former `/settings/usage` contract redirected to the hash-routed Usage view, so static injection never ran | Exact full-route validation in both background and extractor; one Human toolbar click permits one fixed packaged extraction; route/landmark ambiguity fails closed | Route, fragment, redirect, drift, duplicate-label, billing, and login fixtures plus live checkpoint | Closed |
| M5BROWSER-005 | DOM or identity data could cross a permissive native-message schema | Blocking | Private page content could enter UMA, diagnostics, or persistence | Versioned bounded allowlist message; reject unknown/duplicate fields, raw DOM/HTML/URL, identity, billing, cookie, token, and malformed frames at every boundary | Parser/schema/privacy-negative matrix | Closed |
| M5BROWSER-006 | Native-host origin or executable mismatch could accept a foreign extension or host | Blocking | A foreign process could inject observations | Exact extension ID, immutable host path, owner, signature, and symlink checks; bounded local handoff; no network, command, daemon, or secret arguments | Wrong-ID/path/owner/signature/symlink, oversized-frame, and owner-only handoff tests | Closed |
| M5BROWSER-007 | Prior cache could admit Claude without a current browser observation | Blocking | Stale or wrong-account data could appear as current | Require current observation for first admission; restore only safely validated Cached/Stale state; never restore Fresh | First-admission, relaunch, auth-failure, route-failure, and stale-to-fresh tests | Closed |
| M5BROWSER-008 | Snapshot deletion could leave a backup copy restorable after Disconnect | Blocking | Disconnect would not fully clear UMA-owned Claude state | Scrub consent plus primary and backup Claude snapshot state and close the local bridge without touching browser data | Disconnect/relaunch/backup-recovery tests | Closed |
| M5BROWSER-009 | Automatic refresh could open repeated tabs, steal focus, or create churn | Major | Browser behavior would violate the bounded user-controlled source | Keep refresh manual/page-driven; no repeated tabs, focus theft, private requests, or background polling | Connect/Sync coalescing, browser-closed, duplicate-publication, process, and idle-write checks | Closed |
| M5BROWSER-010 | Historical OAuth consent could be mistaken for Browser Sync consent | Blocking | A materially different data boundary could activate without informed consent | Use separately versioned Browser Sync consent and never migrate the old OAuth approval | Preference migration and first-connect disclosure tests | Closed |
| M5BROWSER-011 | Shared surfaces could diverge or provider failure could spread | Major | Claude could show conflicting state or regress Codex/WorkBuddy | Keep one source owner, one in-flight gate, one shared snapshot, stable order, and provider isolation | Main/Assistant parity, registry, UsageStore, Maximum Decrement, Codex, and WorkBuddy regressions plus live surface inspection | Closed |
| M5BROWSER-012 | Static fixtures or package construction could be mistaken for live source proof | Gate | Browser Sync could be admitted without a real current account-level window | Require the Human-controlled default-browser checkpoint and report only match/unavailable/mismatch outcomes without exact live values | Live gate: both windows matched; reset honestly unavailable; final commit-exact audit remains required | Live gate passed |
| M5BROWSER-013 | Hash-routed provider pages cannot be constrained by a static WebExtension match without granting persistent access to the broader `/new` route | Blocking | A persistent host match would also cover chat-capable SPA content | Remove host permissions and static content scripts; inject only after a Human action click, temporary `activeTab` grant, and exact full-URL validation; no monitoring or automatic retry | Manifest, background-trigger, single-attempt content-script, and live toolbar-click tests | Closed |
| M5BROWSER-014 | Safari rejected the original local socket bridge from the extension sandbox | Blocking | A Unix-domain socket under Application Support was not reachable from the Safari extension process | Replace the socket with an atomic owner-only file handoff in one private Application Support directory | Live Safari callback, filesystem-mode, no-network, and cleanup tests | Closed |
| M5BROWSER-015 | Listener shutdown could remove coordination state before completing cleanup | Major | Unlocking and unlinking the listener marker before final cleanup created a lifecycle race | Hold the exclusive lock through pending-file cleanup and remove the marker only when its descriptor identity still matches | Focused lifecycle and identity tests | Closed |
| M5BROWSER-016 | A second listener could replace the active listener marker | Blocking | Marker replacement could disrupt the active owner and permit ambiguous delivery | Acquire a nonblocking exclusive lock before cleanup and reject a second listener without changing the active marker | Second-listener rejection plus first-listener delivery test | Closed |

## M5ADBG-G1 combined defect-closure ledger

This section contains classifications and sanitized counts only. It contains no
live percentage, reset timestamp, identity, URL, credential, cookie, token,
browser data, raw page content, screenshot, prompt, response, chat, project, or
billing data.

| ID | Found by | Severity | Evidence / acceptance impact | Repair | Focused retest | Regression retest | Final status |
|---|---|---:|---|---|---|---|---|
| M5ADBG-001 | Source audit | Blocking | Plain numeric text inside an allowlisted Usage card could be interpreted as a percentage, so a promotional multiplier or Credit count could make quota ambiguous | Visible quota text now requires `%`; only explicit percentage attributes may omit it; label and candidate scans are bounded | Exact extractor fixtures for promotional values and one explicit percentage: PASS | Full Browser Sync, bridge, and 465-test suite: PASS | Closed — PASS |
| M5ADBG-002 | Source audit | Blocking | A hash-routed SPA could leave the exact Usage route during extraction, and malformed or conflicting reset attributes could degrade silently | Revalidate route and login absence after bounded DOM reads; reject malformed or conflicting reset attributes without fabricating a reset | Route-change, malformed-reset, conflicting-reset, duplicate-card fixtures: PASS | Manifest, route, privacy, and bounded live Safari audits: PASS | Closed — PASS |
| M5ADBG-003 | Lifecycle audit | Major | Concurrent injections/native sends and replacement of an unread pending observation could create duplicate or lost handoff state | Add one-in-flight injection and native-send gates; publish with exclusive rename; remove a consumed observation only when descriptor and path identity match | Pending-observation exclusion and repeated-message checks: PASS | Native-host strict build, lifecycle matrix, five relaunches, and process/resource checks: PASS | Closed — PASS |
| M5ADBG-004 | Filesystem audit | Blocking | Intermediate symlinks, dangling cache links, path/descriptor replacement, or permissive cache state could cross the owner-only boundary | Reject symlink traversal, use owner/mode/type/identity checks, bounded descriptor reads, exclusive `0600` temporary writes, `fsync`, atomic rename, and identity-safe clear | Cache round-trip, wrong-mode, intermediate-link, dangling-link, and handoff-link tests: PASS | Privacy/package scans and idle cache metadata check: PASS | Closed — PASS |
| M5ADBG-005 | State-machine audit | Major | A valid snapshot could outlive a disabled/missing companion; listener-start failure could leave a phantom started flag; the retention timer did not schedule deterministic final expiry | Health-check every probe, withdraw unsafe health states, retain browser-closed data only same-session, make listener start retryable, and schedule exact Fresh→Stale→expired boundaries | Health matrix, five availability transitions, start recovery, and exact-boundary tests: PASS | Provider registry, UsageStore, Codex, WorkBuddy, full-suite, and five-relaunch regressions: PASS | Closed — PASS |
| M5ADBG-006 | Settings audit | Minor required for acceptance | Recovery could leave a stale English-only error, waiting state duplicated Open Usage, and explicit actions lacked visible progress | Centralize localized safe errors and action states, clear errors on recovery, remove duplicate waiting action, and expose Refreshing/other action progress | EN/zh-CN action/error and recovery tests: PASS | Settings, localization, deterministic accessibility, and UI source audit: PASS | Closed — PASS |
| M5ADBG-007 | Inventory audit | Gate | The reported 445 and accepted 435 counts compared unlike target scopes and milestones, creating an apparent ten-test deletion | Reconcile exact arithmetic and inspect every removed test name against replacement coverage | Source inventory parser and focused closure suite: PASS | Authoritative post-repair runner: 449 UI plus 16 bridge tests, 465 total PASS | Closed — reconciled with no coverage loss |
| M5ADBG-008 | Delivery audit | Gate | The accepted package helper lacked task-specific preflight/final phases | Add exact `m5adbg-preflight` and `m5adbg-final` output contracts while preserving commit-exact archive behavior and audits | Script argument/output rejection matrix and exact preflight phase: PASS | Preflight structure, nested signature, manifest, privacy, and provenance audits: PASS; final phase pending commit | Preflight PASS; final package pending |
| M5ADBG-009 | Goal acceptance | Gate | Current code and fixtures cannot replace a bounded same-time Safari validation and mandatory security restoration | Build exact preflight, perform one Human toolbar action without retaining values, then unregister and restore Safari unsigned mode Off | Exact preflight registered with `pluginkit`; Human-triggered callback produced a strictly sanitized current observation; Safari unsigned mode independently confirmed Off after relaunch | Fresh-to-Stale transition, main/Assistant parity, disconnect cleanup, extension unregister, and process cleanup: PASS | Closed — PASS |
| M5ADBG-010 | Affected-suite retest | Major | The first current toolbar observation could arrive after the connector started but before the registry's fire-and-forget stream task installed its continuation, leaving Claude hidden | Await connector stream establishment before the registry returns from listener setup, so the first current observation cannot fall into a subscription gap | Registry first-toolbar-read test: PASS | Browser suites and 465-test full suite: PASS | Closed — PASS |
| M5ADBG-011 | Affected-suite retest | Minor required for acceptance | A symlink at the cache-file leaf was rejected safely but reported the generic traversal error instead of the contract's precise nonregular-file error | Validate parent traversal separately and retain `lstat`/`O_NOFOLLOW` type checks for the leaf | Leaf, dangling, and intermediate symlink matrix: PASS | Browser suites, full suite, and package privacy audit: PASS | Closed — PASS |
| M5ADBG-012 | Founder physical Settings review | Major / live-gate blocking | The visible Continue control in the native SwiftUI consent alert did not respond to a physical pointer press in the transient status-panel Settings context; an Accessibility action invoked the same model operation successfully, isolating the defect to modal presentation and hit testing rather than the consent function | Replace the panel-hosted alert with an inline consent card in the same Settings hierarchy, with direct Cancel and Continue buttons, stable accessibility identifiers, the unchanged disclosure, and a direct `connectWithConsent()` action | Inline-control structure plus consent persistence/listener-start/Usage-open tests: 10/10 PASS | Rebuilt-candidate physical pointer press: PASS; 465/465 tests, Debug, Release, strict main, strict native-host, preflight package, manifest, signature, privacy, secret, and retired-route audits: PASS | Closed — PASS |
| M5ADBG-013 | Founder bounded live Safari acceptance | Blocking | The Human completed the first toolbar action while UMA's owner-only listener was healthy, but no sanitized observation or cache arrived and the native handler emitted no forwarding event | The M5ADBG hardening had limited label fallback to the first 40 structural elements, excluding the real Usage landmarks later in Claude's settings SPA; replace the prefix truncation with a bounded 4,096-element scan that retains only exact allowlisted leaf labels and stops after ambiguity | Structural-prefix extractor fixture plus affected Browser Sync suites: 23/23 PASS | Human retry delivered both account-level windows without retaining values; Fresh-to-Stale shared-surface parity, disconnect cleanup, 465-test regression matrix, and privacy checks: PASS | Closed — PASS |

### Test-inventory reconciliation

The apparent ten-test difference is a reporting-scope mismatch, not a deletion:

```text
previous intermediate report: 431 UI tests + 14 bridge tests = 445
accepted final UI target only: 435 UI tests                         = 435
accepted final complete inventory: 435 UI + 14 bridge tests        = 449
```

The final Browser Sync commit therefore had four more UI tests than the
431-test predecessor and fourteen tests in the new bridge target. Comparing
the intermediate all-target count with the final UI-only count omitted those
fourteen bridge tests while also including the four net-new UI tests, producing
the apparent difference of ten. A direct predecessor-to-final source audit
found 36 retired or consolidated names and 54 replacements/additions, for a net
increase of 18 and no active coverage loss.

Exact removed names, grouped by former file:

- `M5AG1ClaudeAssistantTests`: `rendererPackageAndQALedgerCarryM5AContracts`.
- `M5DBGN1ClaudeSnapshotTests`: `validEventsAtomicallyReplaceOneRemainingOnlyOwnerRecord`, `relaunchRestoresCachedWithoutProviderReadThenTransitionsFresh`, `recentCacheAgesToStaleWithoutPromptOrProviderRead`, `expiryPrunesEachWindowIndependentlyAndBothExpiredDelete`, `malformedOversizedUnknownAndFutureRecordsFailClosed`, `disableRepairAndOwnershipLossInvalidateTheSnapshot`, `malformedNewEventRetainsCacheAndRestoreDoesNotCreateDecrementOrAlert`, `copyRendererAndPackageContractsExposeCachedStateWithoutPrivateData`.
- `M5DBGThreeProviderAcceptanceTests`: `fiftyEventMatrixHasExactAcceptanceAndPublicationBoundaries`, `thirtyGlobalRefreshesReadCodexAndWorkBuddyOnceAndOnlyHealthCheckClaude`, `m5dbgPackagingAndDurableRecordsAreExactAndPrivacyBounded`.
- `M5G2ClaudeConnectorSettingsTests`: `descriptorLocksPrivacySourceAndSanitizedRestoreBoundary`, `configurationStatesMapToRequiredConnectorLifecycle`, `currentPacketAdmitsClaudeAndConvertsExactlyOnceInSharedModel`, `invalidPacketRetainsLastValidOnlyAsStale`, `packetAgesToStaleAndRelaunchRestoresWithoutPrompt`, `manualRefreshChecksConfigurationWithoutGeneratingProviderData`, `socketTransportDrivesFreshStateAndRecoversAfterInvalidPacket`, `passiveRegistryRetainsStaleAndRecoversWithoutAnotherListener`, `staleSnapshotSurvivesHealthRefreshUntilACurrentEventArrives`, `concurrentHealthRefreshesAreCoalesced`, `missingOptionalWindowIsNotInvented`, `providerOrderIsCodexClaudeWorkBuddyWithoutPlaceholders`, `agentSettingsListsClaudeBetweenCodexAndWorkBuddy`, `settingsModelReactsFromWaitingToFreshWithoutAnotherAction`, `settingsSourceHasBoundedActionsTransparencyLocalizationAndNoCredentialControls`, `desktopAssistantHasNoClaudeOwnedSourceAndRetainsGenericCapabilityFilter`, `packageContractIncludesHelperAndExcludesArtifacts`, `relayAndConnectorSourcesContainNoNetworkOrCredentialPath`.
- `M5G3ClaudeLiveAcceptanceTests`: `disableAfterLiveAdmissionWithdrawsClaudeImmediately`, `deterministicMatrixKeepsWindowsIndependentAndConvertsOnce`, `malformedFailureRecoversWithoutAnotherListener`, `providerOrderAndAssistantBoundaryRemainLocked`, `g3PackagingPhasesAreExactAndPrivacyBounded`, `liveAcceptanceRecordContainsClassificationsNotValues`.

The removed snapshot/packet/socket names belonged to the retired status-line
relay and socket transport or were consolidated into the accepted Browser Sync
contract. Current equivalents are located in
`ClaudeBrowserBridgeCoreTests`, `M5G2ClaudeConnectorSettingsTests`,
`M5G3ClaudeLiveAcceptanceTests`, `M5DBGN1ClaudeSnapshotTests`,
`M5DBGThreeProviderAcceptanceTests`, `M5AG1ClaudeAssistantTests`,
`SharedUsagePresentationPolicyTests`, and
`M5ADBGG1BrowserSyncClosureTests`. They cover exact route and permissions,
strict schema/privacy, owner-only handoff, cache admission and expiry,
Fresh/Cached/Stale, provider isolation/order, shared presentation, Maximum
Decrement, Settings/localization, and bounded lifecycle stress.

## M5-AUTO-G1 automatic Browser Sync issue ledger

This section contains only structural classifications and sanitized counts.
It contains no live percentage, reset timestamp, identity, URL, credential,
Cookie, token, browser content, screenshot, prompt, response, chat, project, or
billing data.

| ID | Found by | Severity | Evidence / acceptance impact | Repair | Focused retest | Regression retest | Final status |
|---|---|---:|---|---|---|---|---|
| M5AUTO-001 | Consent-boundary audit | Blocking | The predecessor's consent authorized only one Human toolbar action and could not silently authorize persistent site access or recurring reads | Add a new recurring-consent version; in-product Continue enables five-minute Auto Refresh while Safari launch remains Off | Migration and explicit-consent tests: PASS | Full regression 491/491 PASS | Automated PASS; live permission gate pending |
| M5AUTO-002 | Permission and route audit | Blocking | A hash route cannot be represented in a static host-permission rule, while `/new*` can include non-Usage SPA content | Limit persistent access to `https://claude.ai/new*` and independently verify scheme, host, path, and exact Usage hash before the first DOM query on every cycle | Manifest, wrong-route zero-query, and login-guard tests: PASS | Full regression 491/491 PASS | Automated PASS; live revocation gate pending |
| M5AUTO-003 | Tab-ownership audit | Blocking | Reusing or enumerating user tabs could expose unrelated URLs or close Human content | Create one inactive extension-owned tab per cycle; use only its returned ID; never enumerate, adopt, activate, or inspect unrelated tabs; close it after the bounded result | Source contract and collision tests: PASS | Full regression 491/491 PASS | Automated PASS; live one-tab/focus gate pending |
| M5AUTO-004 | Scheduler audit | Major | View-owned or overlapping timers could multiply reads, tabs, and Safari launches | Keep one connector-owned completion-relative scheduler, one in-flight gate, five-minute cadence, three-minute floor, manual coalescing, and no immediate retry | Scheduler, coalescing, unavailable-Safari, Disconnect, and 20-collision tests: PASS | Full regression 491/491 PASS | Automated PASS; live cadence pending |
| M5AUTO-005 | Browser availability audit | Major | Automatic refresh could foreground Safari or launch it without consent | Keep launch preference separate and Off by default; dispatch only once per permitted cycle; retain Cached/Stale or Waiting when launch is Off | Preference and bounded-dispatch tests: PASS | Full regression 491/491 PASS | Live focus and real five-minute cycle pending |
| M5AUTO-006 | Delivery audit | Gate | The accepted package helper did not have M5-AUTO exact preflight/final destinations or persistent-permission auditing | Add task-specific preflight/final phases and conditional Safari/Chromium manifest audits | Package-helper contract test: PASS | Working-tree preflight passed before the final runtime repair; rebuilt preflight and final package pending | Automated PASS; packages pending |
| M5AUTO-007 | Physical first-read validation | Blocking | Safari received the containing-app dispatch but its Manifest V3 worker could release the native port, leaving a later command without a reliable delivery path | Retain exactly one native port, reconnect it after worker disconnect, and send a content-free bounded wake message before the one real refresh command | Port-retention, wake, timeout, nonmultiplication, and lifecycle tests: PASS | Full regression 491/491 PASS | Repaired; real five-minute follow-up pending |
| M5AUTO-008 | Physical first-read validation | Blocking | The exact Usage route completed loading before Claude's SPA rendered its Usage landmarks, causing an honest but premature `usageUnavailable` result | Retry only the fixed `usageUnavailable` classification for at most 20 seconds at 500 ms intervals; exact-route and sign-in rejection remain immediate and precede every DOM query | SPA-readiness, wrong-route, login-guard, and bounded-source tests: PASS | Full regression 491/491 PASS | Repaired; live initial read PASS |
| M5AUTO-009 | Final runtime audit | Major | The Safari-launch preference allowed dispatch while Safari was absent but did not itself perform the promised launch | Launch only the exact Safari bundle through public `NSWorkspace` configuration with activation and new-instance creation disabled, then wait at most five seconds for the running-app registry | Launch preference, no-activation source contract, unavailable-Safari cadence, and focused suite: PASS | Full regression 491/491 PASS | Automated PASS; live closed-Safari focus gate pending |
| M5AUTO-010 | Final tab-ownership audit | Blocking | The extension cleared its ownership gate before awaiting removal of the completed tab, leaving a narrow path for two extension-owned tabs | Keep the read owned through exact tab removal and release the ownership gate only afterward | Owned-tab sequencing, ten-cycle closure, collision, and Disconnect tests: PASS | Full regression 491/491 PASS | Closed |
| M5AUTO-011 | Full regression | Major | A predecessor bridge test still prohibited every bounded readiness timer and expected the old single-attempt source shape | Update only the affected contract assertion to require the 20-second/500 ms `usageUnavailable` wait while still prohibiting observers, intervals, and message listeners | Bridge contract 18/18 PASS | Full regression 491/491 PASS | Closed |
| M5AUTO-012 | Physical recurring-read validation | Blocking | The initial read reached Fresh, but after Safari suspended its Manifest V3 worker, the fixed 250 ms wake delay raced native-port reconnection; scheduled and manual reads timed out without a new sanitized observation | Replace the blind delay with a content-free `bridgeReady` acknowledgement keyed to the existing request ID; dispatch the one real refresh command only after readiness, with a five-second fail-closed timeout and no provider-read retry | M5-AUTO focused 24/24 PASS; bridge 18/18 PASS | Full regression 491/491 PASS; Debug, Release, strict-concurrency Release, and strict native-host builds PASS | Automated repair verified; rebuilt five-minute live cadence pending |
| M5AUTO-013 | Rebuilt live launch validation | Blocking | A previously consented Browser Sync connector was not a passive-local connector, and its explicit start was initially queued behind passive-provider startup; a slow passive source could therefore delay the local listener while Auto Refresh was already enabled | Start the consent-owned Claude connector before awaiting any passive provider and before the application-launch admission scan; make the Auto Refresh preference boundary start the listener when needed before scheduling its immediate cycle | Focused launch-order, listener-start, and automatic-cycle tests: PASS | Full regression 499/499 PASS; Debug, Release, strict app, and strict native-host builds PASS | Closed; current read began immediately after relaunch |
| M5AUTO-014 | Rebuilt live listener retention | Blocking | The registry correctly kept the consent-owned Browser Companion listener during the launch scan, but a later fail-closed, non-admitted cycle was treated like a terminal hidden provider and stopped the connector, preventing scheduled recovery | Keep the provider hidden and update its admission record, but retain the consent-owned Browser Companion listener and scheduler while consent still permits reads; other non-passive sources retain the prior stop behavior | Focused hidden-failure-to-fresh listener-retention test: PASS | Full regression 499/499 PASS; strict builds PASS | Closed; two later scheduled reads completed |
| M5AUTO-015 | M5-AUTO-R1 Founder direction | Blocking | The earlier per-cycle create-and-close contract multiplied tabs and contradicted the accepted reusable inactive-tab lifecycle | Persist only a tab ID and random ownership token, prove the isolated content-script token before reuse or closure, reload one inactive owned tab, recreate only when the prior tab is absent, and fail closed on ownership uncertainty | Manifest, ownership storage, proof, reuse, relaunch, Disconnect, and uncertainty tests: PASS | Full regression 499/499 PASS; strict builds PASS | Closed; bounded reusable-tab lifecycle accepted |
| M5AUTO-016 | Rebuilt live command-delivery audit | Blocking | `SFSafariApplication.dispatchMessage` reached the extension runtime listener, but that listener handled only content results; automatic wake and refresh commands were therefore accepted by Safari without reaching the command handler | Route only content-free containing-app envelopes with no tab sender through the same strict command decoder used by the retained native port; tab senders cannot invoke control commands | Containing-app routing and command allowlist tests: PASS | Full regression 499/499 PASS; strict builds PASS | Closed; automatic command delivery completed three reads |
| M5AUTO-017 | Reusable-tab disconnect audit | Blocking | Disconnect and stop closed an owned tab only while a provider request ID was still active, so a successfully completed reusable tab could remain | Always send one fresh bounded close command when idle, prove the persisted token before removing the exact tab, and clear ownership metadata | Idle Disconnect and relaunch close tests: PASS | Full regression 499/499 PASS; strict builds PASS | Closed; connector, extension registration, cache, and consent state removed |
| M5AUTO-018 | Live five-minute cadence | Blocking | The initial automatic read succeeded, but Safari suspended the Manifest V3 worker before the next cycle; the single content-free wake was accepted while its runtime listener was still starting, and a one-second settle window proved too short for the work-bearing command to reach the re-established native port | Keep exactly one wake and one refresh command, allow one bounded five-second worker-settle window, treat readiness as advisory, and retain the existing no-retry contract | Focused automatic-refresh and bridge contract suites: PASS | Full regression: pending | Superseded by M5AUTO-020 after the real five-minute cycle proved that an accepted containing-app message does not reliably wake Safari's suspended Manifest V3 worker |
| M5AUTO-019 | Recreated inactive-tab navigation | Blocking | After the worker-settle repair, a newly created inactive tab could transiently report the pre-navigation document as complete; injection bound to that replaced document and produced no result before the bounded timeout. Re-signing the repaired nested extension at the same version also left Safari's registration cache on the obsolete code identity | Add one content-free one-second navigation settle before exact-route polling and injection; treat `usageUnavailable` as a transient retained-value state that schedules only the normal five-minute cadence, while route, permission, authentication, and ownership uncertainty still suspend; increment the Browser Companion's internal version from 1.2.0/4 to 1.2.1/5 so the repaired nested bundle registers deterministically | M5-AUTO focused 31/31 PASS | Full regression 499/499 PASS; all four required builds PASS | Closed; repaired navigation reached a current read and normal cadence |
| M5AUTO-020 | Real five-minute recurring-read validation | Blocking | The rebuilt Manifest V3 companion completed the first automatic read, but after Safari suspended its service worker the next completion-relative cycle logged both accepted containing-app messages and no `bridgeReady`, `refreshStarted`, observation, or completion event. A longer settle cannot repair a worker that Safari did not wake | Use Safari's officially supported Manifest V2 persistent background page only for the Safari companion, preserving the single app-owned five-minute scheduler and one in-flight read. Keep Chromium on Manifest V3. Use the same exact `/new*` host grant and a bounded MV2 `tabs.executeScript` fallback; retain no broad tab permission, polling timer, retry, or page-content cache | M5-AUTO 31/31, bridge 18/18, and closure 10/10 PASS | Full regression 499/499 PASS; all four required builds PASS | Closed; first current read plus two later completion-relative five-minute reads PASS |
| M5AUTO-021 | Persistent-background preflight | Blocking | Safari registered and enabled the Manifest V2 companion but its persistent background page emitted no `bridgeReady`. The former Manifest V3 loader called worker-only `importScripts`, which is unavailable in a persistent background page, so the control listener never installed | Load the fixed packaged extractor, Safari configuration, and shared background core as three ordered manifest scripts; keep the loader configuration-only and version the nested extension to 1.2.3/7 | Ordered-script, no-worker-global, permission, and packaging tests PASS | Full regression 499/499 PASS; all four required builds PASS | Closed; live first and recurring reads PASS |

### M5-AUTO-R1 final acceptance summary

The sanitized live event sequence proved one current automatic read after
launch and two later reads at the completion-relative five-minute cadence. No
toolbar action, catch-up burst, provider-read retry, foreground activation
request, or exact quota/reset value was used as evidence. The same package
retained one scheduler and one in-flight read, and kept background Safari
launch separately disabled.

Final automated evidence is 31/31 focused automatic-refresh tests, 18/18
bridge tests, 10/10 Browser Sync closure tests, and 499/499 tests across the
complete package. Debug, Release, strict-concurrency Release, and strict native
host builds pass. The task-owned extension was disabled and unregistered,
Safari was restarted, UMA-owned Claude cache/consent/handoff state was removed,
and the protected Desktop application remained byte-identical.
