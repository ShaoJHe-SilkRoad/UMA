# UMA Logic 1.4

**Document type:** Current product, data, security, and implementation contract  
**Version:** 1.4  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Canonical remote branch:** `main`  
**Current canonical main commit:** `469be4d6cf411a89401c2341807a57aef176d852`  
**UMA 0.11 integration commit:** `ff6553943280836fb0d3db5289f85b163c41c1a3`  
**Qualified UMA 0.11 development commit:** `459ea1321817e391ba80fe79f19edb0352fc76cb`  
**Current installed application:** `/Users/juliushe/Desktop/UMA_0.11.app`  
**Current version/build:** `0.11 / 202607270003`  
**Current production-capable providers:** Codex and WorkBuddy  
**Next provider program:** Manus official API v2 integration  
**Status:** Replaces UMA Logic 1.3.1. Sections describing Manus are locked M4 target contracts and must not be represented as shipped until M4 passes.

---

## 0. Truth hierarchy

Use this order:

```text
Current Founder instruction
→ current live repository/main evidence
→ latest accepted DEV report
→ current accepted package/runtime evidence
→ this Logic 1.4
→ Goal Mode 2.0
→ Scroll 2.0
→ current milestone Plan and Goals
→ historical logic, plans, screenshots, and packages
```

The DEV 3 handoff remains the primary historical record for UMA 0.11. Its pre-merge GitHub statements are superseded by the merged `main` evidence recorded above.

A future legitimate `main` commit may supersede the fixed hashes in this header. DEV must inspect and record that change rather than silently using a stale commit.

---

## 1. Purpose

UMA is a local-first macOS menu-bar monitor for AI Agents whose current usage can be read honestly through an admitted source.

The governing architecture is:

```text
one macOS host application
→ one registered-provider catalog
→ provider-specific source admission
→ one connector instance per admitted provider
→ one serialized UsageStore
→ one shared presentation policy
├── one compact multi-Agent main panel
└── one optional Desktop Assistant
```

UMA is not:

- a directory of installed AI applications;
- a task launcher;
- an account-management dashboard;
- a billing system;
- a provider-control layer;
- a credential extractor;
- a browser scraper for arbitrary providers.

A provider is visible because its current usage is readable, not merely because its application is installed.

---

## 2. Current implementation truth

### 2.1 Accepted shipped foundation

UMA 0.11 includes:

- one native macOS application;
- one status item;
- one detailed compact main panel;
- one optional floating Desktop Assistant;
- one provider registry;
- one serialized UsageStore;
- one shared presentation path;
- equal Codex and WorkBuddy Agent cards;
- independent Agent details;
- independent Agent Settings;
- global Show All / Hide All;
- persistent per-Agent preferences;
- first-run manual Agent search;
- optional later Auto Search;
- centralized Maximum Decrement selection;
- Codex live usage and local activity details;
- WorkBuddy all-pool Account Web Sync;
- WorkBuddy one-minute Auto Refresh;
- native percentage and Credit value types;
- Light/Dark and accessibility appearance support;
- English and Simplified Chinese;
- package-safe serif/native-CJK/tabular-numeric typography;
- single-contour medium-transparency glass;
- main-panel/Desktop Assistant provider parity.

### 2.2 Current provider truth

#### Codex

```text
Source class:
localStructured

Primary source:
codex app-server --stdio

Additional approved local sources:
Codex session metadata and token-count logs for recent tasks and API-equivalent cost estimation

Authentication:
existing Codex session

Status:
live-qualified

Visibility:
only after a current successful admitted read
```

#### WorkBuddy

```text
Source class:
authenticatedAccountWeb

Primary source:
isolated UMA-owned WorkBuddy account web session

Authentication:
provider-controlled login inside isolated WKWebView

Status:
live-qualified / Experimental source

Visibility:
only after one complete current all-pool Credit read
```

#### Claude Code

```text
Current source:
not admitted on the current Mac

Status:
deferred

Visibility:
hidden
```

#### Manus

```text
Candidate source class:
officialRemoteUsageAPI

Candidate endpoint:
GET /v2/usage.availableCredits

Authentication:
API key only under current official documentation

Status:
M4 target, not shipped

Visibility:
hidden until source admission, implementation, secure credential configuration, and current successful read
```

### 2.3 Process and ownership invariant

Expected normal maximum ownership:

```text
1 host app process
1 status item
0 or 1 reused Desktop Assistant panel
1 provider registry
1 serialized UsageStore
1 shared presentation policy
1 connector instance per admitted provider
<= 1 app-owned Codex child
0 or 1 WorkBuddy WKWebView
0 or 1 WorkBuddy Auto Refresh timer
0 overlapping WorkBuddy reads
0 Assistant-owned provider clients
0 arbitrary installed-app scanning loops
```

After Manus is admitted, add:

```text
0 or 1 Manus API client owned by the Manus connector/source layer
0 or 1 Manus refresh scheduler
0 overlapping Manus reads
0 Manus API key copies outside Keychain and transient request memory
```

---

## 3. Governing product principles

### 3.1 Honest native units

- Percentage-based plan limits remain percentages.
- WorkBuddy remains native Credits.
- Manus remains native Credits.
- Credits are not converted into tokens, tasks, currency, or a fake percentage.
- Missing is not zero.
- Unlimited is not 100%.
- A grant quota is not a current balance.
- A source subtotal is not automatically an account total.
- A cached snapshot is not a current provider read.

### 3.2 Current successful read

A provider is admitted into the usage surfaces only after a current accepted read.

Do not keep a provider visible solely because:

- it was previously visible;
- its app is installed;
- a credential exists;
- the previous launch succeeded;
- a stale snapshot exists;
- a manual value exists;
- a source endpoint is documented but has not been read.

### 3.3 Shared surface truth

Required invariant:

```text
main visible provider IDs
==
Desktop Assistant visible provider IDs
==
current admitted provider IDs
```

Both surfaces consume the same immutable presentation models.

### 3.4 Fail closed

When source semantics, schema, scope, or reconciliation are ambiguous:

- reject the current observation;
- withdraw surface admission;
- keep only safe internal diagnostics;
- do not guess;
- do not silently substitute stale or manual data;
- do not select the number closest to a historical value.

### 3.5 Provider independence

One provider can be healthy while another is unavailable.

No provider failure may blank the entire product.

No provider may overwrite another provider’s value, state, timer, credentials, or settings.

### 3.6 Monitoring only

UMA does not:

- start AI tasks to generate usage;
- buy Credits;
- upgrade or cancel plans;
- change provider account settings;
- send messages;
- control provider conversations;
- access invoices, payments, or orders.

---

## 4. Source classes and admission

### 4.1 Source classes

Conceptual model:

```swift
enum ProviderSourceClass {
    case localStructured
    case authenticatedAccountWeb
    case officialRemoteUsageAPI
    case manualOnly
}
```

Current use:

| Source class | Current provider | Production status |
|---|---|---|
| `localStructured` | Codex | Accepted |
| `authenticatedAccountWeb` | WorkBuddy | Accepted WorkBuddy-specific exception |
| `officialRemoteUsageAPI` | Manus | M4 target, not shipped |
| `manualOnly` | WorkBuddy legacy compatibility record | Retained, not a live surface fallback |

### 4.2 Surface admission

Conceptual result:

```swift
enum ProviderSurfaceAdmission {
    case admitted(LocalLiveProviderSnapshot)
    case hiddenNotConfigured
    case hiddenNotRunning
    case hiddenNotAuthenticated
    case hiddenNoAdmittedSource
    case hiddenCurrentReadFailed
    case hiddenUnsupported
}
```

Only `.admitted` produces a provider card or Assistant row.

### 4.3 Local structured admission

For Codex-like sources:

```text
registered provider
+ required runtime/service available
+ authenticated session usable
+ admitted structured source
+ current successful read
= visible
```

### 4.4 WorkBuddy account-web admission

```text
registered WorkBuddy provider
+ explicit Account Web Sync consent
+ isolated UMA-owned official web session
+ authenticated session
+ verified usage route
+ complete all-pool observation
+ successful reconciliation
= visible
```

WorkBuddy.app is not required for this source.

### 4.5 Official remote API admission

For the planned Manus source:

```text
registered Manus provider
+ official endpoint admitted
+ user-configured API key stored in Keychain
+ secure read request
+ strict schema validation
+ current successful balance read
= visible
```

The Manus desktop application is not required if the official API source passes admission.

### 4.6 Hidden-provider rule

Do not display:

- installed but unreadable providers;
- logged-out providers;
- providers with invalid or missing credentials;
- unsupported providers;
- stale current data after admission loss;
- placeholder cards;
- partial WorkBuddy pool reads;
- Manus documentation-only candidates without a live read.

Hidden reasons may appear in Settings and safe diagnostics.

---

## 5. Provider registration and discovery

### 5.1 Registered catalog

UMA may inspect only registered providers.

Conceptual descriptor:

```swift
struct RegisteredProviderDescriptor {
    let id: AgentConnectorID
    let stablePriority: Int
    let formalDisplayName: String
    let sourceClass: ProviderSourceClass
    let runtimePolicy: ProviderRuntimePolicy
    let authenticationPolicy: ProviderAuthenticationPolicy
    let sourceAdmission: ProviderSourceAdmission
    let settingsCapabilities: ProviderSettingsCapabilities
}
```

Do not infer provider support from arbitrary process names, bundle names, icons, or categories.

### 5.2 Search behavior

First-ever search:

```text
manual
```

Later launch:

```text
Auto Search ON
→ one bounded registered-provider eligibility scan

Auto Search OFF
→ zero launch scans
```

Search does not inspect arbitrary applications.

### 5.3 Search triggers

Allowed:

1. application launch when Auto Search is enabled;
2. explicit Search/Refresh action;
3. explicit Check Again after a supported login or connection flow.

Not allowed from:

- opening/closing the main panel;
- showing/hiding the Assistant;
- countdown rendering;
- expansion/collapse;
- Settings navigation;
- appearance change;
- language change;
- density change;
- app activation alone.

### 5.4 Remote API providers

A remote API provider may be eligible without a local provider process.

For Manus, source readiness depends on:

- secure credential configuration;
- endpoint support;
- current read success.

Do not require the Manus desktop app merely to satisfy a local-runtime assumption.

---

## 6. Shared data path

```text
RegisteredProviderDescriptor
→ ProviderEligibilityCoordinator
→ AgentConnectorRegistry
→ provider-specific validation/normalization
→ serialized UsageStore
→ SharedUsagePresentationPolicy
→ AgentCardViewModel
├── main panel
└── Desktop Assistant
```

### 6.1 Main-application ownership

The host application owns:

- app lifecycle;
- status item;
- provider catalog;
- provider eligibility;
- provider login/configuration routing;
- connector registry;
- UsageStore;
- source clients;
- source timers/observers;
- selected-window policy;
- normalized safe persistence;
- Settings;
- panel/frame persistence.

### 6.2 Desktop Assistant ownership

The Assistant owns only:

- one panel lifecycle;
- Regular/Minimalist presentation;
- drag/position behavior;
- context menu;
- action delegation;
- rendering of shared models.

### 6.3 Prohibited Assistant ownership

The Assistant must never create:

- a connector;
- a provider process;
- a WebView;
- an API client;
- an API key store;
- a timer;
- a file observer;
- a source scanner;
- a selected-window calculation;
- Credit validation;
- a private production snapshot cache;
- a second status item or app lifecycle.

---

## 7. Value model

Conceptual shared value:

```swift
enum AgentAvailabilityValue {
    case percentage(remainingPercent: Double)
    case credits(CreditBalance)
    case unlimited
    case unavailable
    case invalid(reason: SafeUsageError)
}
```

Conceptual Credit balance:

```swift
struct CreditBalance: Equatable, Sendable, Codable {
    let remaining: Decimal
    let used: Decimal?
    let total: Decimal?
    let unit: CreditUnit
    let scope: CreditScope
    let observedAt: Date
    let provenance: AvailabilityProvenance
    let nextRefreshAt: Date?
}
```

Actual source types may use integer authority when the provider guarantees integer Credits. Conversion into shared Decimal must be exact.

---

## 8. Percentage semantics

### 8.1 Remaining-only display

Every compact percentage means remaining usage.

```text
remainingPercent = 100 - usedPercent
```

Clamp only after valid provider parsing.

Do not turn:

- token count;
- context usage;
- task count;
- session cost;
- duration;

into plan remaining percentage.

### 8.2 One selected-window result

Percentage-provider selected-window output is shared by:

- main collapsed summary;
- main Minimalist row;
- Desktop Assistant;
- tooltip;
- VoiceOver;
- status summary input.

Views do not independently choose a window.

### 8.3 Maximum Decrement

Within one accepted reset epoch:

```text
rawChange = previousRemaining - currentRemaining
decrement = max(0, rawChange)
```

Selection order:

1. valid depleted override;
2. valid critical override;
3. largest positive decrement rate;
4. deterministic tie-break;
5. retain previous valid selection during no-change periods;
6. cold-start lowest finite remaining;
7. explicit unlimited handling;
8. unavailable/error fallback.

Required safeguards:

- increases caused by reset/refill do not win;
- expired epochs cannot win;
- invalid windows cannot win;
- unlimited is not treated as 100%;
- selection is centralized.

Credit providers do not use this algorithm.

---

## 9. Credit semantics

### 9.1 Native Credits

WorkBuddy and Manus values are Credits.

Do not label them as:

- percent;
- tokens;
- requests;
- dollars;
- task count.

### 9.2 Exact authority

WorkBuddy uses exact Decimal values.

Manus API v2 currently documents integer Credit fields. Preserve integer authority and convert exactly to shared display types.

Do not use binary floating point as semantic or persisted authority.

### 9.3 Fraction

A fraction may be calculated only when one complete same-observation, same-scope current total is valid.

Do not derive a percentage from:

- a monthly grant quota;
- a next-refresh grant amount;
- an incomplete pool;
- a plan name;
- a historical purchase;
- a task-history sum.

### 9.4 Absolute-only balance

When only an exact spendable balance exists:

```text
remaining > 0
→ available

remaining == 0
→ exhausted
```

Do not apply a universal absolute low-Credits threshold.

### 9.5 Shared thresholds

When a complete valid fraction exists:

```text
26...100% → normal
11...25%  → warning
0...10%   → critical
```

Invalid and unavailable override quota thresholds.

### 9.6 Compact formatting

Credit compact formatting reuses deterministic truncation:

```text
0                  → 0
0 < value < 1      → <1
1...999.99         → floor(value)
1,000...999,999    → k
1,000,000...       → M
1,000,000,000...   → B
```

No upward rounding or unit prepromotion.

Exact surfaces show the complete value.

For Manus integer Credits, exact surfaces do not invent `.00` unless the shared visual contract explicitly requires fixed decimal formatting for all Credit providers. Provider-native integer display is preferred.

---

## 10. State model

Keep these independent.

### 10.1 Runtime state

Examples:

- active;
- inactive;
- local service unavailable;
- local runtime not required.

### 10.2 Authentication/configuration state

Examples:

- existing authenticated local session;
- isolated account-web session authenticated;
- API key configured;
- API key missing;
- invalid credential;
- reauthentication required.

### 10.3 Source state

Examples:

- admitted;
- refreshing;
- reconnecting;
- current read failed;
- unsupported schema;
- no admitted source.

### 10.4 Quota state

Examples:

- normal;
- warning;
- critical;
- depleted/exhausted;
- unlimited;
- unavailable;
- invalid.

### 10.5 Valid combination

```text
healthy source
+
low quota
```

is valid.

A low quota never means the source is disconnected.

---

## 11. Main panel

### 11.1 Role

The main panel is the detailed usage, source, and settings surface.

It displays only admitted providers.

### 11.2 Hierarchy

```text
UMA header
→ compact global controls
→ equal provider cards
→ independent details
→ independent Agent Settings
→ compact footer
```

Codex is not the global hero dashboard.

WorkBuddy is not a subordinate strip.

Future Manus is an equal provider card after admission.

### 11.3 Global controls

- Show All;
- Hide All;
- Search/Refresh as defined by current UI;
- no global combined percentage.

### 11.4 Expansion

Expansion uses stable connector IDs.

Data updates do not collapse expanded cards.

Expansion does not trigger provider discovery or source reads.

### 11.5 Agent Settings

Each provider has independent Settings.

Settings may persist while the provider is hidden.

A future schema fails closed.

Credentials are not stored in normal preference records.

### 11.6 Stable order

Order comes from provider priority.

Do not reorder by:

- quota;
- Credits;
- freshness;
- failure;
- reset time;
- process start;
- login time;
- source class.

---

## 12. Desktop Assistant

### 12.1 Role

The Desktop Assistant is:

- optional;
- presentation-only;
- floating;
- draggable;
- restorable;
- nonactivating during ordinary display;
- optionally Always on Top;
- driven by shared provider models.

### 12.2 Modes

Only:

```text
Regular
Minimalist
```

Ultra Minimalist is not a separate mode.

### 12.3 Forced Minimalist

```text
visible providers > 4
→ force Minimalist
```

The stored manual preference is preserved and restored when the forced condition ends.

### 12.4 Regular

Regular may show:

- provider mark;
- formal name;
- native value;
- optional plan/source detail;
- selected window for percentage providers;
- reset or update information.

### 12.5 Minimalist

Visible hierarchy:

```text
provider/source-state mark
→ compact native value
```

Do not visibly add:

- plan tier;
- reset;
- `remaining`;
- `available`;
- extra internal bar;
- close button;
- title.

Tooltips and VoiceOver retain full semantics.

### 12.6 Zero-provider behavior

When no provider is admitted:

- do not show an empty Assistant shell;
- preserve enabled, position, Always-on-Top, and density settings.

### 12.7 Read independence

Showing/hiding the Assistant does not:

- create or cancel provider timers;
- trigger provider reads;
- create a WebView;
- reset cadence;
- change admission.

---

## 13. Visual system

- public macOS APIs only;
- one contour/material owner;
- medium-transparency glass;
- no duplicate outlines;
- no nested full-shell glass;
- no Dark Mode white slab;
- Light/Dark adaptive;
- Reduce Transparency fallback;
- Increase Contrast support;
- Reduce Motion support;
- package-safe system-serif Latin roles;
- native CJK fallback;
- tabular numeric values;
- technical monospaced text only where justified.

Exact Anthropic Serif is not bundled.

---

## 14. Codex contract

### 14.1 Source split

Keep three data classes distinct:

```text
rate limits and account-level token totals
→ Codex app-server account methods

recent-task cumulative tokens
→ approved local Codex session logs

API-equivalent cost
→ local visible token logs + model pricing snapshots
```

### 14.2 Authentication

UMA reuses the existing Codex session through the local app-server.

UMA does not ask the user to enter an OpenAI API key.

### 14.3 Limits

Provider `usedPercent` is converted to remaining percentage.

Reset times retain local-time presentation.

Expired windows cannot win selected-window logic.

### 14.4 Recent tasks

Recent task titles and cumulative counts come from approved local Codex session metadata/logs.

They remain inside Codex details.

### 14.5 Token Cost

Token Cost is a local API-equivalent estimate, not an OpenAI invoice.

Requirements:

- separate uncached input, cached input, and output pricing;
- frozen pricing snapshots;
- child-task inherited baseline subtraction;
- malformed or decreasing counters fail closed;
- local ledger remains private;
- unsupported pricing reduces coverage rather than inventing cost.

### 14.6 Failure

On current Codex read failure:

- withdraw current admission;
- hide Codex from usage surfaces;
- preserve safe troubleshooting;
- allow later recovery.

---

## 15. WorkBuddy contract

### 15.1 Source classification

```text
Provider:
WorkBuddy

Source:
authenticatedAccountWeb

Source ID:
workbuddy.accountWebCredits

Scope:
buddyAI.sharedCredits

Provenance:
Account web sync

Support:
Experimental
```

### 15.2 Authentication

The user signs in through an isolated UMA-owned official WorkBuddy web session.

UMA does not collect:

- password;
- SMS code;
- QR content;
- cookies;
- tokens.

WebKit session material remains opaque to app business logic.

### 15.3 Account observation

A complete observation includes:

- subscription base;
- subscription bonus;
- add-on packages;
- benefit/gift packages.

```text
subscriptionRemaining
+ addOnRemaining
+ benefitGiftRemaining
= calculatedTotalRemaining
```

A subscription subtotal is not the account total.

### 15.4 Arithmetic

Use exact Decimal.

For each pool:

```text
remaining = total - used
```

Reject:

- negative values;
- used greater than total;
- excessive precision;
- invalid dates/status;
- ambiguous duplicate rows;
- mismatched displayed/calculated values.

### 15.5 Pool inclusion

Include current valid Buddy AI pools.

Do not require the `使用中` badge.

Do not merge distinct equal-value packages merely because their numbers match.

### 15.6 Atomicity

One read returns either:

- one complete valid current account observation; or
- one rejected observation.

Do not combine current and stale sections.

### 15.7 Auto Refresh

Default:

```text
ON
```

Cadence:

```text
no sooner than 60 seconds after the previous read completes
```

Requirements:

- one timer;
- one WebView;
- one in-flight read;
- no overlap;
- no catch-up burst;
- manual read resets the next interval;
- auth expiry suspends scheduled reads;
- Disconnect cancels reads.

OFF means Manual only.

### 15.8 Failure

On auth expiry or extraction failure:

- withdraw admission;
- hide WorkBuddy;
- no manual fallback;
- no stale visible fallback;
- show concise Settings state;
- no rapid retry.

### 15.9 Disconnect

Disconnect:

- cancels Auto Refresh;
- clears only UMA-owned WorkBuddy website data;
- clears current web-derived snapshot;
- hides WorkBuddy;
- leaves external browser and WorkBuddy.app sessions untouched;
- preserves the legacy manual record without using it as fallback.

---

## 16. Manus M4 target contract — not shipped

### 16.1 Source decision

Preferred source:

```text
GET https://api.manus.ai/v2/usage.availableCredits
Header: x-manus-api-key
```

Source class:

```text
officialRemoteUsageAPI
```

This source is documentation-supported but remains conditional until M4 live admission.

### 16.2 Why this source

The official endpoint is designed to return the caller’s Credit balance and refresh information.

For a personal account, it returns the personal balance.

For an API key belonging to a team sub-account, it returns the team shared-pool balance.

UMA must describe the scope conservatively when the response does not include an explicit account-type field.

Recommended compact scope:

```text
Manus Credits
```

Recommended detailed explanation:

```text
Balance for the Manus account represented by this API key.
A team sub-account key may represent a shared team pool.
```

Do not assert `Personal` or `Team shared` without an explicit trusted field or user-confirmed setting.

### 16.3 Authentication boundary

Current official documentation requires an API key for this endpoint.

Requirements:

- user creates the key through the official Manus API settings;
- user enters it directly into UMA;
- store it only in macOS Keychain;
- never persist it in UserDefaults, JSON, logs, fixtures, snapshots, crash reports, Git, or package resources;
- never print it;
- never return it in a DEV report;
- never ask the user to paste it into Codex or ChatGPT;
- no reveal-after-save control by default;
- disconnect deletes the Keychain item and current Manus snapshot;
- failed migration leaves no plaintext copy.

Because a Manus API key may grant broad account access, it is a high-sensitivity secret.

### 16.4 Network client

Use:

- `URLSession`;
- standard TLS validation;
- exact host `api.manus.ai`;
- exact v2 endpoint;
- bounded response size;
- bounded timeout;
- no unexpected redirect;
- one in-flight request;
- safe HTTP status mapping;
- strict JSON decoder;
- no automatic task creation;
- no broad API discovery call during ordinary refresh.

Do not use a general-purpose embedded browser for this source.

### 16.5 Allowed fields

Initial M4 allowlist:

```text
total_credits
free_credits
periodic_credits
addon_credits
pro_monthly_credits
event_credits
refresh_credits
max_refresh_credits
next_refresh_time
refresh_interval
```

No other response fields are required.

### 16.6 Field semantics

#### `total_credits`

Authoritative spendable balance.

Use as the primary Manus native value.

Do not reconstruct a different primary total from components.

#### `free_credits`

Free/system-granted balance component.

Optional detail.

#### `periodic_credits`

Current remaining subscription-period Credits.

Optional detail.

#### `addon_credits`

Current add-on/credit-pack balance.

Optional detail.

#### `event_credits`

Current active-event balance.

Optional detail.

#### `refresh_credits`

Current remaining auto-refresh Credits.

Optional detail.

#### `pro_monthly_credits`

Monthly issuance quota.

It is not the current balance and not a denominator for remaining percentage.

#### `max_refresh_credits`

Amount issued by one refresh.

It is not current balance and not a denominator.

#### `next_refresh_time`

Next refresh timestamp when applicable.

Treat as Unix seconds UTC.

Reject impossible or out-of-range timestamps.

#### `refresh_interval`

Expected values:

```text
daily
weekly
empty
```

Unknown future values fail safely or remain hidden detail.

### 16.7 Value presentation

Primary:

```text
exact total_credits
```

Main panel and Regular Assistant:

```text
full integer Credits
```

Minimalist:

```text
deterministic compact k/M/B Credits
```

Do not append `%`.

Do not infer warning/critical from an absolute balance.

`0` means Manus Credits exhausted.

Do not claim the entire Manus product is unavailable solely because the balance is zero.

### 16.8 Refresh

Planned initial policy:

```text
launch read when configured
+ explicit Manual Refresh
+ provider Sync Now
+ optional Auto Refresh no faster than 60 seconds
```

Requirements:

- one timer maximum;
- one in-flight request;
- no overlap;
- no catch-up burst;
- no immediate failure retry;
- manual read resets cadence;
- key/auth failure suspends scheduled reads until user action.

M4-G1 may tighten this policy if official endpoint limits require it.

### 16.9 Surface admission

```text
valid Keychain credential
+ admitted endpoint
+ current successful strict read
= visible Manus
```

On current read failure:

- withdraw admission;
- hide Manus;
- preserve a safe Settings error;
- do not display a stale balance as current.

### 16.10 Settings

Disconnected:

```text
Manus
Official API v2

Not connected

[ Connect Manus ]
```

Connection:

```text
Manus API Key
[ SecureField ]

The key is stored in macOS Keychain and is never shown again.
[ Save and Verify ]
```

Connected:

```text
Manus
Official API v2

Connected
Updated <relative time>

Auto Refresh [On/Off]
[ Sync Now ] [ Disconnect ]
```

Do not show or log the raw key.

### 16.11 Excluded first-version API surfaces

M4 initial integration does not use:

- `usage.list`;
- task titles;
- collaborator names;
- task messages;
- task creation;
- project endpoints;
- connector endpoints;
- files;
- webhooks;
- browser clients;
- account writes.

`usage.list` may expose task/session history and collaborator information and is not required to monitor the current spendable balance.

### 16.12 Human live-validation gate

For live validation:

1. DEV builds a candidate.
2. Human opens the candidate.
3. Human creates or retrieves an official Manus API key outside Codex.
4. Human pastes the key into the candidate SecureField.
5. Candidate performs a bounded read.
6. Human confirms that the displayed balance matches the official Manus interface.
7. DEV receives only redacted success/failure evidence.

The key never appears in the development transcript.

---

## 17. Secret handling

### 17.1 Keychain

Provider secrets that must be stored by UMA use macOS Keychain.

Normal preference stores may retain only:

- configured/not configured;
- safe connection state;
- timestamps;
- nonidentifying settings;
- schema version.

### 17.2 Prohibited secret paths

Do not store secrets in:

- `UserDefaults`;
- plist;
- JSON;
- source tree;
- `.env` committed to Git;
- command-line arguments;
- process environment used by report tooling;
- temporary logs;
- fixtures;
- screenshots;
- package resources;
- crash diagnostics;
- raw analytics.

### 17.3 DEV access

Codex/DEV must not inspect:

- raw Keychain values;
- API-key text;
- browser cookies;
- token stores;
- authentication databases.

Live validation is user-controlled through the product UI.

### 17.4 Error text

Do not include secret fragments in errors.

Safe examples:

```text
API key not configured
Authentication failed
Current Credits could not be read
Unsupported response
```

---

## 18. Refresh and synchronization

### 18.1 One application-wide refresh

One global Manual Refresh produces at most:

- one Codex refresh;
- one WorkBuddy current read;
- one Manus current read after M4;
- one serialized presentation update per provider result.

### 18.2 Provider-specific cadence

Each provider owns its accepted cadence.

The Assistant never multiplies cadence.

### 18.3 Coalescing

For each provider:

```text
one active read
→ redundant scheduled trigger dropped
→ manual trigger may request at most one bounded follow-up
```

No read storms.

### 18.4 No rendering reads

Relative time, countdown, animation, expansion, language, density, and appearance changes cause no provider read.

---

## 19. Settings and persistence

Persist only safe settings:

- Assistant enabled;
- Always on Top;
- density preference;
- Automatic density setting;
- plan/source visibility choices;
- restore position;
- safe frame/display ID;
- per-Agent nonsecret settings;
- Auto Search;
- WorkBuddy Auto Refresh;
- WorkBuddy keep-signed-in choice;
- Manus Auto Refresh after M4;
- provider connection configured boolean;
- schema versions.

Do not persist in normal settings:

- credentials;
- raw cookies;
- API keys;
- account identity;
- raw provider payload;
- conversation/task content;
- process IDs as durable authority;
- a second Assistant usage cache.

Future preference schemas fail closed.

---

## 20. Privacy and diagnostics

### 20.1 Never collect without a separate accepted contract

- passwords;
- raw access/refresh tokens;
- API keys outside Keychain;
- Authorization headers;
- cookies exported from WebKit;
- SMS/QR data;
- account email/name/ID;
- billing address;
- payment methods;
- invoices/orders;
- conversation text;
- task content;
- source code;
- private app databases;
- process memory;
- browser state outside an admitted isolated source;
- full environment or argv dumps.

### 20.2 Safe process diagnostics

Do not use:

```text
ps ... command
ps ... args
ps e...
env
printenv
```

Use bounded fields:

```text
pid
ppid
elapsed time
state
approved executable basename/path
owned-child count
```

### 20.3 Evidence

- raw provider responses remain temporary;
- normalize/redact before reporting;
- screenshots remain unstaged;
- real balances are not published in public fixtures;
- secret/config backups remain outside Git;
- packages contain no session, snapshot, credentials, or governing docs unless explicitly part of source distribution.

---

## 21. Performance and reliability

Required:

- one connector per admitted provider;
- no duplicate observers/timers;
- one WorkBuddy WebView maximum;
- one Manus API client maximum after M4;
- zero overlapping provider reads;
- no Assistant source ownership;
- stable provider IDs;
- failure isolation;
- bounded persistence;
- no missed-cycle burst;
- no immediate failure retry;
- bounded CPU/RSS/thread/descriptor behavior;
- clean termination;
- no orphan child/helper process.

Debug milestones verify claim-matched resource behavior.

---

## 22. Packaging

Every accepted package must prove:

- exact commit provenance;
- version/build;
- bundle identity;
- architecture;
- minimum macOS;
- signature;
- expected dependencies;
- fixture isolation;
- no tests/logs/screenshots;
- no raw provider response;
- no WorkBuddy session data;
- no Manus API key;
- no Keychain export;
- no manual WorkBuddy record;
- no real account balance fixture;
- no config backup.

The current Desktop application remains protected until explicit replacement authority.

Public release, Developer ID signing, notarization, and GitHub Release remain separate Release Mode work.

---

## 23. Required test matrix

### 23.1 Shared architecture

- zero providers;
- Codex only;
- WorkBuddy only fixture;
- Codex + WorkBuddy;
- Codex + WorkBuddy + Manus fixture after M4;
- independent failures;
- stable order;
- no hidden spacing;
- main/Assistant parity;
- no duplicate connector.

### 23.2 Percentage

- finite values;
- 0%;
- unlimited;
- unavailable;
- invalid;
- reset/refill increase;
- expired epoch;
- tie;
- no-change retention;
- centralized selected-window parity.

### 23.3 Credits

- 0;
- 1;
- large value;
- exact Decimal WorkBuddy;
- integer Manus;
- absolute-only balance;
- complete fraction;
- invalid negative/overflow;
- compact truncation;
- no unit prepromotion;
- no universal absolute warning threshold.

### 23.4 WorkBuddy

Retain the full accepted:

- pool aggregation;
- duplicate handling;
- expiry/effective-state;
- Auto Refresh;
- coalescing;
- auth expiry;
- disconnect;
- privacy;
- Settings;
- surface parity.

### 23.5 Manus — required after M4

Offline:

- missing key;
- key configured flag without key access;
- Keychain save/read/delete through production abstraction tests;
- request construction without logging header;
- exact host/path;
- redirects rejected;
- timeout;
- HTTP 200/401/403/429/500;
- malformed JSON;
- missing data;
- missing `total_credits`;
- negative/overflow values;
- unknown fields ignored safely;
- optional fields absent;
- timestamp bounds;
- refresh interval daily/weekly/empty/unknown;
- no `usage.list` request;
- no task API call;
- one in-flight request;
- no retry storm;
- disconnect clears current snapshot.

Live:

- user-controlled key entry;
- one successful read;
- official balance parity;
- invalid-key recovery;
- relaunch with Keychain credential;
- Manual Refresh;
- Auto Refresh cadence;
- no secret in logs/process args/artifacts;
- current-read failure hides Manus.

### 23.6 UI/accessibility

- Light/Dark;
- Reduce Transparency;
- Increase Contrast;
- Reduce Motion;
- English/Chinese;
- keyboard;
- VoiceOver;
- Settings scrolling;
- Regular/Minimalist;
- forced Minimalist when visible count exceeds four;
- stable position/focus.

---

## 24. Acceptance criteria

Logic 1.4 is correctly implemented for the current 0.11 product when:

1. the merged `main` lineage is recorded;
2. Codex and WorkBuddy are the only current production providers;
3. the main panel and Assistant share one provider set;
4. equal Agent cards and Agent Settings remain;
5. first manual search and optional Auto Search remain;
6. Maximum Decrement remains centralized and reset-safe;
7. WorkBuddy all-pool Account Web Sync remains exact and atomic;
8. WorkBuddy Auto Refresh remains no faster than one minute after completion;
9. Credits remain native;
10. no Assistant source ownership exists;
11. privacy, package, and resource boundaries remain;
12. unsupported providers remain hidden.

The Manus M4 contract passes only when:

13. the official v2 source is admitted;
14. the API key is stored only in Keychain;
15. DEV never reads or logs the key;
16. `usage.availableCredits` is the only required initial endpoint;
17. `total_credits` is the primary authoritative value;
18. quota/grant fields are not misrepresented as current balance;
19. no fake percentage is created;
20. one current successful read is required for visibility;
21. current-read failure withdraws admission;
22. no task is created or Credit intentionally consumed;
23. no task history or collaborator data is collected;
24. main and Assistant use one shared Manus presentation;
25. no duplicate timer/client exists;
26. live, privacy, package, and resource evidence pass;
27. a commit-exact M4 package exists;
28. installed Desktop replacement remains separately authorized.

---

## Appendix A — Locked current decisions

1. `main` is canonical after PR #3.
2. UMA 0.11 is closed and qualified.
3. Codex and WorkBuddy are current production providers.
4. Claude Code is deferred, not fabricated.
5. Manus is the next provider program.
6. Manus uses an official API source if admission passes.
7. Manus API key entry is allowed only through a secure product flow.
8. Manus key storage is Keychain-only.
9. No raw key enters Codex, logs, Git, or normal preferences.
10. `total_credits` is the intended primary Manus value.
11. Manus remains absolute Credits, not percentage.
12. `usage.list` is excluded from the first integration.
13. The Assistant remains presentation-only.
14. Visible-provider count, not roadmap slot, controls forced Minimalist.
15. Remote push/release/notarization remain separate authority.

---

## Appendix B — Conceptual Manus models

```swift
struct ManusCreditsSnapshot: Equatable, Sendable, Codable {
    let totalCredits: Int64
    let freeCredits: Int64?
    let periodicCredits: Int64?
    let addonCredits: Int64?
    let proMonthlyCredits: Int64?
    let eventCredits: Int64?
    let refreshCredits: Int64?
    let maxRefreshCredits: Int64?
    let nextRefreshAt: Date?
    let refreshInterval: ManusRefreshInterval?
    let observedAt: Date
    let source: ManusCreditsSource
}

enum ManusCreditsSource: String, Codable, Sendable {
    case officialAPIV2
}

enum ManusRefreshInterval: String, Codable, Sendable {
    case daily
    case weekly
}
```

Actual names may differ. Runtime behavior and security must map to this contract.

---

## Appendix C — Current provider status

| Provider | Source class | Authentication | Current status | Primary value |
|---|---|---|---|---|
| Codex | localStructured | Existing Codex session | Live-qualified | Remaining percentage |
| Claude Code | none admitted | Unavailable | Deferred | — |
| WorkBuddy | authenticatedAccountWeb | Isolated provider web login | Live-qualified | Exact Credits |
| Manus | officialRemoteUsageAPI candidate | API key in Keychain | M4 target | Exact Credits |
| Cursor/Kimi+/Doubao | none admitted | Unavailable | Not started | — |

---

## Appendix D — Governing references

Current:

```text
Scroll_2.0.md
UMA_Logic_1.4.md
UMA_0.11_closeout.md
Provider_Status_Matrix.md
M4_Plan.md
M4_Goal.md
Goal_Mode_2.0.md
```

Historical:

```text
DEV 3 shift report
UMA Logic 1.3.1
Scroll 1.2
M3 Plan / Goals
M2W Plan / Goals
Monitor Mechanism historical reference
accepted QA ledgers, scope locks, and package closures
```

Official Manus references are listed in Scroll 2.0 and M4 Plan.
