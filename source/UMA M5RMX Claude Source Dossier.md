# UMA M5RMX Claude Source Dossier

**Version:** 1.3

**Date:** 2026-08-29

**Goal:** M5RMX Claude root-repair final closeout

**Status:** live Test source and deterministic closeout admitted; exact Git delivery pending

## Current admitted runtime evidence

The admitted runtime uses a Safari-free mutable UMA Test app and one immutable
Safari Host/Companion generation. Content-free Host qualification passed the
accepted cold/warm lifecycle matrices without Extensions UI. One real Accuracy
Sync then reached the approved Claude Usage destination, returned only the
allowlisted two-window observation, committed and read back the exact anchor,
published it, acknowledged it, and removed both the proven temporary tab and
its owner-only receipt.

Reset timestamps were absent and remained absent. The exact observation is
bounded to five minutes, cannot calibrate Local Smart, and cannot degrade into
an estimate. The committed anchor survived Safari quit and mutable UMA
relaunch without consent, permission, Companion, or connection re-setup.
No exact Founder quota value is durable evidence.

Final affected coverage passed `240/240`; race-sensitive individual,
parallel, and load verification passed `2184/2184`; two consecutive full
deterministic runs passed `963/963` each. Signing trust was stable for ten
strict/deep checks apiece against the unchanged mutable app, immutable Host,
and Companion. The independent examiner found no remaining product defect.

## Current source owner — Founder override

The current default source architecture is:

```text
Claude Code official status-line callback
→ bounded stdin read
→ immediate allowlist projection
→ owner-only atomic sanitized state
→ exact anchors + sanitized local-activity calibration
→ deterministic five-hour and seven-day estimates when exact truth is absent
→ shared presentation
```

The relay is one-shot: it reads, projects, atomically writes sanitized state,
optionally invokes one exact preserved prior status-line command through a
nonrecursive compatibility bridge, and exits. It has no socket, daemon,
listener, network path, environment capture, or log. The raw status-line stdin
contains broader session/workspace fields; those fields are discarded during
projection and cannot be represented by the sanitized packet.

Official exact status-line quota fields are documented for Pro/Max and occur
after a first API response. Missing exact callbacks therefore do not become
zero. The estimator requires two compatible exact anchors, derives its
coefficient only from observed anchor deltas, never assumes a plan denominator,
and fails closed across reset/schema/model/account discontinuities.
Mixed windows preserve independent truth: an exact window is never marked with
`≈` merely because the other window is estimated. Settings expose the current
estimate confidence and last exact observation time without retaining a private
quota value.

Safari is retained only for explicit one-shot Accuracy Sync. Each request may
create one inactive extension-owned exact Usage tab, perform one bounded read,
and close only that proven-owned tab. There is no persistent scheduler,
automatic retry, catch-up burst, or permanent owned tab.

The current installed immutable Safari Host build `202608281805` and runtime
generation `e55245ee-7baf-4791-aadc-f13b52209986` are forensic evidence, not a
final candidate. No current live Accuracy Sync has been admitted. The next
Safari enablement is suspended until the consolidated state-machine, API,
owned-tab, native-IPC, privacy, package/signing and examiner gates all pass.

Read-only installed-runtime evidence at forensic entry:

```text
Host ID:             com.silkrd.uma.test.safarihost
Host CDHash:         06d5658bdd3e7461fd04e75e1d0f7703fed979e5
Host bundle digest:  79f4fe913c1ea6e971cc0629f0b23bff89a03b7ad33ea0cde2bdbdc36d80fa73
Companion ID:        com.silkrd.uma.test.safarihost.ClaudeBrowserCompanion
Companion CDHash:    53ec25480aa98da945593cd2ef45b48945777b62
Companion digest:    c38a80893f06f4992cb2c843705b2a504ed41c935055da87c5dda9eec3c0166c
Team ID:             C6TUZVJ6SJ
Required App Group:  group.com.silkrd.uma.test.bridge
```

These hashes classify only the installed `1805` intermediate. They must not be
reused as the final frozen-candidate record.

Sections below describe the predecessor architecture and remain historical
evidence only where they conflict with this current source owner.

## Current Safari source architecture — forensic authority

### Owned Provider Tab V2 source decision

**Selected:** direct provider tab plus self-identifying provider content
script. A separate controller tab adds lifecycle surface without strengthening
provider ownership. Safari-native `SFSafariWindow` / `SFSafariTab` creation is
not selected because those APIs are documented for Safari App Extensions, not
as an ownership authority for this Safari Web Extension target.

Authority classification:

- **Documented Apple behavior:** Safari Web Extensions use the WebExtension
  model; content scripts message background code; native messaging crosses
  through background/native extension boundaries. Apple does not document a
  stable tab-ID guarantee across the rejected cross-origin self-navigation.
- **Cross-browser WebExtension behavior:** `tabs.create()` is asynchronous;
  content-script sender metadata can identify its tab; fragment identifiers
  are not matched by URL match patterns; `onRemoved` and `onReplaced` are
  lifecycle signals, not ownership proof.
- **Observed Safari behavior:** the accepted live sequence retired the owned
  internal bootstrap identity before provider readiness and emitted removal
  semantics that the old reducer treated as terminal.
- **UMA inference and design:** provider ownership is the conjunction of one
  durable request, one-time nonce digest, current runtime generation, trusted
  top-frame content-script Port, exact provider surface and `sender.tab.id`.

The manifest-declared ownership script is inert on an unmarked user-owned
Claude tab and performs no DOM query or extraction. At `document_start`, it
captures the one-time marker in its isolated world and synchronously removes it
by same-document history replacement before starting the ownership Port. This
keeps Claude's provider-controlled hash exact while the asynchronous durable
proof completes. After acceptance it idempotently revalidates the exact Usage
route against the same captured nonce before announcing provider readiness.
Extraction remains a separate, later exact-route action. There is no bootstrap
self-navigation, general tab enumeration or unknown-tab closure.

The only acceptable one-shot browser path is:

```text
Mutable UMA Test App
→ bounded request in group.com.silkrd.uma.test.bridge
→ immutable UMA Safari Host Test App
→ Safari dispatch to its embedded Companion
→ persistent MV2 background
→ one canonical native port
→ SafariWebExtensionHandler
→ sanitized correlated Host receipt
→ bounded App Group result
→ Mutable UMA consumption
```

The immutable Host architecture is the correct security boundary, subject to
final package and live qualification. It keeps ordinary UMA UI/Local Smart
development outside Safari's signed containing-app/appex identity. It is not
proved merely by prior 10/10 machine handshakes or app-only update tests; the
complete provider extraction, cleanup and restart lifecycle still must pass.

### Responsibility inventory

| Responsibility | Owner | Reason / boundary |
|---|---|---|
| Manifest, exact-site permission, background wake and Safari tab APIs | `MUST_STAY_IN_EXTENSION` | Requires WebExtension privilege and Safari-owned page context |
| Exact route/login/layout gate, bounded DOM extraction and sanitization | `MUST_STAY_IN_EXTENSION` | Raw page state must be projected before crossing the browser boundary |
| Direct inactive provider-tab creation, trusted sender proof, exact tab-ID lifecycle and proven-tab closure | `MUST_STAY_IN_EXTENSION` | Requires direct authority over the one request-owned Safari tab; the create result alone is only a candidate |
| `runtime.connectNative`, retained Port, native reply acknowledgement and disconnect classification | `MUST_STAY_IN_EXTENSION` | This is Safari's supported extension-to-native bridge |
| Signed Host/appex identity and runtime-generation validation | `MUST_STAY_IN_EXTENSION` and Host | Each side independently proves the same signed generation |
| Request serialization, phase deadlines, cancellation authority, atomic terminal response and content-free diagnostics | `CAN_MOVE_TO_HOST` | No provider-page privilege is required; Host is the stable Safari authority |
| Durable owner-only receipt persistence/expiry and App Group handoff | `CAN_MOVE_TO_HOST` / native handler | Persistence must survive background reload without giving the extension broad storage or filesystem access |
| Consent, Accuracy Sync UI, Local Smart, cache/presentation, app-shell state and one-shot scheduling | `CAN_MOVE_TO_MUTABLE_UMA` | Product policy and local sources must remain independent of Safari runtime availability |
| Direct Safari dispatch from mutable UMA, toolbar-driven acquisition, generic tab discovery, `tabs.get` recovery, unused `tabs.update`/`tabs.reload` gates and duplicate native transports | `OBSOLETE` | They either violate the Host boundary, depend on unsupported discovery, or create competing lifecycle paths |

### Explicit Companion state machine

Every transition is request/generation correlated and permits only the listed
side effect. A deadline bounds a stalled state; it never creates readiness.

| State | Trigger and preconditions | Allowed effect / durable ownership | Failure and cleanup owner |
|---|---|---|---|
| `DORMANT` | no accepted request | no tab or native transaction | none |
| `STARTING` | signed runtime identity loaded | install listeners before any acknowledgement | identity/protocol mismatch → `FAILED` |
| `REQUEST_ACCEPTED` | one current request, no in-flight request | retain exact request/generation; reject a second request | cancellation → `CANCELLED` |
| `NATIVE_BRIDGE_CONNECTING` | request accepted | open one retained native Port; install message/disconnect listeners first | open/disconnect deadline → `FAILED` |
| `NATIVE_BRIDGE_READY` | native handler acknowledged the same request/generation | no provider or tab access | stale/duplicate acknowledgement rejected |
| `SITE_PERMISSION_CHECKING` | provider consent exists and a real Accuracy Sync was requested | query only exact declared site access | absent/revoked → `FAILED`, no tab |
| `REQUEST_INTENT_PERSISTED` | permission passes; a nonce digest and bounded request/generation are durably saved | no tab exists and no close authority exists | expiry removes the intent only when no candidate/proof exists |
| `PROVIDER_CREATION_PENDING` | durable intent accepted | create one inactive direct provider tab carrying only the short-lived fragment nonce; durably bind the returned ID as a candidate | create failure cannot close an unproved candidate |
| `PROVIDER_DOCUMENT_DISCOVERED` | top-frame exact-provider content-script Port presents the nonce | correlate trusted `sender.tab.id`, digest, request, generation and candidate; still no extraction/close authority | mismatch → `FAILED` without tab closure |
| `PROVIDER_OWNERSHIP_PROVEN` | native compare-and-swap accepts the exact correlated candidate as owned after the content script already sanitized the marker at document start | arm exact-ID removal/replacement listeners; revalidate the canonical Usage route with the isolated captured nonce | wrong/stale generation, route drift or replacement remains unproved |
| `PROVIDER_READY` | the proved provider content script confirms the idempotent exact-route finalization | retain one correlated Port | route/login/permission uncertainty → fail closed |
| `EXTRACTING` | exact route and login gate pass | perform one bounded allowlisted extraction | reload never restarts an in-flight extraction |
| `RESULT_READY` | one sanitized observation validates | freeze one closed payload; duplicate results rejected | no terminal success yet |
| `RESULT_DELIVERED` | native Port acknowledges the correlated sanitized payload | request cleanup | disconnect/late response → `FAILED` |
| `CLEANUP_REQUESTED` | terminal result/failure still has current proved Port and tab ID | remove only that exact proved tab | ownership uncertainty retains one blocking tombstone |
| `CLEANUP_CONFIRMED` | exact removal succeeds or the owned-tab removal event is correlated | delete the exact terminal receipt | deletion failure never reports success |
| `COMPLETE` | result acknowledged and cleanup receipt removed | publish one terminal success; release port/resources | terminal and idempotent |
| `CANCELLED` | current request cancellation accepted | reject late replies; clean only proved ownership | terminal after bounded cleanup |
| `FAILED` | explicit first broken phase | emit only bounded reason; clean only proved ownership | terminal; no automatic provider retry |

### Safari API conclusions

The following statements deliberately separate authority classes:

- **Documented platform fact:** Safari extension enablement is Human-controlled;
  the state manager exposes a bounded enabled-state snapshot, not a proof that
  a dispatched message reached the background or native handler.
- **Documented API surface plus engineering conclusion:** containing-app
  dispatch has an operation completion handler, but the API does not supply the
  request-correlated background/native/application receipt UMA requires;
  therefore dispatch completion is not end-to-end readiness proof.
- **Observed UMA evidence:** Safari retired the internal bootstrap identity
  during its cross-origin self-navigation. V2 therefore creates the final
  provider tab directly and uses `active: false` only on that one creation.
- **Engineering inference, verification-pending:** ordinary mutable UMA updates
  should require zero Safari action because neither the immutable Host nor the
  Companion identity/bytes change.

Primary platform references:

- Apple, [SFSafariExtensionManager](https://developer.apple.com/documentation/safariservices/sfsafariextensionmanager)
  and [SFSafariExtensionState.isEnabled](https://developer.apple.com/documentation/safariservices/sfsafariextensionstate/isenabled)
  for the bounded enablement-state API;
- Apple, [dispatchMessage](https://developer.apple.com/documentation/safariservices/sfsafariapplication/dispatchmessage%28withname%3Atoextensionwithidentifier%3Auserinfo%3Acompletionhandler%3A%29)
  for containing-app dispatch;
- Apple, [Messaging between the app and JavaScript in a Safari web extension](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)
  for the containing app / native handler / WebExtension boundary;
- Apple, [Managing Safari web extension permissions](https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions)
  and [Running your Safari web extension](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)
  for Human-controlled site/extension setup;
- Apple, [Optimizing your web extension for Safari](https://developer.apple.com/documentation/safariservices/optimizing-your-web-extension-for-safari)
  for Safari background lifecycle constraints.

These references do not promise that website permission or enablement survives
every signed binary/containing-host replacement. UMA's persistence expectations
are therefore tested product invariants, not undocumented platform guarantees.

Active API contract:

| API | Final bounded use | Safari-specific control |
|---|---|---|
| `tabs.create` | create one direct provider tab after durable intent | intentionally uses `active: false`; the returned ID is durably bound only as a candidate until the trusted content-script sender independently matches it |
| `tabs.sendMessage` | not used for V2 ownership or reload recovery | the request-scoped content-script Port is the only provider-document channel |
| `tabs.remove` | close only a currently proved request-owned tab | removal must succeed before terminal success and receipt deletion |
| `tabs.query` / `tabs.get` | absent from the active ownership path | no tab enumeration or URL-based rediscovery |
| `tabs.update` / `tabs.reload` / `tabs.executeScript` | absent from V2 provider ownership and extraction | the manifest content script is installed at `document_start`; no self-navigation or injection race remains |
| `tabs.onRemoved` / `tabs.onReplaced` | lifecycle hints for the exact proved ID only | replacement never transfers ownership; the new content-script sender must independently re-prove before extraction or closure |
| `runtime.connect` | provider content-script discovery and one bounded reload challenge | trusted top-frame sender metadata plus exact request/generation; no page messaging and no polling |
| `runtime.connectNative` | sole extension/native transport | Port retained for the request; listeners installed before dispatch; disconnect is explicit |
| permissions API | verify only the declared Claude site scope before provider work | absence is a site-permission state, not a machine-handshake failure |
| WebExtension storage | not a general tab database | ownership authority is the bounded owner-only Host/native receipt |

### Owned-tab invariants

- Persist exact creation intent before `tabs.create`.
- One request, generation and random nonce may bind at most one tab ID.
- The create return is never ownership. It is durably bound as one candidate;
  ownership requires the exact trusted provider content-script sender ID to
  match it under the same digest, request and generation.
- After reload, only the exact persisted proved provider-tab ID may answer one
  request-scoped challenge. Provider tabs are never rediscovered by a broad or
  URL-based query, and recovery never replays a raw nonce.
- Wrong nonce, wrong generation, stale receipt, duplicate proof, unknown tab,
  user closure, Safari closure, redirect, cancellation, crash, quit or expiry
  fails closed. `UNPROVEN TAB IS NEVER CLOSED`.
- Expiry bounds active work but cannot prove absence. One ambiguous receipt is
  retained as a content-free cleanup tombstone, no second tab may be created,
  and the product reports ownership recovery blocked. This is a safe terminal
  state, not a blind retry or permission/setup loop.
- A sanitized result is not terminal success until its proved tab is gone and
  the exact ownership receipt is removed. Result/cleanup races are resolved by
  the single state machine, not by another provider retry.

### Native IPC single-flight contract

Mutable UMA writes one closed request and wakes the stable Host. The Host
admits at most one request, creates operation-specific request/generation
correlation, establishes its result listener before Safari dispatch, and owns
monotonic phase deadlines. Dispatch acknowledgement, background
acknowledgement, native-port readiness, native-handler decode, signed-generation
validation, native reply, JS acknowledgement, cleanup and terminal Host result
are distinct phases. The terminal response is published atomically once.
Duplicate, stale, future-version, post-cancel and wrong-generation replies are
rejected with a fixed content-free reason rather than timing out generically.

### Consent, permission and product-state matrix

| Capability | Machine runtime qualified | Claude Test consent | `claude.ai` site permission | Provider data read | Safari required | Local Smart/app shell effect |
|---|---:|---:|---:|---:|---:|---|
| App shell, dropdown, Settings, Assistant | no | no | no | no | no | fully available |
| Local Smart exact/estimated local lanes | no | no | no | no | no | independent |
| Content-free Companion handshake | yes | no | no | no | yes | no effect on Local Smart |
| Show Accuracy Sync readiness | yes | no | no | no | yes | reports precise missing layer |
| Provider consent grant | yes | yes | no | no | no provider page | authorizes a future explicit read only |
| Site permission qualification | yes | yes | yes | no | yes | separate permission state |
| One real Accuracy Sync | yes | yes | yes | exactly one bounded read | yes | exact anchor may outrank estimate after validation |

There is no global `CLAUDE_CONNECTED` boolean that may collapse these layers.
Site permission is expected to persist across mutable UMA updates, immutable
Host relaunch, Safari relaunch and macOS restart because the Safari security
identity does not change; that is a product target requiring final live proof,
not an Apple guarantee inferred from a byte digest. A deliberate Host or
Companion migration is exceptional and may impose one
`PLATFORM_SECURITY_MIGRATION_COST`: Human enablement and, if Safari requests
it, one exact-site grant. Normal UMA update targets remain enablement `0`, site
permission action `0`.

## 1. Historical predecessor source owner — superseded

Claude account-capacity truth currently comes from:

```text
Safari owns Claude authentication and session state
→ exact https://claude.ai/new#settings/usage route
→ bounded semantic extraction in the Safari Browser Companion
→ versioned sanitized browser/native packet
→ owner-only local handoff and cache
→ ClaudeCodeUsageConnector
→ shared Main Panel and Desktop Assistant presentation
```

This was the accepted browser-first source before the active Founder override.
It is retained only as lineage evidence. It is not the current source contract
and does not authorize recurring Browser Sync.

## 2. Current source-candidate matrix

The candidates were evaluated in the required preference order. A higher rank
does not create authority; every replacement gate must pass.

| Rank | Candidate | Account-capacity truth | Automatic no-work refresh | Credential opacity | Current decision |
|---|---|---|---|---|---|
| 1 | Official Claude local service or IPC | No current official, documented, bounded account-quota contract is proven | Not proven | Local trust is unadmitted: current strict verification of Claude.app fails | `NOT ADMITTED` |
| 2 | Official hook, event, or status interface | Official status-line input documents five-hour and seven-day used percentages and matching reset fields | Callback-driven after normal Human Claude activity; no provider task or polling is generated by UMA | Raw status-line stdin is projected immediately by the bounded UMA relay; only the allowlisted packet persists | `ACCEPTED CURRENT VIA SANITIZED RELAY` |
| 3 | Official read-only CLI or provider-owned local metadata | No current documented read-only quota command with stable account-window schema is proven | Not proven | Current strict verification of the installed 2.1.220 CLI fails | `NOT ADMITTED` |
| 4 | Safari Browser Sync | Provider-rendered five-hour and weekly account windows remain an admitted exact calibration source | No recurring refresh; Human-requested one-shot Accuracy Sync only | Yes; Safari owns authentication and only a closed packet crosses | `RETAINED ONE-SHOT ACCURACY` |

Claude Desktop additionally exposes one Founder-authorized provider-owned cache
at `~/Library/Application Support/Claude/plan-usage-history.json`. The installed
Desktop implementation identifies schema v2 samples whose `fh` and `sd`
members are five-hour and seven-day utilization. This cache is undocumented and
has private-API ancestry, so it is not promoted to official or exact account
truth. UMA admits only the newest bounded sample after strict path, type, owner,
mode, size, schema, range, and freshness checks; discards `org` and every
unrelated field; converts utilization to remaining once; and publishes `≈`
estimates with no reset. It is a separate candidate, not an additive JSONL
activity stream and not a substitute for status-line or Safari exact truth.

### Claude Desktop activity adjudication

Repeated Founder-observed Claude Desktop responses produced no sanitized local
receipt. The historical scope failure was observed on Desktop 1.32885.1. A bounded
current recheck on Claude.app 1.34493.0 found the exact owner-only cache stale
and unchanged through an app launch window; its lifecycle is quota-refresh, not
response-notification. The Desktop-hosted surface does not resolve UMA's Claude Code
status-line scope, and the only separately authorized Desktop file is a quota
history cache rather than an event stream. A cache metadata change can refresh
an estimate, but cannot prove that a specific Desktop response occurred.

No stable privacy-safe Claude Desktop activity signal exists inside the current
authorized architecture. The honest fallback contract is:

- keep a fresh schema-v2 plan-cache sample as `≈` estimated quota only;
- never label cache creation or mutation as Desktop activity;
- state that Desktop automatic activity detection is unavailable;
- use Claude Code status-line exact values when that supported surface exists;
- use explicit Safari Accuracy Sync for current exact account truth;
- fail closed without a fresh estimate rather than displaying “activity
  detected” or fabricating a response receipt.

Local Smart Mode replaces persistent Browser Sync only because its bounded
status-line projection, exact-anchor continuity, local estimator, and explicit
one-shot Accuracy lane satisfy the current contract together. Any future
replacement must prove all of:

- official and documented authority;
- current account-capacity truth rather than this-Mac activity;
- explicit used-versus-remaining semantics;
- stable window identities and matching reset scopes;
- provider-owned authentication;
- zero Claude prompt/task generation and zero intentional spend;
- automatic refresh without requiring provider work;
- credential opacity and a bounded sanitized output;
- live parity with the official Usage surface;
- safe rollback to Browser Sync.

## 3. Official status-line delta and coverage

The current official status-line input contract includes:

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
```

These fields are the preferred exact local source only after immediate
allowlist projection by the UMA status-line relay. They are supplied after a
normal Human Claude response; UMA does not create a response, poll the provider,
or rerun a status-line command to fabricate freshness. Broader session and
workspace fields are discarded before any UMA-owned state is written.

Documented quota-field coverage is Claude.ai Pro and Max. Team, Enterprise, and
unknown account modes are not qualified and must not be inferred from Pro/Max
schema evidence. Safari remains an optional one-shot Accuracy source for
calibration and comparison; it is not the always-on owner.

## 4. Current local trust result

Read-only strict verification on 2026-08-17 returned:

```text
$HOME/.local/bin/claude: invalid signature (code or signature have been modified)
In architecture: arm64

/Applications/Claude.app: invalid signature (code or signature have been modified)
In architecture: arm64
```

The launcher resolves to `$HOME/.local/share/claude/versions/2.1.220`. These failures
remain a documented provenance limitation. Local Smart Mode does not inspect
credentials or treat the executable as an account-token authority; it accepts
only the official callback's allowlisted quota fields through the fail-closed
relay. Safari remains a provider-controlled, explicit one-shot Accuracy source.

## 5. Admitted account semantics

The current normalized account channel admits:

- five-hour used percentage and optional matching reset;
- weekly/all-model used percentage and optional matching reset;
- at most one explicitly scoped model-family weekly window when separately
  provider-rendered and unambiguous;
- observation time, source/browser classification, schema versions, exact-route
  verification state, and freshness.

Each percentage must be finite and within `0...100`. Both admitted exact lanes
transport provider-rendered **used** percentage. Shared production logic
performs exactly one conversion:

```text
remainingPercent = 100 - usedPercent
```

Missing, malformed, duplicate, or ambiguous windows are unavailable, never
zero. A missing reset stays unavailable. Five-hour and weekly windows remain
independent.

## 6. Continuation and usage-credit decision

No continuation, overage, extra-usage, usage-credit, billing-balance, purchase,
or payment field is currently admitted. The exact Usage extractor deliberately
excludes spending and billing sections. UMA must not infer continuation from a
quota percentage, local activity, plan label, model availability, or the
presence of an authenticated session.

Official usage-credit continuation means that `0%` included-plan remaining does
not prove Claude work must stop. UMA therefore presents that account window as
exhausted without claiming overall provider unavailability. Whether work can
continue through usage credits remains `UNAVAILABLE / UNKNOWN` until an
explicitly scoped provider-rendered continuation field is separately admitted.

If Claude later renders an explicit continuation state, it requires a separate
source-admission decision proving its label, scope, native unit, reset or cycle,
and privacy-safe extraction. Until then it is `UNAVAILABLE / NOT ADMITTED`.

## 7. Browser and native boundary

The current contract identifiers are:

```text
source ID: claude-browser-usage
message kind: claudeUsageObservation
bridge schema: 1
extractor schema: 1
maximum message: 4096 bytes
Safari extension: com.silkrd.uma.ClaudeBrowserCompanion
native message identity: com.silkrd.uma.claude_browser
exact Usage route: https://claude.ai/new#settings/usage
```

The current Safari manifest requests exactly `nativeMessaging` and
`https://claude.ai/new*`, with a persistent background script. This supersedes
historical activeTab/toolbar-only records; those describe an earlier product
stage, not the current runtime. The fragment cannot be represented in a host
permission, so the extension revalidates protocol, host, path, empty query, and
`#settings/usage` before any DOM query and again before returning a result.
There are no static content scripts or broader host permissions.

On the exact route, the extractor tries explicit provider-owned Usage-card
selectors first. If they are absent, it performs bounded in-browser matching of
exact allowlisted leaf-text landmarks across at most 4096 candidate elements.
That fallback may inspect unrelated leaf text transiently inside the browser as
it rejects nonmatches. It does not serialize, retain, or forward those strings;
only the normalized allowlisted observation may cross the native boundary.

The closed observation packet contains only fixed identifiers, browser family,
route state, observation time, extractor version, allowlisted quota windows,
optional matching resets, and an optional bounded model-family enum. The native
decoder rejects unknown keys, invalid schemas, oversized messages, invalid
timestamps, out-of-range percentages, and observations without an account
window.

## 8. Local Smart lifecycle and fallback

- one connector consumes callback-driven exact local state and bounded local
  activity; it owns no recurring Safari scheduler;
- one explicit Accuracy Sync may be in flight;
- at most one request-owned inactive Usage tab exists during that one-shot
  request;
- ownership uncertainty fails the request closed and never adopts a user-owned
  tab;
- authentication, permission, route, or layout uncertainty fails closed;
- a validated exact anchor may become Stale but never becomes current merely
  because it was restored;
- calibrated estimates are marked with `≈`, remain independent per window, and
  never outrank current exact truth;
- Disconnect stops the relay path, removes UMA-owned state, restores the exact
  prior Human statusLine fragment, and leaves Safari login data unchanged;
- local activity calibrates estimates but is never presented as provider exact
  account truth.

If exact local status is absent and no valid calibrated estimate exists, UMA
may show only a valid stale exact anchor or Missing. It must not fall back to
manual quota, API-key, Keychain, cookie, token, private endpoint, or an
uncalibrated estimate.

## 9. G1 decision

```text
LOCAL SMART MODE: ACCEPTED IMPLEMENTATION CANDIDATE; FINAL VALIDATION PENDING
EXACT LOCAL STATUS LINE: ACCEPTED THROUGH BOUNDED SANITIZED RELAY
SAFARI BROWSER SYNC: RETAINED ONE-SHOT ACCURACY ONLY
FIVE-HOUR WINDOW: ADMITTED
WEEKLY / SEVEN-DAY WINDOW: ADMITTED
MODEL-SPECIFIC WEEKLY WINDOW: OPTIONAL, EXPLICIT-SCOPE ONLY
CONTINUATION / USAGE-CREDIT STATE: NOT ADMITTED
OVERALL WORK AVAILABILITY AT 0% INCLUDED REMAINING: UNKNOWN
STATUS-LINE ROUTE: ACCEPTED CURRENT THROUGH UMA SANITIZER
STATUS-LINE ACCOUNT COVERAGE: PRO/MAX DOCUMENTED; TEAM/ENTERPRISE/UNKNOWN UNQUALIFIED
LOCAL CLI / CLAUDE.APP TRUST: UNADMITTED
```

The current forensic Goal preserves the accepted Local Smart source hierarchy
while consolidating the one-shot Safari Host/Companion lifecycle. Final frozen
package, physical provider read, cleanup, persistence, mutable-update stability
and regression acceptance all remain pending.
Owned Provider Tab V2 live requalification found a second route-lifecycle defect after ownership and cleanup worked: a transient Claude SPA hash transition was treated as terminal `routeRejected`. The repaired contract keeps exact-route-before-DOM enforcement and permits only content-free waiting within the already bounded readiness window; no broader route becomes an extraction source.

The provider-facing freeze candidate now separates the remaining lifecycle into explicit route, document, data, extraction, delivery and cleanup phases. Route and document signals are event-driven; the first stable-looking projection is confirmed on one render turn; transient login is confirmed twice; unsupported/malformed/missing states never become zero or an exact anchor. The provider layer returns only an allowlisted failure enum or one validated sanitized observation. Native/Host policy owns request correlation, generation validation, timeout cancellation, cleanup-first terminal publication and product-state mapping.

Background reload recovery accepts no new provider read. It may receive one replay of the exact correlated sanitized result, guarded by durable state and an explicit ACK. Crash recovery uses only exact known tab IDs: proven absence may complete receipt cleanup, while a present tab must reprove request, tab and generation before cleanup-only closure. Result delivery can no longer race ahead of successful tab/receipt cleanup.

No new Companion generation or provider read was used for this hardening phase. Freeze still requires the independent provider-layer examiner verdict and affected offline verification; live acceptance remains a later Human migration and separately authorized one-shot provider gate.
