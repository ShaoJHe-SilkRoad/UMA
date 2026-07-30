# UMA M5 Claude QA Issue Ledger

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
| M5DBG-003 | M5DBG final output had no phase-exact package contract | High | Package helper ended at M5-G3 | Add M5DBG preflight/final paths and dedicated provenance state | Package contract and preflight audit PASS | Final commit-exact package audit remains the delivery gate | Repaired; final package pending |
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
