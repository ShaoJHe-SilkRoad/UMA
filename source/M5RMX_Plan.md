# Usage Monitor Altoget — M5RMX Plan

**Program:** M5RMX-FINAL — current UMA major-version completion and UMA 0.13.0 delivery
**Version:** 3.0
**Date:** 2026-08-29
**Product:** UMA — Usage Monitor Altoget
**Execution owner:** Codex DEV
**Execution model family:** GPT-5.6 Sol
**Execution standard:** Goal Mode 2.0 / Dev Default 2.1
**Authority profile:** `LOCAL_FULL_THROTTLE`
**Apple Developer Team ID:** `C6TUZVJ6SJ`
**Current Claude status:** Supported in the accepted runtime
**Claude Safari Extension:** Core M5RMX deliverable
**Target application:** `UMA_0.13.0.app`
**Target Founder GitHub repository:** `https://github.com/ShaoJHe-SilkRoad/UMA` — verify live remote before push
**Cursor/Kimi/new-provider work:** Out of scope
**Status:** Claude root repair accepted; current-major 0.13.0 release integration in progress
**Canonical workspace:** `/Volumes/HE/DEV/UMA/Worktrees/UMA-M5RMX-Claude`

---

## Current master closeout override — 2026-08-29

The authoritative release version is `0.13.0`; the last accepted rollback line
is `0.11`. Historical `0.12` targets below are retained only as stage evidence
and do not authorize a `0.12` package or delivery. The current release must use
the split architecture: a Safari-free production UMA application, an immutable
production Safari Host, and the production Claude Companion. Test bundle IDs,
Test provisioning, and Apple Development signatures are forbidden from the
distributed release.

The Founder remote is `https://github.com/ShaoJHe-SilkRoad/UMA`. The `upstream`
remote is read-only for this closeout and must never receive a push. A final
PASS requires an exact source freeze, Developer ID signing, notarization,
stapling, Gatekeeper acceptance, rollback-preserving Desktop delivery, Founder
remote readback, and a clean worktree/index. Earlier closeout records document
accepted Claude Test-channel evidence; they are not evidence that the final
0.13.0 production package already exists.

## Current final-closeout authority — 2026-08-29

The accepted runtime is now the split Test architecture: a mutable Safari-free
UMA app talks over the bounded App Group IPC contract to the separately signed,
immutable Safari Host and its frozen Companion. The Host/Companion generation
is locked during this closeout.

One authorized live Accuracy Sync completed through the real provider route.
The result was validated, committed atomically, read back before publication,
and followed by proven temporary-tab and ownership-receipt cleanup. The exact
resetless anchors remain exact for a bounded five-minute TTL; absent reset
timestamps remain absent and cannot enter calibration. Safari quit and mutable
UMA relaunch both preserved the committed exact anchor without re-setup.

Mutable-app classification/installer truth, deterministic regression,
signing-trust stability, and independent product review passed. Provider-read
budget used: `1/2`; the unused second read is not a sampling or retry allowance.
The exact Git delivery referenced in this historical closeout applies only to
the accepted Claude root-repair commit. It does not mean the final 0.13.0
production release has been staged, committed, packaged, notarized, delivered,
or pushed. Those actions remain governed by the current master closeout above.

## Current Founder lifecycle override — Owned Provider Tab V2

The accepted live 2026-08-28 sequence revoked the prior claim that the frozen
Companion had no known extension-side blocker:

```text
refreshStarted
→ receipt save
→ bootstrap ownership
→ bootstrap self-navigation
→ Safari removal semantics
→ receipt retirement
→ tabUnavailable
```

The immutable Safari Host, App Group IPC, Test/production identity isolation,
native handshake, mutable app shell, Local Smart independence and consent
separation remain accepted. The failed component is only the bootstrap-to-
provider ownership handoff.

The current executable design is **Owned Provider Tab V2**:

```text
durable request intent
→ direct provider-tab creation
→ top-frame provider content-script discovery
→ request/generation/nonce plus trusted sender.tab.id proof
→ durable provider ownership
→ exact-route readiness
→ one bounded extraction
→ proven-tab cleanup
```

No security invariant may depend on an internal extension tab retaining its ID
across navigation to `https://claude.ai`. The active package must not contain
or invoke the retired `owned-tab-bootstrap.html → location.replace(...)`
handoff. `tabs.create()` output, a URL marker, an `onUpdated` event, or an
`onReplaced` event is never ownership by itself. No general tab enumeration is
permitted, and an unproven tab is never closed.

One new signed Companion generation is permitted only after offline reducer,
privacy, adversarial, package and independent-examiner gates pass. That later
Human enablement is a development-defect recovery, not normal product setup.
No provider read, staging, commit, push or notarization occurs before that
freeze gate.

## Current Founder forensic override — one final frozen Companion

`M5RMX-CLAUDE-FORENSIC-CLOSE-G1` is the current authority over every
conflicting current-stage statement below. The installed immutable Safari Host
build `202608281805` / generation
`e55245ee-7baf-4791-aadc-f13b52209986` is **not final**. Its pending Companion
enablement is suspended. No current live Accuracy Sync PASS is accepted.

The current architecture is:

```text
Mutable UMA Test App
→ bounded App Group IPC: group.com.silkrd.uma.test.bridge
→ immutable UMA Safari Host Test App
→ minimal Safari Companion
→ exact-route one-shot Accuracy Sync
```

Only the immutable Host may dispatch to Safari, receive native extension
callbacks, own request serialization/deadlines, and publish the atomic App
Group terminal result. Mutable UMA owns Local Smart, product state, consent,
presentation and explicit request initiation. The Companion owns only
Safari-privileged site permission, inactive bootstrap/tab lifecycle, exact
route/DOM sanitization, one canonical native Port and proved-tab cleanup.

Until the forensic timeline, authoritative Safari/API audit, owned-tab and
native-IPC audits, consent/site state matrix, synthetic/adversarial pipeline,
privacy review, package/signing review and independent examiner all pass, do
not enable/install/register/restart Safari, change site permission, perform
provider work, mint a claimed-final package, stage or commit. The next Human
Safari action may be requested only after one consolidated final signed frozen
Host/Companion has been verified offline.

Expected product contract after final acceptance:

```text
First setup: one Companion enable + one exact claude.ai Allow
Normal UMA update: zero Safari enablement + zero site-permission action
Normal UMA relaunch: zero Safari setup
```

Repeated enablement is a development failure except for a deliberate signed
Host/Companion security migration. Final live Accuracy Sync, cleanup, Safari
quit persistence, UMA relaunch, 10/10 mutable-app updates, site-permission
persistence, final suite, staging and commit remain future gates. Do not treat
offline test counts as live acceptance.

## Current Founder architecture override — Claude Local Smart Mode

The accepted `M5RMX-CLAUDE-SMART-CLOSE-G1` Local Smart source decision remains
the data-source authority inside the current forensic Goal. It supersedes the
plan's persistent-Safari source assumption without overriding the newer live
freeze, immutable-Host lifecycle, or final-candidate gates above. The current production
direction is:

```text
official Claude Code status-line exact quota
→ immediately sanitized owner-only state
→ independently calibrated local estimate when exact truth is not current
→ one-shot Safari Accuracy Sync only when the Human requests it
→ shared Main Panel and Desktop Assistant presentation
```

Normative priority is `OFFICIAL EXACT > CALIBRATED ESTIMATE`. Every estimate
must be visibly labeled. Persistent Safari scheduling, a permanent owned Usage
tab, and Browser Sync as the mandatory always-on source are retired from the
default product architecture. The bounded Safari extractor, sanitizer,
protocol, exact-route checks, signed extension packaging, and diagnostics are
retained only for explicit one-shot Accuracy Sync.

The local estimator has no fixed plan denominator. It requires at least two
compatible exact anchors and invalidates on reset, schema, model-family, plan,
account, or monotonicity discontinuity. Local prompt-bearing records may be
parsed only long enough to project allowlisted token/model/time metadata; raw
content is never retained. This section remains current source authority over
conflicting historical source statements below, subordinate to the forensic
live freeze and Host lifecycle gate above.

## Current conflict fence

Every lower section that requires recurring Browser Sync, a five-minute Safari scheduler, automatic Safari launch, or persistent owned-tab operation is historical and non-executable. Current Claude truth is one provider with three bounded surfaces: official Claude Code status-line exact data, explicit one-shot Safari Accuracy exact data, and Claude Desktop `plan-usage-history.json` estimate-only data. Claude Desktop has no admitted per-response activity signal. Compatibility symbols with `automatic` names are permitted only when runtime, tests, and governance prove they are inert outside a Human-requested one-shot.

## Historical plan archive boundary — Sections 0 through 15

Every imperative statement in Sections 0 through 15 is retained only as stage
evidence and is non-executable where it describes Browser Sync as primary,
recurring/five-minute Safari work, automatic Safari launch, or persistent tab
ownership. It cannot authorize runtime behavior, tests, packaging, or Human
actions. Only the current override/conflict fence above and the explicitly
currentized Section 16 continuation may govern new work.

## 0. Founder directive and corrected interpretation

M5RMX accepts the complete currently accepted Claude Code implementation and continues development from that baseline. It does not restart Claude source admission from zero and does not restore the retired status-line route merely because it existed historically.

The earlier interpretation that Claude Safari Extension support would remain entirely outside M5RMX is superseded.

M5RMX now owns the complete Claude product line required for `UMA_0.12.app`, including:

1. full development-stage retrospective;
2. acceptance and preservation of current Claude Code results;
3. adoption of the updated UMA credential/privacy boundary;
4. Claude Safari Extension source, manifest, permission, bridge, lifecycle, onboarding, migration, signing integration, and production acceptance;
5. completion of the Claude Main Panel, Settings, Desktop Assistant, local-activity, failure, repair, and disconnect experiences;
6. full functional, privacy, lifecycle, resource, package, and physical debugging;
7. bounded Claude-specific aesthetic and usability repair;
8. final Developer ID signing, notarization, stapling, and Gatekeeper verification of the exact final `UMA_0.12.app` bytes;
9. Desktop delivery and rollback preservation;
10. synchronization to the Founder GitHub repository;
11. current-source closeout and task completion.

The Apple infrastructure work already performed is accepted as a separate evidence stream, not as the final product package. M5RMX must consume its proven assets and pipeline without repeating completed readiness work unnecessarily.

Current Apple infrastructure evidence indicates:

```text
Apple Team C6TUZVJ6SJ                     READY
Developer ID Application certificate      READY
Matching private key                       READY
Developer ID signing smoke                 PASS
Hardened Runtime                           PASS
Secure timestamp                           PASS
notarytool                                 READY
UMA-notary Keychain profile                READY
First real non-Claude smoke submission     SUBMITTED
Submission ID                              bced6fed-8c8b-469e-924b-9b8a98395b6d
Current reported Apple state               In Progress
Final smoke staple/Gatekeeper              NOT YET COMPLETE
General UMA packaging-pipeline upgrade     NOT YET COMPLETE
Final UMA_0.12 notarization                 NOT STARTED
```

These values are expected evidence and must be rechecked when M5RMX consumes the final Apple handoff.

A smoke notarization ticket cannot be reused for `UMA_0.12.app`. The final app must be signed and notarized after all source, extension, entitlement, metadata, and nested-code bytes are frozen.

---

## 1. Authority and source basis

Use this order:

```text
1. Current Founder instruction
2. Current live repository evidence
3. Latest accepted DEV report and independent audit
4. Current accepted M5RMX predecessor source
5. Final Apple infrastructure / signing handoff when delivered
6. This M5RMX Plan
7. M5RMX Goal file
8. Current M5RMX Scope Lock
9. Accepted Claude Browser Sync / M5-AUTO / M5 closeout records
10. Scroll 3.0
11. UMA Logic 1.5
12. Goal Mode 2.0
13. Dev Default 2.1
14. Accepted M6/M7/M8 closeout and source records
15. Historical M5 Plan, Goal, status-line, and package records
```

Current live evidence outranks fixed hashes in this plan.

Historical M5 documents remain useful for architecture, semantics, privacy, testing, and restore rules. Their retired status-line acquisition path is not current authority.

### 1.1 Expected latest local source

At plan creation, the latest reported clean local source is:

```text
Workspace:
/Users/juliushe/Developer/UMA-M8-Kimi

Branch:
codex/uma-m8-kimi

HEAD:
01b190260da857f55fa5fa9b14da9715cafbc221

Tree:
49f2af499c86b9b8757da0e9406a0d9e5c24495b

Full deterministic suite:
683/683 PASS
```

This is an expected predecessor, not a reset target. Use a newer accepted clean successor when current evidence proves one exists.

### 1.2 Expected accepted runtime evidence

The accepted production runtime remains the M6 combined closeout unless current evidence proves a later accepted runtime change:

```text
Runtime commit:
e72bd92c476e05152b95ccb9ba95c22be78efef1

Runtime tree:
c1358c5b4176383021e87605afc45ca3e347ab89

Bundle ID:
com.silkrd.uma

Accepted package:
$HOME/Developer/UMA-Packages/
uma-m6adbg-final-e72bd92c476e05152b95ccb9ba95c22be78efef1/UMA.app
```

Protected rollback app:

```text
/Users/juliushe/Desktop/UMA_0.11.app
```

Reported historical executable SHA-256:

```text
88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

### 1.3 Accepted Claude results

M5RMX begins with the following accepted Claude truth:

```text
Claude quota source                              Browser Sync
Official provider surface                        Claude Usage page
Authentication owner                             Claude / Safari
UMA credential access                            None
Accepted account windows                         5-hour and weekly/7-day
Refresh                                           completion-relative 5 minutes
Scheduler ownership                               one Claude coordinator
In-flight extraction                              maximum one
Browser tab ownership                             extension-owned inactive Usage tab
Repeated toolbar interaction                      not required after setup
Route gate                                        before semantic extraction
Native handoff                                    sanitized, bounded, versioned
Freshness                                         Fresh / Cached / Stale / unavailable
Main Panel / Assistant                            shared presentation parity
Local activity/cost                               separate this-Mac estimate channel
Retired status-line quota route                   remains retired
```

Current live ancestry and files must verify these claims. Do not blindly cherry-pick old commits into a newer accepted lineage.

---

## 2. Current-stage retrospective and accepted-result map

M5RMX-B0 must review the complete current development stage before implementation.

### 2.1 Product state

Expected current provider state:

```text
1. Codex                 SUPPORTED
2. Claude Code           SUPPORTED
3. WorkBuddy             SUPPORTED
4. Google Antigravity    SUPPORTED
Cursor                   UNSUPPORTED / HIDDEN
Kimi                     UNSUPPORTED / HIDDEN
```

M5RMX does not add provider five.

### 2.2 Required retrospective output

Create an accepted Claude claim-to-code map:

```text
accepted claim
→ current source owner
→ current deterministic tests
→ current live evidence
→ packaged artifact/file
→ latest modifying commit
→ current status
→ known risk
```

Map at minimum:

- Browser Sync scheduler;
- extension-owned tab behavior;
- extension manifest and exact-site permissions;
- route/layout validation;
- semantic extractor;
- sanitized packet schema;
- extension-to-native handoff;
- native host/bridge validation;
- Claude connector and cache;
- UsageStore / Maximum Decrement integration;
- local activity/cost reader;
- Main Panel;
- Settings and repair actions;
- Desktop Assistant;
- package/signing scripts;
- current tests and fixtures;
- current source and closeout records.

### 2.3 File ownership classification

Every current Claude-related path must be classified as:

```text
Claude Safari Extension source
Claude containing-app / extension manifest / entitlement
Claude native host / bridge / protocol
Claude Browser Sync coordinator / scheduler / cache
Claude connector / normalized model
Claude local activity/cost
Claude Settings / localization / UI
shared provider-neutral runtime/UI
package/signing/notarization tooling
Claude tests / fixtures
current governance / historical evidence
generated/private evidence
protected unrelated provider
```

### 2.4 Acceptance rule

Accepted results are not reopened because another implementation appears cleaner.

Change an accepted component only when:

- current evidence proves a defect;
- current Apple distribution requirements demand a source-level correction;
- the updated privacy boundary enables a materially better official source;
- current Claude account behavior changed and existing semantics are no longer honest;
- package, onboarding, or supportability is incomplete.

---

## 3. Updated UMA privacy boundary for Claude Code

### 3.1 Governing principle

The correct question is not whether Claude Code or Safari possesses a credential.

The correct question is:

```text
Does a credential cross into UMA-owned business logic, durable state, evidence, or UI?
```

Allowed:

```text
Human authenticates inside Claude Code or Safari
→ Claude/Safari stores and uses its own credential/session
→ provider-owned or provider-controlled code obtains usage internally
→ the browser/provider boundary sanitizes the result
→ UMA receives usage-only data
```

Forbidden:

```text
UMA asks for Claude password/API key/token
UMA reads Claude Keychain items
UMA copies OAuth/access/refresh tokens
UMA exports Safari cookies or browser profiles
UMA reads an auth database
UMA receives a credential-bearing response
UMA persists a token, cookie, login URL, code, or credential path
UMA uses a private account endpoint by replaying provider credentials
```

### 3.2 Safari Extension boundary

The Claude Safari Extension may operate within Safari's provider-controlled authenticated session, subject to:

- exact allowed Claude origin/route family;
- least website permission required by the accepted architecture;
- no `All Websites` permission;
- no cookie API extraction;
- no token/session-storage extraction;
- no Keychain interaction;
- no broad DOM/HTML export;
- semantic extraction inside the extension;
- sanitization before any native handoff;
- versioned packet validation;
- unknown layout fails closed.

### 3.3 Existing Browser Sync remains valid

The current path remains accepted:

```text
Safari owns login/session
→ official Claude Usage page renders quota
→ signed UMA Claude Safari Extension observes the admitted route
→ browser layer emits sanitized quota only
→ native bridge validates provenance/schema
→ Claude connector publishes current normalized windows
```

Browser Sync remains the production account source unless a superior official source passes full live parity, rollback, and privacy acceptance.

### 3.4 Ideal-source investigation

M5RMX-G1 may investigate current official Claude capabilities in this order:

```text
1. official Claude local service / IPC
2. official Claude Code hook/event/status interface
3. official read-only CLI or provider-owned local metadata
4. accepted Safari Browser Sync
```

A candidate replaces Browser Sync only when it proves:

- official/documented authority;
- account-capacity truth, not only local activity;
- explicit remaining/used semantics;
- stable window identities and reset scopes;
- provider-owned authentication;
- zero Claude prompt/task creation by monitoring;
- no intentional provider spend;
- automatic refresh feasibility;
- credential opacity;
- bounded sanitized output;
- live parity with the official Claude Usage surface;
- safe fallback to Browser Sync.

The retired status-line route is not restored without current proof.

### 3.5 Two-channel maximum

Claude retains no more than two channels.

#### Channel A — account capacity

May contain only admitted provider-rendered account quantities:

```text
5-hour remaining/reset
weekly/7-day remaining/reset
additional provider-rendered current windows when separately admitted
continuation / usage-credit state when explicitly admitted
source / observation time / freshness
```

#### Channel B — this-Mac Claude activity

May contain privacy-safe local aggregates:

```text
input tokens
output tokens
cache-read/cache-creation tokens when available
model classification
API-equivalent estimated cost
observation scope/time
```

Channel B never substitutes for Channel A and is never presented as official billing.

---

## 4. Claude Safari Extension — complete M5RMX product scope

Claude Safari Extension support is a core M5RMX deliverable.

### 4.1 Required production architecture

```text
Signed UMA containing app
└── signed Claude Safari Web Extension appex
    ├── exact Claude site permission
    ├── extension-owned Usage tab lifecycle
    ├── exact route/layout gate
    ├── semantic usage extraction
    ├── privacy sanitization
    └── versioned usage-only handoff

Signed native host / bridge / protocol
→ validates extension identity, packet schema, size, freshness, sequence, and source
→ rejects private or unknown payloads

Claude Browser Sync coordinator
→ one scheduler
→ one in-flight extraction
→ current-read admission
→ cache/freshness/account-epoch handling
→ shared UsageStore presentation
```

### 4.2 Extension source responsibilities

The extension owns:

- current Claude Usage route recognition;
- exact-site permission checks;
- extension-owned tab creation/reuse/closure;
- page-ready and authentication state classification;
- bounded semantic field extraction;
- layout/source version classification;
- sanitized packet construction;
- no raw page-state handoff;
- no provider task generation;
- no account mutation.

The extension does not own:

- quota selection;
- Maximum Decrement;
- Main Panel/Assistant rendering;
- local activity aggregation;
- native cache policy;
- cross-provider orchestration.

### 4.3 Website permissions

Production extension requirements:

- minimum admitted Claude origins only;
- minimum current route family only;
- no permanent `All Websites` permission;
- no hidden broad host permission;
- explicit setup state when permission is missing;
- permission revoke/regrant support;
- permission changes fail closed;
- no repeat toolbar click for healthy automatic reads after setup.

### 4.4 Extension-owned tab contract

The extension may create and reuse one inactive Claude Usage tab only when the accepted architecture requires it.

It must never:

- adopt a user-owned tab;
- navigate a user-owned tab;
- close a user-owned tab;
- close unrelated Safari windows/tabs;
- create duplicate tabs on scheduler collision;
- keep multiplying tabs after Safari relaunch;
- expose private page content in logs/evidence.

Ownership must survive normal read cycles and fail safely across Safari restart, app restart, and stale tab IDs.

### 4.5 Semantic extraction contract

The extension extracts only bounded provider-rendered semantics such as:

```text
window ID / bounded label
used or remaining semantic
percentage or same-scope numerator/denominator
reset/cycle metadata
source/layout version
observation time
account-mode class when required
continuation state when admitted
```

It must not pass:

- raw DOM;
- raw HTML;
- whole page text;
- arbitrary accessibility tree;
- email/name/avatar/account ID;
- payment/invoice/history;
- conversations/projects;
- token/cookie/session data.

### 4.6 Native handoff contract

Require:

- explicit packet schema version;
- provider ID = Claude;
- extension/containing-app identity validation;
- bounded packet size;
- sequence/replay protection;
- timestamp/freshness validation;
- source/layout version allowlist;
- strict number/range validation;
- missing != zero;
- unknown fields/layouts fail closed;
- atomic or message-framed delivery;
- no raw stderr/page output in durable diagnostics.

### 4.7 Production signing and distribution

The final extension must be distributed inside the final signed `UMA_0.12.app`.

Required final chain:

```text
Claude Safari appex signed first
→ native host/helper signed
→ remaining nested executable code signed
→ containing UMA app signed
→ Hardened Runtime
→ secure timestamp
→ strict deep verification
→ notarization of exact final archive
→ staple
→ stapler validate
→ Gatekeeper accepted
```

Use Apple Team:

```text
C6TUZVJ6SJ
```

M5RMX must verify live bundle identifiers, entitlements, extension point identifiers, containing-app relationships, and native-host registration from current source. Do not invent identities from this summary.

### 4.8 No unsigned production dependency

Final users must not need:

- Safari `Allow unsigned extensions`;
- Xcode;
- manual `pluginkit` development registration;
- `/private/tmp` extension containers;
- task-owned browser profiles;
- developer-only permission bypasses.

Temporary unsigned development mode may be used only under an exact Human gate in a dedicated Goal, and must be restored Off before Goal closeout.

### 4.9 New-user onboarding

Required normal flow:

```text
Open UMA_0.12.app
→ open Claude Settings
→ extension availability check
→ open Safari Extension Settings when required
→ enable signed UMA Claude extension
→ grant current Claude website access only
→ open official Claude Usage page
→ sign in normally through Claude/Safari when required
→ first sanitized current observation
→ automatic five-minute sync begins
```

### 4.10 Existing-user migration

Safely migrate from development or earlier builds:

- obsolete unsigned registrations;
- old bundle identifiers;
- previous native-host manifests;
- stale Browser Sync cache;
- older extension version/state;
- previous app container identity.

Migration must preserve:

- Claude Safari login;
- user-owned Safari tabs/history;
- unrelated Safari extensions/settings;
- `UMA_0.11.app` rollback;
- provider-owned Claude Code configuration and sessions.

No broad Safari data deletion is authorized.

---

## 5. Claude account and normalized data model

### 5.1 Window model

Support provider-rendered windows rather than one hard-coded plan shape.

Potential admitted windows:

```text
5-hour
weekly / 7-day all-model
weekly model-specific window
other current provider-rendered windows
```

Each admitted window requires:

```text
stable semantic identity
explicit used/remaining semantic
remaining percentage
independent reset/cycle
source/layout version
observation time
freshness
account-mode applicability
```

Do not infer a window from marketing limits.

### 5.2 Remaining normalization

Explicit remaining percentage:

```text
retain remaining
```

Explicit used percentage:

```text
remaining = 100 - used
```

Used + total:

```text
remaining = total - used
remainingPercent = remaining / total × 100
```

Only when values share the same pool, cycle, account mode, and observation.

No silent clamping.

### 5.3 Continuation / usage-credit state

When current Claude product behavior exposes a paid-continuation state, normalize only admitted fields:

```text
unavailable
notOffered
disabled
enabledBalanceAvailable
enabledBalanceUnavailable
usageBasedPlan
unknown
```

Optional native detail may include:

```text
currency
native balance
month-to-date spend
monthly cap state
observation time/freshness
```

Native money remains native money. Never convert it to a fabricated percentage.

Critical rule:

```text
0% included remaining
≠ automatically “Claude cannot continue”
```

### 5.4 Account-mode handling

Classify only what source correctness requires:

```text
Free
Pro
Max
Team
Enterprise seat-based
Enterprise usage-based
unknown / unsupported
```

Do not retain identity or organization details.

Unknown source-affecting account modes fail closed.

### 5.5 Maximum Decrement

Only Fresh account-capacity percentage observations participate.

Do not use:

- Cached/Stale samples;
- local activity/cost;
- native money;
- missing windows;
- unknown account modes;
- identity-changing account epochs.

---

## 6. Complete Claude Code product block

### 6.1 Main Panel — collapsed

Require:

- formal name `Claude Code`;
- selected remaining percentage;
- selected window label only when the compact contract permits it;
- source/freshness state;
- no local-cost value presented as quota;
- no explanatory sentence appended to the compact percentage;
- no false zero for missing data.

### 6.2 Main Panel — expanded

Show admitted data only:

- 5-hour remaining/reset;
- weekly/7-day remaining/reset;
- any separately admitted current window;
- continuation/usage-credit state and native details when admitted;
- source and source/layout version;
- last current observation;
- Fresh/Cached/Stale/error;
- local activity token aggregates;
- local API-equivalent estimated cost;
- explicit `This Mac only / not official billing` scope;
- Sync, Open Claude, Repair, and Disable/Disconnect actions.

Account capacity, continuation money, and local activity must remain visually separate.

### 6.3 Claude Settings

Required EN/zh-CN states:

```text
Ready
Refreshing
Fresh
Cached
Stale
Safari unavailable
Extension missing
Extension disabled
Website access required
Sign in required
Usage page unavailable
Unsupported route/layout
Native handoff unavailable
Signed package mismatch
Repair required
Disconnected
```

Required actions:

```text
Check Claude
Open Claude Usage
Open Safari Extension Settings
Grant Website Access
Sync Now
Repair Companion
Disable / Disconnect
```

Settings must disclose:

```text
Source
Authentication owner
Credentials visible to UMA: None
Data retained
Refresh cadence
Extension/tab behavior
Disconnect behavior
Local activity scope
Signed extension version/health
```

### 6.4 Desktop Assistant

Assistant consumes the shared immutable presentation.

It owns no:

- browser/session communication;
- scheduler;
- extension tab;
- source decoder;
- cache;
- local activity reader;
- quota selection;
- continuation calculation.

Regular and Minimalist output must remain identical in meaning to Main Panel truth.

### 6.5 Disconnect and repair

Disconnect must:

- cancel Claude-owned UMA scheduling;
- cancel pending extraction;
- clear UMA-owned Claude snapshots/presentation;
- close only a proven extension-owned tab when appropriate;
- preserve Claude/Safari login;
- preserve user-owned tabs/history;
- preserve Claude Code configuration/sessions;
- never alter the Claude account.

Repair must be bounded and explicit. It must not clear Safari data or reinstall unrelated extensions.

### 6.6 Failure isolation

One Claude failure must not:

- blank/reorder another provider;
- alter another provider's refresh cadence;
- change another provider's selected value;
- trigger an all-provider retry storm;
- cause Main Panel/Assistant divergence.

---

## 7. Runtime and lifecycle contract

### 7.1 Refresh

Preserve the accepted completion-relative five-minute cadence unless current live evidence justifies a safer value.

Require:

- one scheduler;
- one extraction in flight;
- manual/scheduled coalescing;
- successful manual refresh resets next normal interval;
- no overlap;
- no catch-up burst;
- no retry storm;
- one normal wake refresh;
- source-specific failure isolation.

### 7.2 Freshness and cache

- current successful observation admits presentation;
- Cached/Stale do not create decrement samples or alerts;
- older data cannot overwrite newer Fresh;
- account/auth uncertainty invalidates prior snapshots;
- cache corruption fails closed;
- no periodic write when unchanged.

### 7.3 Safari lifecycle

Test and support:

- Safari absent;
- Safari not running;
- Safari launched;
- extension disabled/enabled;
- permission denied/granted/revoked;
- login expired/recovered;
- extension-owned tab missing/stale/duplicated;
- Safari quit/relaunch;
- app quit/relaunch;
- sleep/wake;
- shutdown during extraction.

### 7.4 Native host lifecycle

Require:

- one expected host process maximum when architecture requires it;
- exact identity/path;
- no residual task-owned process after shutdown;
- bounded resources;
- signed identity parity;
- no broad argv/environment capture;
- fail-closed version/provenance mismatch.

---

## 8. Full Claude debugging program

M5RMX-DBG-G1 is milestone-level adversarial debugging, not a test rerun.

### 8.1 Source/layout matrix

Test:

- valid 5h + weekly;
- one window missing;
- reset missing;
- additional window;
- continuation absent/disabled/enabled/unreadable;
- unsupported/future layout;
- wrong route;
- SPA navigation/hash change;
- page loading/partial/error;
- duplicate/ambiguous labels;
- localization variation;
- account-mode change.

### 8.2 Permission/auth matrix

- extension missing;
- extension disabled;
- current-site permission missing;
- permission revoked during read;
- login required;
- session expires;
- provider page unavailable;
- repair succeeds/fails;
- no repeated login loop.

### 8.3 Scheduler/concurrency matrix

- manual/scheduled collision;
- slow extraction;
- timeout/cancellation;
- sleep/wake;
- clock movement;
- app restart;
- Safari restart;
- extension restart;
- Disconnect during read;
- no duplicate timer/process/tab.

### 8.4 Tab ownership matrix

- user opens own Claude tabs;
- extension creates owned tab;
- owned tab closed by user;
- stale tab ID;
- Safari restores old tabs;
- multiple windows;
- no user-tab adoption/navigation/closure;
- no duplicate hidden tabs.

### 8.5 Handoff/security matrix

- valid packet;
- duplicate/replay;
- out-of-order;
- future schema;
- wrong provider/source;
- oversized packet;
- forged provenance;
- partial write/message;
- symlink/path attack where relevant;
- concurrent delivery;
- private-field injection;
- signed identity mismatch.

### 8.6 Cache/account epoch matrix

- cold launch;
- first current read;
- corrupted cache;
- stale cache;
- account/auth switch uncertainty;
- new Fresh protection;
- no stale decrement/alert;
- missing != zero.

### 8.7 UI/Assistant matrix

- all provider subsets 0–4;
- stable order;
- Fresh/Cached/Stale/Error/Repair;
- Light/Dark;
- EN/zh-CN;
- Regular/Minimalist;
- local activity present/absent;
- continuation state variations;
- Main/Assistant parity;
- Settings lifecycle.

### 8.8 Physical/resource soak

Measure safely:

```text
CPU
RSS
threads
file descriptors
extension/native-host child count
scheduler count
in-flight extraction count
owned-tab count
periodic writes
shutdown residue
```

No broad process argv/environment capture.

### 8.9 QA Issue Ledger

Every confirmed defect requires:

```text
Issue ID
Found by
Severity
Evidence
Acceptance impact
Repair owner/action
Focused retest
Regression retest
Final status
```

Fix all blocking, major, and acceptance-required minor defects before PASS.

---

## 9. Stage-specific aesthetic and usability repair

M5RMX-UX-G1 begins only after functional/debug stability.

### 9.1 Visual target

Preserve:

- one-contour medium-transparency glass;
- Light/Dark adaptation;
- Reduce Transparency fallback;
- Increase Contrast support;
- Reduce Motion support;
- package-safe system-serif Latin roles;
- native CJK fallback;
- tabular numeric values;
- provider order;
- Regular/Minimalist rules.

### 9.2 Claude-specific scope

Repair only proven issues in:

- card rhythm/alignment;
- reset/freshness hierarchy;
- capacity versus local-activity separation;
- continuation state clarity;
- status icon clarity;
- expansion density;
- Settings spacing/action order;
- extension setup/repair guidance;
- EN/zh-CN fit;
- Light/Dark contrast;
- keyboard focus/accessibility labels;
- Assistant parity;
- clipping/overlap/duplicate material/nested shells.

### 9.3 Usability target

A user must be able to answer:

```text
Is Claude connected?
Is the signed Safari extension ready?
How much plan usage remains?
Which window is selected?
When does it reset?
Is the value Fresh or Stale?
Can paid continuation still allow work?
Is local activity an estimate or official quota?
What exact action fixes the current issue?
What does Disconnect preserve?
```

### 9.4 Hard rules

- compact percentage means remaining only;
- no extra note beside compact percentage;
- missing does not render zero;
- Unlimited does not render 100%;
- local money/token detail does not replace quota percentage;
- no combined global percentage;
- no provider reordering by value/state;
- no broad redesign of protected providers.

### 9.5 Visual evidence

Use deterministic renders plus bounded physical inspection:

```text
Light / Dark
English / zh-CN
Regular / Minimalist
Fresh / Cached / Stale / Error / Repair
5h only / weekly only / both / additional window
continuation states
local activity present / absent
extension missing / disabled / permission required / ready
0–4 providers
```

---

## 10. Apple infrastructure handoff and release boundary

### 10.1 Accepted current infrastructure evidence

M5RMX may rely on the reported readiness of:

- Team ID `C6TUZVJ6SJ`;
- Developer ID Application certificate/private key;
- Hardened Runtime signing;
- secure timestamp;
- `notarytool`;
- `UMA-notary` Keychain profile.

It must not expose or export Apple credentials/private keys.

### 10.2 Pending smoke submission

Expected current smoke submission:

```text
bced6fed-8c8b-469e-924b-9b8a98395b6d
```

At handoff, classify:

```text
Accepted + staple + Gatekeeper PASS
Invalid / rejected with log
Still In Progress
Unknown / evidence incomplete
```

Do not resubmit merely because status is slow.

### 10.3 Handoff acceptance

M5RMX-H1 verifies:

- exact Apple result;
- staple/validate/Gatekeeper evidence;
- cleanup of smoke artifacts;
- current signing identities;
- current package-pipeline changes, if any;
- exact source diff/commit/tree;
- no credentials in source/evidence;
- child-first signing design;
- notary profile parameterization;
- rollback and failure behavior.

### 10.4 Historical Apple `NO TOUCH CLAUDE` scope

The historical APPLE-G0/G1 restriction applied to those Apple infrastructure Goals.

It does not prohibit M5RMX from editing and signing Claude components, because Claude Safari Extension support is now an explicit M5RMX deliverable.

M5RMX must still avoid mutating historical smoke artifacts or Apple credentials outside the exact release goals.

### 10.5 Final-byte rule

The final `UMA_0.12.app` must be notarized after:

- Claude extension source is final;
- entitlements/manifests are final;
- native host is final;
- main app is final;
- version/build metadata is final;
- nested signing is complete;
- package inventory is frozen.

No earlier ticket can be relabeled as the final release ticket.

---

## 11. UMA 0.12 packaging contract

### 11.1 Final source freeze

Before release candidate packaging:

- all M5RMX functional/debug/UX Goals accepted;
- Apple handoff accepted;
- clean worktree/index;
- exact final commit/tree;
- no untracked production dependency;
- no unsigned extension mode required;
- no development-only registration/profile/container.

### 11.2 Target

```text
Application filename:
UMA_0.12.app

Bundle ID:
com.silkrd.uma

Version:
0.12

Architecture:
arm64

Package root:
$HOME/Developer/UMA-Packages/uma-m5rmx-final-<commit>/UMA_0.12.app
```

Build number must be unique, deterministic from the accepted delivery process, and recorded.

### 11.3 Requirements

- exact source revision/provenance;
- child-first nested signing;
- signed Claude Safari extension;
- signed native host/helper;
- signed main app;
- correct entitlements/relationships;
- Hardened Runtime;
- secure timestamp;
- strict deep signature PASS;
- notarization Accepted;
- staple PASS;
- stapler validate PASS;
- Gatekeeper accepted;
- no debug entitlement;
- no provider credential/session/profile;
- no tests/fixtures/source records/logs/databases/sockets;
- no raw provider evidence;
- exact-path launch and clean shutdown PASS.

### 11.4 Final live acceptance

Using the exact packaged app:

- Safari unsigned extensions Off;
- signed extension visible/enabled through normal Safari UI;
- exact-site permission;
- normal provider-controlled login;
- first current Claude observation;
- real automatic refresh interval;
- no repeated toolbar click;
- one owned tab maximum;
- Main/Assistant parity;
- local-activity separation;
- permission revoke/regrant;
- Safari/app relaunch recovery;
- zero monitoring-created Claude prompt/task/spend;
- no exact private values retained in evidence.

---

## 12. Desktop delivery and migration

### 12.1 Final app delivery

Target:

```text
/Users/juliushe/Desktop/UMA_0.12.app
```

Rules:

- preserve `/Users/juliushe/Desktop/UMA_0.11.app` as rollback;
- do not overwrite or delete it;
- copy only the exact accepted package;
- verify copied app hash;
- exact-path launch/smoke/termination;
- no unrelated Desktop mutation.

### 12.2 Bundle identity migration

Reported old Desktop identity:

```text
com.kevinchen.CodexUsageMonitor
```

Target identity:

```text
com.silkrd.uma
```

Treat them as distinct applications.

Verify:

- settings/cache migration or intentional reset;
- extension permission behavior;
- native-host registration target;
- coexistence;
- rollback;
- no cross-container corruption;
- no duplicate scheduler/extension process.

### 12.3 Desktop development folder

M5RMX-B0 inventories any separate Desktop development folder.

If present, M5RMX-DELIVER-G1 may update it only after:

- exact path/type/Git identity classification;
- unrelated WIP preservation;
- exact source synchronization method;
- rollback for destructive replacement.

Do not replace a development repository with app-package contents.

---

## 13. GitHub synchronization

### 13.1 Target remote

```text
https://github.com/ShaoJHe-SilkRoad/CodexUsageMonitor
```

Before push:

- verify repository ownership;
- inspect `git remote -v`;
- inspect branch/upstream;
- inspect remote main and divergence;
- verify exact final source commit;
- scan for secrets/private/generated artifacts;
- verify package provenance references only, not secrets/binaries unless explicitly authorized.

### 13.2 Push policy

Never:

- force-push;
- rewrite remote history;
- push to unrelated upstream;
- silently change remote URL;
- push Apple credentials/private keys;
- push provider/browser data;
- push task-owned profiles/containers/evidence.

Required result:

```text
accepted local M5RMX source
→ Founder repository
→ reviewed integration into Founder main
→ remote main contains final accepted source commit
```

Public Release, tag, and binary upload are separate actions unless explicitly authorized in M5RMX-SYNC-G1.

---

## 14. Scope Lock

### 14.1 Claude editable zone

Verify exact paths live. Expected classes:

```text
BrowserExtension/**
Claude Safari extension manifest/assets/source
Claude appex / containing-app metadata / entitlements
Sources/ClaudeBrowserBridgeProtocol/**
Sources/ClaudeBrowserNativeHost/**
Sources/ClaudeBrowserNativeHostCore/**
Claude Browser Sync coordinator/cache/connector
Claude local activity reader
Claude Settings/localization/views
Claude-specific tests/fixtures
M5/M5RMX QA/current records
M5RMX package/signing/delivery tooling
```

### 14.2 Shared additive-only zone

Potential shared paths:

```text
Package.swift
AgentUsageConnector.swift
AgentConnectorRegistry.swift
AgentConnectorSnapshotStore.swift
AgentUsageRuntime.swift
UsageStore.swift
UsageSnapshot.swift
SharedUsagePresentation.swift
UsagePanelView.swift
DesktopAssistantView.swift
Settings/provider registry surfaces
```

Shared edits must be minimal and behavior-neutral for protected providers.

### 14.3 Protected provider mechanisms

Do not change the source/authentication/cadence/semantic model of:

- Codex;
- WorkBuddy;
- Google Antigravity.

They are regression controls.

### 14.4 Out of scope

- Cursor;
- Kimi;
- TRAE;
- Qoder;
- new provider cards;
- fifth-provider density work;
- unrelated storage cleanup;
- provider account changes/purchases;
- broad app redesign;
- App Store submission unless separately authorized.

---

## 15. Mandatory subagent operating standard

The Founder requires subagents for every M5RMX task.

M5RMX does not use standalone Quick Patch Mode. Narrow repairs occur inside an active Standard/Full/Release Goal and retain subagent review.

Every Goal must begin using role-separated subagents from Stage 1.

Minimum roster for every Goal:

```text
implementer
qa_runner
examiner
```

Add only actual domain roles:

```text
docs_operator
Browser / Protocol Auditor
Privacy Steward
Packaging / Signing Auditor
Repo Hygiene Guard
Performance Auditor
Product UX / Accessibility QA
Translation Steward
Source Integrity Auditor
send_safety_auditor
```

Rules:

- every role has a distinct evidence contract;
- all roles share one current evidence packet;
- no multiple full-repo rescans without reason;
- no duplicate live Claude observations;
- subagents participate early, not only at final review;
- DEV resolves disagreements and documents the decision;
- if the platform cannot spawn a requested role, DEV must explicitly perform a separated equivalent pass and report that limitation; omission is not silent;
- final responsibility remains with DEV.

---

## 16. Program sequence

```text
M5RMX-B0
→ M5RMX-G1
→ M5RMX-SAFARI-G1
→ M5RMX-G2
→ M5RMX-DBG-G1
→ M5RMX-UX-G1
→ M5RMX-H1
→ M5RMX-RC-G1
→ M5RMX-DELIVER-G1
→ M5RMX-SYNC-G1
→ M5RMX-CLOSE-G1
```

No Goal starts automatically.

Every Goal ends under Completion Lock.

M5RMX-H1 may be executed earlier when the final Apple handoff arrives, but it must pass before M5RMX-RC-G1.

### 16.1 M5RMX-B0 — retrospective, branch, source installation, baseline

**Model:** GPT-5.6 Sol
**Effort:** High
**Mode:** Full Goal
**Subagents:** `docs_operator`, `qa_runner`, `examiner`, `Repo Hygiene Guard`

Outcomes:

- verify latest accepted source;
- create M5RMX branch/worktree;
- install Plan/Goal/Scope Lock;
- complete retrospective and claim-to-code map;
- inventory Claude extension/native host/signing state;
- inventory Desktop dev/delivery paths and remotes;
- run current baseline;
- commit docs/tests only;
- stop.

### 16.2 M5RMX-G1 — privacy boundary and source architecture

**Model:** GPT-5.6 Sol
**Effort:** Extra High
**Mode:** Full Goal — privacy/source architecture
**Subagents:** `implementer`, `Source/Protocol Examiner`, `Privacy Steward`, `qa_runner`

Outcomes:

- formalize provider-internal credential use versus UMA credential exclusion;
- audit Browser Sync and handoff;
- investigate official ideal-source deltas;
- preserve Browser Sync unless a replacement passes parity;
- admit current account windows/continuation semantics;
- update contracts/tests;
- no production UI redesign;
- commit and stop.

### 16.3 M5RMX-SAFARI-G1 — production Claude Safari Extension support

**Model:** GPT-5.6 Sol
**Effort:** Extra High
**Mode:** Full Goal — browser/native/package architecture
**Subagents:** `implementer`, `Browser/Protocol Auditor`, `Privacy Steward`, `Packaging Auditor`, `qa_runner`

Outcomes:

- complete extension manifest/permissions/route/extractor;
- complete owned-tab lifecycle;
- complete sanitized handoff and native validation;
- complete setup/repair/migration diagnostics;
- prepare correct bundle IDs/entitlements/signing order;
- prove unsigned-mode-free production design;
- full tests/builds and preflight package;
- commit and stop.

Final notarization occurs in RC after final bytes freeze.

### 16.4 M5RMX-G2 — complete Claude product block

Current G2 authority is Local Smart completion, not restoration of browser-first behavior. It must preserve exact-local > one-shot-Safari-exact > Desktop/local-estimate > stale > missing, report Claude Desktop activity as unavailable unless a new admitted official event exists, and keep all `automatic*` compatibility surfaces inert outside an explicit Accuracy request.


**Model:** GPT-5.6 Sol
**Effort:** Extra High
**Mode:** Full Goal — implementation
**Subagents:** `implementer`, `qa_runner`, `examiner`, `Translation Steward`, `Product UX/Accessibility QA`

Outcomes:

- implement admitted account/continuation model;
- complete Main Panel;
- complete Settings/actions/source transparency;
- complete Desktop Assistant parity;
- complete local activity scope;
- complete disconnect/repair/failure isolation;
- full tests/builds/preflight package;
- commit and stop.

### 16.5 M5RMX-DBG-G1 — adversarial Claude closeout

**Model:** GPT-5.6 Sol
**Effort:** Extra High
**Mode:** Full Goal — debug/lifecycle/privacy/performance
**Subagents:** `implementer`, `qa_runner`, `Browser/Protocol Auditor`, `Privacy Steward`, `Performance Auditor`, `examiner`

Outcomes:

- execute Section 8 matrices;
- create old-fail/new-pass tests;
- repair all blocking/major issues;
- physical lifecycle/resource soak;
- protected-provider regression audit;
- debug-closeout package/commit;
- stop.

### 16.6 M5RMX-UX-G1 — bounded Claude aesthetic/usability repair

**Model:** GPT-5.6 Sol
**Effort:** High
**Mode:** Full Goal — UI/UX
**Subagents:** `implementer`, `Product UX/Accessibility QA`, `Translation Steward`, `qa_runner`, `examiner`

Outcomes:

- deterministic/physical visual inspection;
- Claude-specific fixes only;
- Light/Dark, EN/zh-CN, accessibility, Regular/Minimalist;
- no view-owned source behavior;
- commit/package and stop.

### 16.7 M5RMX-H1 — Apple infrastructure and pipeline handoff

**Model:** GPT-5.6 Sol
**Effort:** Extra High
**Mode:** Full Goal / Release-evidence intake
**Subagents:** `Source Integrity Auditor`, `Packaging/Signing Auditor`, `Privacy Steward`, `qa_runner`, `Repo Hygiene Guard`

Outcomes:

- verify final smoke notarization result;
- verify staple/Gatekeeper/cleanup;
- verify package-pipeline changes;
- integrate accepted source-level pipeline work;
- reject unsupported claims;
- establish final RC signing owner;
- regressions/commit and stop.

### 16.8 M5RMX-RC-G1 — final UMA 0.12 release candidate

**Model:** GPT-5.6 Sol
**Effort:** Extra High
**Mode:** Release Mode
**Subagents:** `implementer`, `Packaging/Signing Auditor`, `Privacy Steward`, `qa_runner`, `Repo Hygiene Guard`, `examiner`

Outcomes:

- freeze final source;
- build exact `UMA_0.12.app`;
- child-first Developer ID signing;
- notarization submission/terminal result;
- staple/validate/Gatekeeper;
- package/privacy/provenance audit;
- signed live Claude acceptance;
- commit-exact final package;
- stop.

### 16.9 M5RMX-DELIVER-G1 — Desktop delivery

**Model:** GPT-5.6 Sol
**Effort:** High
**Mode:** Live Action
**Subagents:** `implementer`, `Packaging Auditor`, `qa_runner`, `Repo Hygiene Guard`

Outcomes:

- preserve `UMA_0.11.app`;
- copy exact `UMA_0.12.app`;
- update separately confirmed Desktop dev folder safely;
- exact-path launch/smoke/termination;
- hash parity;
- stop.

### 16.10 M5RMX-SYNC-G1 — Founder GitHub synchronization

**Model:** GPT-5.6 Sol
**Effort:** High
**Mode:** Release Mode / remote action
**Subagents:** `implementer`, `send_safety_auditor`, `Repo Hygiene Guard`, `qa_runner`, `examiner`

Outcomes:

- verify target remote and divergence;
- scan exact commit range;
- integrate into Founder main without force;
- push authorized refs only;
- verify remote main commit/tree;
- stop.

### 16.11 M5RMX-CLOSE-G1 — final current-truth closeout

**Model:** GPT-5.6 Sol
**Effort:** High
**Mode:** Full Goal — milestone closeout
**Subagents:** `docs_operator`, `Source Integrity Auditor`, `qa_runner`, `examiner`

Outcomes:

- update current mutable source truth;
- record final Claude extension/runtime/privacy/UI/package/delivery/GitHub state;
- record rollback and known limits;
- clean worktrees/indexes;
- declare M5RMX complete;
- no automatic next milestone.

---

## 17. Verification standard

Every implementation/debug/UX/package Goal uses claim-matched verification.

Minimum applicable suite:

```text
focused Claude Browser Sync tests
Safari extension unit/fixture tests
extension manifest/permission validation
Claude bridge/native-host tests
Claude local activity tests
Claude Settings/localization tests
provider registry / UsageStore / Maximum Decrement
Main Panel / Desktop Assistant
Codex regressions
WorkBuddy regressions
Antigravity regressions
full deterministic script/test.sh
Debug build
Release build
strict-concurrency Release
native-host strict build
JavaScript/manifest/Info.plist/entitlement checks
Developer ID signature checks where applicable
privacy/identity/secret scan
package inventory/provenance
independent staged-index review
```

Current reported baseline is 683 tests. Do not delete/weaken tests to preserve that count. Legitimate coverage may increase it.

Live browser, signing, notarization, Gatekeeper, installation, or remote claims cannot PASS from fixtures alone.

---

## 18. Privacy and evidence contract

Allowed durable data:

- safe Claude window IDs/labels;
- remaining percentage;
- reset/cycle type;
- source/layout version;
- observation/freshness;
- bounded failure category;
- local token aggregates;
- versioned estimated cost;
- extension/native-host/package versions;
- minimized account-mode classification;
- signing/notary status and public submission identifier;
- package hashes/provenance.

Forbidden durable data:

- Claude password/API key/token;
- Keychain item contents;
- cookies/browser profile;
- account identity/email/name/avatar;
- prompt/response/reasoning/project content;
- raw DOM/HTML/page dump;
- payment method/invoices/history;
- Apple Account password/app-specific password;
- certificate private key;
- unrelated signing identities;
- broad process argv/environment;
- exact private values in screenshots/reports.

A privacy incident is FAIL until contained, corrected, independently audited, and explicitly closed.

---

## 19. Git and artifact policy

Hard rules:

```text
Do not use git add .
Do not use git add -A.
Do not use git add -u.
Do not reset --hard.
Do not clean for convenience.
Do not discard unrelated WIP.
Do not force-push.
```

- stage exact paths/hunks;
- one local commit per accepted Goal;
- generated/private evidence stays outside Git;
- packages remain under the persistent package root;
- no credential/profile/provider data in Git;
- final package is commit-exact;
- remote actions only in M5RMX-SYNC-G1.

Suggested commit subjects:

```text
docs(m5rmx): establish Claude completion baseline
docs(m5rmx): adopt Claude privacy and source contract
feat(claude): complete signed Safari extension support
feat(claude): complete Claude usage experience
fix(claude): close Claude runtime defects
style(claude): refine Claude usage experience
chore(m5rmx): integrate Apple distribution handoff
build(m5rmx): prepare UMA 0.12 candidate
docs(m5rmx): record UMA 0.12 closeout
```

---

## 20. Risk register

| ID | Risk | Impact | Required handling |
|---|---|---|---|
| M5RMX-R01 | Accepted Claude behavior is accidentally rebuilt | Regression | B0 claim-to-code map; preserve current owners/tests |
| M5RMX-R02 | New privacy rule is misread as permission for UMA to read secrets | Privacy failure | Provider may use secret internally; secret never crosses into UMA |
| M5RMX-R03 | Extension receives broad website permission | Privacy failure | Exact Claude origin/route; no All Websites |
| M5RMX-R04 | Raw DOM/page state crosses native handoff | Privacy failure | Semantic extraction and sanitization in extension |
| M5RMX-R05 | User tabs are adopted/navigated/closed | Data/usability loss | Proven extension-owned tab lifecycle |
| M5RMX-R06 | Signed extension/host identities do not match | Runtime failure | Bundle/entitlement/native-host identity audits |
| M5RMX-R07 | Unsigned development state leaks into final package | Distribution failure | Off-state cleanup and package inventory |
| M5RMX-R08 | Apple smoke ticket is treated as final 0.12 ticket | False release | Final-byte notarization only |
| M5RMX-R09 | Apple handoff remains In Progress or invalid | Release block | H1 exact status/log; no blind resubmit |
| M5RMX-R10 | Local activity appears as account remaining | Misinformation | Two-channel separation and UI tests |
| M5RMX-R11 | Claude page/layout changes | Source outage | Versioned semantic contract; fail closed |
| M5RMX-R12 | Scheduler/tab/native races multiply resources | Stability | DBG concurrency/lifecycle matrices |
| M5RMX-R13 | Claude changes regress protected providers | Product regression | protected-provider audit/full suite |
| M5RMX-R14 | UX work broadens into product redesign | Scope explosion | Claude-specific bounded scope |
| M5RMX-R15 | Old/new bundle IDs corrupt migration | Support failure | coexistence/migration/rollback matrix |
| M5RMX-R16 | Wrong GitHub remote is pushed | Delivery failure | exact remote/divergence gate |
| M5RMX-R17 | Desktop update removes rollback | Recovery loss | preserve `UMA_0.11.app` |
| M5RMX-R18 | Package contains private/development artifacts | Privacy/distribution failure | strict inventory and scans |
| M5RMX-R19 | GitHub source differs from package | Provenance failure | commit-exact package and remote verification |
| M5RMX-R20 | Decorative subagents duplicate work | Cost/noise | distinct evidence contracts, shared packet, 3–6 roles |

---

## 21. M5RMX PASS criteria

M5RMX passes only when all are true:

1. current development stage is reviewed and documented;
2. accepted Claude work is proven present and preserved;
3. updated privacy boundary is adopted;
4. Claude/Safari may use provider-owned credentials internally;
5. credentials never cross into UMA;
6. Browser Sync remains supported or is replaced only by a superior admitted source;
7. Claude Safari Extension is complete as a production component;
8. extension permissions are least-privilege and exact-site;
9. semantic extraction occurs before native handoff;
10. raw page/identity/auth data never crosses into UMA;
11. extension-owned tab lifecycle passes;
12. signed extension works with Safari unsigned mode Off;
13. ordinary-user onboarding and migration pass;
14. account capacity and local activity remain separate channels;
15. Main Panel Claude block is complete;
16. Settings/diagnostics/source transparency are complete;
17. Desktop Assistant parity is complete;
18. scheduler/handoff/cache/disconnect behavior passes adversarial debug;
19. no blocking/major Claude defect remains;
20. protected provider mechanisms are unchanged;
21. aesthetic/usability repair passes Light/Dark, EN/zh-CN, accessibility, and density;
22. Apple infrastructure handoff is accepted;
23. exact final source is frozen;
24. `UMA_0.12.app` exists under persistent package root;
25. final nested code is Developer ID signed with correct identities;
26. final exact archive is notarized Accepted;
27. staple/validate/Gatekeeper pass;
28. package contains no private/development artifacts;
29. Desktop `UMA_0.12.app` matches accepted package;
30. Desktop `UMA_0.11.app` remains rollback;
31. separately confirmed Desktop development folder is updated safely;
32. accepted source is synchronized to Founder GitHub repository;
33. remote main contains final accepted source commit;
34. current source records reflect 0.12 truth;
35. worktrees are clean and indexes empty;
36. every Goal used subagents with distinct evidence contracts;
37. no Cursor/Kimi/new-provider work occurred;
38. M5RMX is explicitly closed with no automatic next task.

---

## 22. Failure and pause rules

Return `BLOCKED` only for a genuine external gate after in-scope alternatives are exhausted, such as:

- required Apple terminal result unavailable;
- unavoidable Human Safari permission/login action;
- missing Developer ID/notary asset despite current report;
- unresolved Founder remote identity;
- remote service unavailable during authorized push.

Do not repeat the same Human gate three times.

Return `FAIL` when:

- accepted Claude functionality is lost;
- credential/private page data crosses into UMA;
- extension permissions are broader than accepted;
- Browser Sync is removed without passing replacement;
- tests/builds/audits fail;
- blocking/major defect remains;
- signed identities/entitlements are wrong;
- final package/source provenance differs;
- wrong remote/Desktop path is mutated;
- a required subagent/equivalent independent pass is silently omitted;
- final delivery claim is unsupported.

`PASS WITH RISKS` is allowed only for an external historical coverage limitation that does not affect current source truth, privacy, signing, package acceptance, or user flow.

---

## 23. Immediate next action

The first task is:

```text
M5RMX-B0
```

It may begin immediately.

It performs:

- lineage verification;
- branch/worktree creation;
- Plan/Goal/Scope Lock installation;
- full retrospective;
- accepted Claude claim-to-code map;
- Claude Safari Extension/native-host/signing inventory;
- Apple handoff state classification;
- Desktop/remotes inventory;
- deterministic baseline;
- docs/test commit;
- Completion Lock.

It does not modify production Claude behavior, sign/notarize final UMA, push, or deliver the Desktop app.

After M5RMX-B0 PASS, the only next task is:

```text
M5RMX-G1
```
