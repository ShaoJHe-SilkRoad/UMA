# UMA Logic 1.5

**Document type:** Current product, source-admission, authentication, privacy, and implementation contract  
**Version:** 1.5  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Canonical remote branch:** `main`  
**Current canonical main commit:** `469be4d6cf411a89401c2341807a57aef176d852`  
**Accepted post-M4 local closeout commit:** `178e6ca47e514dc257ddd5db82a223e5eeb42b85`  
**Accepted post-M4 local closeout tree:** `1871b59ebe8ffdb59784292bf0a52cbde70e4925`  
**Current installed application:** `/Users/juliushe/Desktop/UMA_0.11.app`  
**Current installed version/build:** `0.11 / 202607270003`  
**Current production-capable providers:** Codex and WorkBuddy  
**Current milestone:** `M5 — Claude Code Local Structured Usage Support`  
**Status:** Replaces UMA Logic 1.4 completely. External API-key input is prohibited. Official provider-controlled login is permitted only as a bounded fallback after a local structured source is unavailable or insufficient.

---

## 0. Truth hierarchy

Use this order:

```text
Current Founder instruction
→ current live repository evidence
→ latest accepted DEV execution report
→ current accepted package/runtime evidence
→ this Logic 1.5
→ Goal Mode 2.0
→ Scroll 2.1
→ active milestone Plan and Goals
→ historical logic, plans, reports, screenshots, and packages
```

Current Founder policy overrides the API-oriented clauses in Logic 1.4 and the Manus-first clauses in Scroll 2.0.

The accepted M4-N result is:

```text
M4 CLOSED
Manus unsupported
No API-key product path
No M4-G3 WIP
Codex and WorkBuddy preserved
```

A later legitimate repository commit may supersede fixed hashes in this header. DEV must inspect and record the change instead of silently using stale identifiers.

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
- an API-key vault;
- a credential extractor;
- a manual quota notebook;
- a balance estimator;
- a browser scraper for arbitrary sites.

A provider is visible because its current usage is readable through an admitted source, not merely because its application is installed or the user entered a number.

---

## 2. Current implementation truth

### 2.1 Accepted shipped foundation

UMA 0.11 includes:

- one native macOS application;
- one menu-bar status item;
- one compact multi-Agent main panel;
- one optional floating Desktop Assistant;
- one provider registry;
- one serialized UsageStore;
- one shared presentation path;
- equal Codex and WorkBuddy Agent cards;
- independent Agent details and Agent Settings;
- global Show All / Hide All;
- persistent per-Agent nonsecret preferences;
- first-run manual Agent search;
- optional later Auto Search;
- centralized Maximum Decrement selection;
- Codex live usage and approved local activity details;
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
officialLocalStructured

Primary source:
codex app-server --stdio

Additional approved local source:
Codex session metadata and token-count logs for recent tasks and API-equivalent cost estimation

Authentication:
existing Codex session managed by Codex

Status:
live-qualified

Visibility:
only after a current successful admitted read
```

#### WorkBuddy

```text
Source class:
isolatedAccountWeb

Primary source:
isolated UMA-owned WorkBuddy account web session

Authentication:
provider-controlled login inside isolated WKWebView

Status:
live-qualified / Experimental source

Visibility:
only after one complete current all-pool Credit read
```

WorkBuddy is the proven reference implementation for provider-controlled login. Its implementation remains accepted. Logic 1.5 generalizes the source class, not WorkBuddy-specific selectors or pool rules.

#### Claude Code

```text
Candidate source class:
officialLocalStatusLine

Primary candidate source:
Claude Code official statusLine JSON on stdin

Authentication:
existing Claude Code provider-managed login

Status:
M5 NEXT / not shipped

Visibility:
hidden until source admission, relay implementation, and current successful payload
```

#### Manus

```text
API-key route:
retired and prohibited

Current admitted source:
none

Current status:
unsupported / deferred

Visibility:
hidden
```

Manus may be reconsidered only through a future Founder-authorized local-source dossier or isolated account-web login dossier. No external API-key route may be revived under Logic 1.5.

#### Later providers

Google Antigravity CLI, Kiro CLI, Kimi Code CLI, Junie CLI, Cursor, Windsurf, TRAE, Doubao/Ark, and other providers remain unadmitted until provider-specific source work passes.

### 2.3 M4 closeout truth

The M4 program ended with:

```text
M4-N commit:
178e6ca47e514dc257ddd5db82a223e5eeb42b85

M4-N tree:
1871b59ebe8ffdb59784292bf0a52cbde70e4925

Result:
M4 CLOSED — MANUS UNSUPPORTED — NO API-KEY PRODUCT PATH
```

The retired Manus API prototype remains historical Git evidence only. Production source and the M4-N package contain no Manus endpoint, authentication header, Keychain path, connector, scheduler, Settings entrance, or presentation route.

### 2.4 Process and ownership invariant

Expected normal maximum ownership:

```text
1 host application process
1 status item
0 or 1 reused Desktop Assistant panel
1 registered-provider catalog
1 provider eligibility coordinator
1 connector registry
1 serialized UsageStore
1 shared presentation policy
1 connector instance per admitted provider
<= 1 app-owned Codex child
0 or 1 WorkBuddy WKWebView
0 or 1 WorkBuddy Auto Refresh timer
0 overlapping WorkBuddy reads
0 Assistant-owned provider clients
0 arbitrary installed-app scanning loops
0 external API-key stores
```

After Claude Code M5 is admitted, add:

```text
0 or 1 Claude status-line relay helper
0 or 1 Claude local socket listener
0 duplicate Claude relay or observer
0 raw Claude payload files
0 UMA-owned Claude credentials
```

---

## 3. Governing product principles

### 3.1 Local-first, login-second

Provider source order is mandatory:

```text
official local structured source
→ official local status hook / status line / event
→ official read-only CLI or documented local metadata
→ isolated provider-controlled account login fallback
→ unsupported
```

A login fallback is considered only when the local route is unavailable, incomplete, or unsupported for the current account.

### 3.2 API-key input is prohibited

UMA must not ask a user to create, paste, import, or store an external provider API key.

This prohibition includes:

- API keys entered in UMA Settings;
- OAuth access tokens copied into UMA;
- long-lived setup tokens;
- personal access tokens;
- cloud-provider credentials;
- environment-based secrets installed for UMA;
- API-key helpers created for UMA.

Provider applications and CLIs may manage their own authentication internally. UMA may consume an admitted local usage output without receiving the credential.

### 3.3 Provider-controlled login is permitted

UMA may offer an official provider login only when:

- the provider controls the authentication page;
- UMA presents no custom username, password, SMS, QR, token, or API-key field;
- credentials remain opaque to UMA business logic;
- the source is restricted to current usage data;
- explicit user consent precedes the login;
- Disconnect removes UMA-owned session state.

### 3.4 Honest native units

- Percentage-based plan limits remain percentages.
- Credit-based balances remain Credits.
- Missing is not zero.
- Unlimited is not 100%.
- A grant quota is not a current balance.
- A source subtotal is not automatically an account total.
- A stale snapshot is not a current provider read.
- Session activity is not account remaining usage.

### 3.5 No manual balance system

UMA does not support:

- manual balance entry;
- manual deduction;
- estimated remaining quota;
- local countdown deduction;
- inferred balance from tasks, tokens, cost, or time;
- user-entered replacement values when a source fails.

The retained historical WorkBuddy manual record remains compatibility data only and never admits a provider or appears as a live fallback.

### 3.6 Current successful read

A provider enters the usage surfaces only after a current accepted observation.

Do not admit a provider solely because:

- its application is installed;
- a login session exists;
- a local helper exists;
- a stale snapshot exists;
- the provider worked on a prior launch;
- the user entered a number;
- a route is documented but unread.

### 3.7 Shared surface truth

Required invariant:

```text
main visible provider IDs
==
Desktop Assistant visible provider IDs
==
current admitted provider IDs
```

Both surfaces consume the same immutable presentation models.

### 3.8 Fail closed

When source semantics, schema, scope, route, or reconciliation are ambiguous:

- reject the current observation;
- withdraw surface admission;
- keep only safe diagnostics;
- do not guess;
- do not substitute manual or stale data;
- do not broaden selectors or endpoints automatically.

### 3.9 Provider independence

One provider can be healthy while another is unavailable.

No provider failure may blank the entire product.

No provider may overwrite another provider’s value, state, cadence, configuration, session, or settings.

### 3.10 Monitoring only

UMA does not:

- start AI tasks to generate usage;
- buy Credits;
- upgrade or cancel plans;
- change provider account settings;
- send messages;
- control provider conversations;
- access invoices, payments, orders, or task history.

---

## 4. Source classes and admission hierarchy

### 4.1 Conceptual source classes

```swift
enum ProviderSourceClass {
    case officialLocalService
    case officialLocalStatusLine
    case officialLocalCLI
    case isolatedAccountWeb
    case unsupported
}
```

There is no production `externalAPIKey` source class.

There is no production `manualValue` source class.

### 4.2 Tier L1 — official local service or IPC

Preferred examples:

- provider app-server;
- documented XPC service;
- documented Unix socket;
- documented loopback status endpoint;
- documented local OpenAPI;
- provider-owned structured snapshot file or event.

Admission requires:

```text
registered provider
+ documented local source
+ provider-managed authentication
+ current successful structured read
+ privacy allowlist
= visible
```

### 4.3 Tier L2 — official local status hook or status line

Accepted when the provider officially invokes a local command with structured usage data.

Requirements:

- exact documented schema;
- strict field allowlist;
- no raw payload persistence;
- no transcript or workspace read;
- no network capability in the relay;
- reversible provider configuration;
- no model request initiated by UMA.

Claude Code M5 targets this class.

### 4.4 Tier L3 — official read-only CLI or documented local metadata

Accepted when:

- the command is official and signed;
- the command is read-only;
- output is structured or contractually stable;
- the command directly returns current usage;
- authentication is managed by the provider CLI;
- the command does not execute a task or intentionally consume quota;
- raw output is discarded after normalization.

Human-oriented terminal scraping without a documented contract is not a stable production source.

### 4.5 Tier W — isolated account-web fallback

This source class is permitted only after local-source admission returns NO-GO or an accepted local source lacks the required current usage metric.

Required path:

```text
explicit provider connection consent
→ isolated UMA-owned WKWebView
→ official provider-controlled login
→ verified official usage route
→ bounded allowlisted extraction
→ current validated observation
→ visible provider
```

### 4.6 Unsupported sources

Reject:

- API-key or token entry;
- private databases or caches;
- browser cookie import;
- Keychain inspection;
- token extraction;
- network interception;
- packet capture;
- process memory;
- Accessibility or OCR extraction;
- arbitrary UI automation;
- undocumented private API replay;
- manual values;
- inferred usage.

### 4.7 Surface admission

Conceptual result:

```swift
enum ProviderSurfaceAdmission {
    case admitted(ProviderUsageSnapshot)
    case stale(ProviderUsageSnapshot, lastSuccessfulAt: Date)
    case hiddenNotConfigured
    case hiddenNotInstalled
    case hiddenNotRunning
    case hiddenNotAuthenticated
    case hiddenNoAdmittedSource
    case hiddenCurrentReadFailed
    case hiddenUnsupported
}
```

Only `.admitted` and a provider-contract-approved `.stale` state produce a visible row.

A stale state must be visually explicit and must never survive an app relaunch unless a separate contract permits safe normalized persistence.

### 4.8 Source selection

When more than one source is admitted:

- local structured source is the default;
- account-web login is labeled `Fallback`;
- source choice is explicit in Agent Settings;
- observations from different sources are never merged;
- switching source withdraws the old admission before activating the new source;
- one provider has only one active source at a time.

---

## 5. Account-web login fallback contract

### 5.1 Eligibility

A provider may receive an account-web fallback only when:

1. a local-source dossier has completed;
2. the local result is NO-GO or lacks the required account-level metric;
3. the provider has an official usage page;
4. the page can be read without account mutation;
5. the user explicitly authorizes the connection.

### 5.2 Authentication boundary

The user enters credentials only on the provider’s official page.

UMA must not provide custom fields for:

- username;
- password;
- passkey;
- SMS code;
- QR data;
- recovery code;
- API key;
- OAuth token;
- cookie.

Keep these concepts separate:

```text
login flow launched
login completed by user
authenticated isolated session usable
current usage read successful
```

Only the last condition admits the provider.

### 5.3 Isolated WebKit session

Use:

- one provider-specific `WKWebView` maximum;
- one provider-specific session controller;
- one narrow website-data scope;
- standard TLS;
- official domains only;
- explicit route verification;
- public WebKit APIs only.

Do not import Safari, Chrome, Edge, provider-app, or system browser sessions.

### 5.4 Persistence default

For newly added account-web providers:

```text
Keep signed in:
OFF by default
```

When OFF:

- use a nonpersistent website data store;
- clear the isolated session when the connection closes or the app terminates.

When the user explicitly enables Keep Signed In:

- provider-managed session material may remain inside the isolated WebKit data store;
- UMA business logic must not read, export, serialize, or log it;
- Disconnect clears only that provider’s UMA-owned website data.

WorkBuddy retains its already accepted behavior and migration rules.

### 5.5 Route and navigation restrictions

Allow only domains and routes required for:

- provider authentication;
- official usage/account page;
- mandatory provider redirects.

Unexpected external navigation is blocked or requires explicit user confirmation.

Extraction code runs only after exact origin and route verification.

### 5.6 Allowed fields

Provider-specific allowlists may include only data required for current usage presentation, such as:

- current remaining percentage;
- current Credits;
- used/total values when necessary for validation;
- reset or refresh time;
- plan label when nonidentifying;
- source timestamp;
- safe row status.

### 5.7 Forbidden fields

Do not collect:

- name;
- email;
- avatar;
- phone number;
- account or organization ID;
- billing information;
- invoices;
- orders;
- payment methods;
- task history;
- conversations;
- workspace content;
- referral data;
- raw page HTML;
- broad DOM text;
- cookies or storage values.

### 5.8 Read-only behavior

Allowed:

- open the verified usage page;
- wait for required landmarks;
- expand an approved usage section when necessary;
- read the bounded allowlisted values;
- perform Sync Now;
- disconnect.

Forbidden:

- upgrade;
- purchase;
- renew;
- cancel;
- change account settings;
- create tasks;
- modify plans;
- open billing or invoice pages.

### 5.9 Extractor behavior

The extractor must be:

- versioned;
- route-bound;
- field-allowlisted;
- deterministic;
- atomic;
- fail-closed;
- small-output only.

It must never return or persist full HTML, page source, scripts, storage, or raw network data.

### 5.10 Refresh defaults

For a newly admitted account-web provider:

```text
Auto Refresh:
OFF by default

Default behavior:
Manual only
```

Auto Refresh may become an opt-in provider setting after provider-specific cadence, rate, resource, and session-expiry tests pass.

WorkBuddy retains its accepted default ON / no-faster-than-60-seconds behavior.

### 5.11 Disconnect

Disconnect must:

- cancel provider reads and timers;
- clear provider admission;
- clear the current normalized snapshot;
- clear only UMA-owned provider website data;
- leave external browser and provider-app sessions untouched;
- preserve unrelated providers;
- hide the provider from both surfaces.

### 5.12 User assurance

Every account-web provider Settings page must show a Source Transparency section:

```text
Source
Official provider account page

Credentials visible to UMA
None

Browser sessions imported
None

Data read
Current usage fields only

Raw page stored
No

Account changes
None

[ Disconnect and Clear ]
```

---

## 6. Provider registration and discovery

### 6.1 Registered catalog

UMA may inspect only registered providers.

Conceptual descriptor:

```swift
struct RegisteredProviderDescriptor {
    let id: AgentConnectorID
    let stablePriority: Int
    let formalDisplayName: String
    let preferredSourceClass: ProviderSourceClass
    let fallbackSourceClass: ProviderSourceClass?
    let runtimePolicy: ProviderRuntimePolicy
    let authenticationPolicy: ProviderAuthenticationPolicy
    let sourceAdmission: ProviderSourceAdmission
    let settingsCapabilities: ProviderSettingsCapabilities
}
```

Do not infer provider support from arbitrary process names, bundle names, icons, or categories.

### 6.2 Search behavior

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

### 6.3 Search triggers

Allowed:

1. application launch when Auto Search is enabled;
2. explicit Search/Refresh action;
3. explicit Check Again after an approved install, login, or connection flow.

Not allowed from:

- opening or closing the main panel;
- showing or hiding the Assistant;
- countdown rendering;
- expansion or collapse;
- Settings navigation;
- appearance changes;
- language changes;
- density changes;
- app activation alone.

---

## 7. Shared data path and ownership

```text
RegisteredProviderDescriptor
→ ProviderEligibilityCoordinator
→ AgentConnectorRegistry
→ provider-specific validation and normalization
→ serialized UsageStore
→ SharedUsagePresentationPolicy
→ AgentCardViewModel
├── main panel
└── Desktop Assistant
```

### 7.1 Main-application ownership

The host application owns:

- app lifecycle;
- status item;
- provider catalog;
- provider eligibility;
- provider setup and login routing;
- connector registry;
- UsageStore;
- local relays, source clients, timers, and observers;
- selected-window policy;
- normalized safe persistence where admitted;
- Settings;
- panel and frame persistence.

### 7.2 Desktop Assistant ownership

The Assistant owns only:

- one panel lifecycle;
- Regular/Minimalist presentation;
- drag and position behavior;
- context menu;
- action delegation;
- rendering of shared models.

### 7.3 Prohibited Assistant ownership

The Assistant must never create:

- a connector;
- a provider process;
- a relay;
- a WebView;
- a timer;
- a file observer;
- a source scanner;
- a selected-window calculation;
- Credit validation;
- an authentication flow;
- a private snapshot cache;
- a second status item or app lifecycle.

---

## 8. Value model

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

Source-native integer authority must convert exactly into shared Decimal when required.

---

## 9. Percentage semantics

### 9.1 Remaining-only display

Every compact percentage means remaining usage.

```text
remainingPercent = 100 - usedPercent
```

Clamp only after valid provider parsing.

Do not turn token count, context usage, task count, session cost, or duration into plan remaining percentage.

### 9.2 One selected-window result

Percentage-provider selected-window output is shared by:

- main collapsed summary;
- main Minimalist row;
- Desktop Assistant;
- tooltip;
- VoiceOver;
- status summary input.

Views do not independently choose a window.

### 9.3 Maximum Decrement

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

- refill increases do not win;
- expired epochs cannot win;
- invalid windows cannot win;
- unlimited is not 100%;
- selection is centralized.

Credit providers do not use this algorithm.

---

## 10. Credit semantics

### 10.1 Native Credits

Credits are not percentages, tokens, requests, currency, or task counts.

### 10.2 Exact authority

WorkBuddy uses exact Decimal authority.

Future integer-Credit providers retain integer authority and convert exactly for shared presentation.

Do not use binary floating point for persisted or semantic authority.

### 10.3 Fraction

A fraction may be calculated only from a complete same-observation, same-scope current total.

Do not derive a fraction from:

- monthly grant quota;
- refresh grant amount;
- plan name;
- historical purchase;
- incomplete pool;
- task-history sum.

### 10.4 Absolute-only balance

When only an exact spendable balance exists:

```text
remaining > 0 → available
remaining == 0 → exhausted
```

Do not apply a universal absolute low-Credits threshold.

### 10.5 Compact formatting

Credit compact formatting uses deterministic truncation:

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

---

## 11. State model

Keep these independent.

### 11.1 Runtime state

Examples:

- active;
- inactive;
- local service unavailable;
- local runtime not required.

### 11.2 Authentication/configuration state

Examples:

- existing provider-managed local session;
- isolated account-web session authenticated;
- login required;
- connection not configured;
- unsupported authentication mode.

`API key configured` is not a valid Logic 1.5 product state.

### 11.3 Source state

Examples:

- admitted;
- waiting for first event;
- refreshing;
- reconnecting;
- stale;
- current read failed;
- unsupported schema;
- no admitted source.

### 11.4 Quota state

Examples:

- normal;
- warning;
- critical;
- depleted/exhausted;
- unlimited;
- unavailable;
- invalid.

### 11.5 Valid combination

```text
healthy source + low quota
```

is valid.

A low quota never means the source is disconnected.

---

## 12. Main panel

### 12.1 Role

The main panel is the detailed usage, source, and settings surface.

It displays only admitted providers.

### 12.2 Hierarchy

```text
UMA header
→ compact global controls
→ equal provider cards
→ independent details
→ independent Agent Settings
→ compact footer
```

### 12.3 Global controls

- Show All;
- Hide All;
- Search/Refresh as defined by the current UI;
- no global combined percentage.

### 12.4 Expansion

Expansion uses stable connector IDs.

Data updates do not collapse expanded cards.

Expansion does not trigger provider discovery or source reads.

### 12.5 Agent Settings

Each provider has independent Settings.

Settings may persist while the provider is hidden.

A future schema fails closed.

No Agent Settings page may contain an external API-key field.

### 12.6 Source transparency

Each provider Settings page must identify:

- source type;
- whether UMA performs a network request;
- whether login is required;
- credentials visible to UMA;
- data retained;
- update behavior;
- Disable or Disconnect action.

### 12.7 Stable order

Current intended priority:

```text
1 Codex
2 Claude Code
3 WorkBuddy
4 Google Antigravity CLI
5 Kiro
6 Kimi Code
7 Junie
8 next approved provider
```

Hidden providers reserve no visual space.

Do not reorder by value, freshness, failure, reset, process start, login time, or source class.

---

## 13. Desktop Assistant

### 13.1 Role

The Desktop Assistant is optional, presentation-only, floating, draggable, restorable, nonactivating during ordinary display, and driven by shared models.

### 13.2 Modes

Only:

```text
Regular
Minimalist
```

### 13.3 Forced Minimalist

```text
visible providers > 4
→ force Minimalist
```

The stored manual preference is preserved and restored when the forced condition ends.

### 13.4 Regular

Regular may show:

- provider mark;
- formal name;
- native value;
- optional plan/source detail;
- selected window for percentage providers;
- reset or update information.

### 13.5 Minimalist

Visible hierarchy:

```text
provider/source-state mark
→ compact native value
```

Tooltips and VoiceOver retain full semantics.

### 13.6 Zero-provider behavior

When no provider is admitted:

- do not show an empty Assistant shell;
- preserve enabled, position, Always-on-Top, and density settings.

### 13.7 Read independence

Showing or hiding the Assistant does not create or cancel source work, trigger provider reads, create a WebView, reset cadence, or change admission.

---

## 14. Visual system

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

## 15. Codex contract

### 15.1 Source split

Keep three data classes distinct:

```text
rate limits and account-level token totals
→ Codex app-server account methods

recent-task cumulative tokens
→ approved local Codex session logs

API-equivalent cost
→ local visible token logs + model pricing snapshots
```

### 15.2 Authentication

UMA reuses the existing Codex session through the local app-server.

UMA does not ask the user to enter an OpenAI API key.

### 15.3 Limits

Provider used percentage is converted to remaining percentage.

Expired windows cannot win selected-window logic.

### 15.4 Recent tasks and cost

Recent-task and Token Cost details remain inside Codex details.

Token Cost remains a local estimate, not an invoice.

### 15.5 Failure

On current Codex read failure:

- withdraw current admission;
- hide Codex from usage surfaces;
- preserve safe troubleshooting;
- allow later recovery.

---

## 16. WorkBuddy contract

### 16.1 Source classification

```text
Provider:
WorkBuddy

Source:
isolatedAccountWeb

Source ID:
workbuddy.accountWebCredits

Scope:
buddyAI.sharedCredits

Provenance:
Account web sync

Support:
Experimental
```

### 16.2 Authentication

The user signs in through an isolated UMA-owned official WorkBuddy web session.

UMA does not collect password, SMS code, QR content, cookies, or tokens.

WebKit session material remains opaque to app business logic.

### 16.3 Account observation

A complete observation includes subscription base, subscription bonus, add-on packages, and benefit/gift packages.

```text
subscriptionRemaining
+ addOnRemaining
+ benefitGiftRemaining
= calculatedTotalRemaining
```

### 16.4 Exact arithmetic and atomicity

Use exact Decimal.

One read returns either one complete valid current account observation or one rejected observation.

Do not combine current and stale sections.

### 16.5 Auto Refresh

WorkBuddy retains:

```text
Default:
ON

Cadence:
no sooner than 60 seconds after the previous read completes

OFF:
Manual only
```

One timer, one WebView, one in-flight read, no overlap, no catch-up burst, no rapid retry.

### 16.6 Failure and disconnect

On auth expiry or extraction failure:

- withdraw admission;
- hide WorkBuddy;
- no manual fallback;
- no stale visible fallback;
- show concise Settings state.

Disconnect clears only UMA-owned WorkBuddy website data and leaves external provider/browser sessions untouched.

---

## 17. Claude Code M5 target contract — not shipped

### 17.1 Product interpretation

The Founder phrase `offline API support` means:

```text
official local structured interface
```

It does not authorize an external Anthropic API key or direct Anthropic API client.

### 17.2 Preferred source

```text
Claude Code official statusLine
→ structured JSON on stdin
→ UMA relay allowlist
→ local Unix-domain socket
→ ClaudeCodeUsageConnector
```

Source class:

```text
officialLocalStatusLine
```

### 17.3 Official field contract

Initial allowlist:

```text
version
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
```

Each limit window may be independently absent.

`rate_limits` may be absent before the first provider response or for an unsupported account/authentication mode.

### 17.4 Forbidden Claude payload fields

The relay must discard and never persist:

- `session_id`;
- `session_name`;
- `prompt_id`;
- `transcript_path`;
- workspace paths;
- repository identity;
- branch/worktree paths;
- model input/output content;
- tool activity;
- account identity;
- raw status-line JSON.

The relay must never open the transcript path.

### 17.5 Authentication boundary

Supported M5 authentication:

```text
Claude Code provider-managed browser login
→ existing Claude.ai subscription session
```

UMA must not:

- request an Anthropic API key;
- read Claude credentials;
- inspect Claude Keychain values;
- use `claude setup-token`;
- set `CLAUDE_CODE_OAUTH_TOKEN`;
- set `ANTHROPIC_API_KEY`;
- add an `apiKeyHelper`;
- import Claude browser cookies.

If the active Claude Code authentication method is API-key based, M5 must not surface it as an accepted UMA source until a separate Founder decision changes the rule.

### 17.6 Official install and login

When Claude Code is absent:

- Settings may offer `Install / Open Claude Code` guidance;
- installation uses only the current official Claude Code installer after explicit Human authorization;
- the Human completes provider-controlled browser login;
- UMA receives no credential or login code;
- `Check Again` re-runs bounded eligibility.

### 17.7 Relay behavior

The relay must:

1. receive the status-line JSON through stdin;
2. parse only the allowlisted fields;
3. convert no values before validation;
4. send one sanitized bounded packet to an app-owned local socket;
5. persist no raw payload;
6. perform no network request;
7. preserve any pre-existing status-line output;
8. fail without blocking Claude Code;
9. use restrictive local permissions;
10. support deterministic install, repair, disable, and restore.

### 17.8 Existing status-line preservation

Before configuration change:

- inspect the active user-level status-line source;
- back up only the exact affected settings file with mode `0600`;
- do not log the original command;
- detect recursion;
- preserve original output and exit behavior;
- restore exact prior configuration on failure or uninstall.

If the existing command contains an obvious literal secret or cannot be preserved safely, stop and request Human resolution. Do not copy it into reports.

### 17.9 Update and freshness

Primary update:

```text
Claude Code provider event
→ status-line invocation
→ sanitized relay event
→ UMA publication
```

Status-line invocation itself must not be treated as provider usage or a model request.

No UMA synthetic Claude prompt is allowed for routine refresh.

A bounded optional status-line refresh interval may be used only after the source dossier confirms it creates no model request and preserves user configuration.

### 17.10 Admission and stale state

```text
official Claude CLI present
+ provider-managed subscription login usable
+ relay installed and healthy
+ current valid status-line payload
+ at least one valid quota window
= visible Claude Code
```

If the payload stops because Claude Code is inactive, the in-memory last value may remain visible as an explicit stale state for a bounded provider-specific interval.

After app relaunch, Claude remains hidden until a new valid event unless a separate normalized-snapshot persistence contract is approved.

Configuration failure, unsupported schema, or explicit logout withdraws admission.

### 17.11 Remaining conversion

```text
remainingPercent = 100 - used_percentage
```

Validate `0...100` before conversion.

Each window retains its own reset epoch.

Maximum Decrement chooses one shared display window.

### 17.12 Main-panel presentation

Collapsed:

- Claude Code;
- selected remaining percentage;
- selected window;
- source-state mark.

Expanded:

- five-hour remaining and reset when present;
- seven-day remaining and reset when present;
- last provider event;
- source: `Official local status line`;
- `Check Again` / repair action;
- Agent Settings.

Do not show session context, cost, transcript, account identity, or repository data in the first M5 version.

### 17.13 Settings

Unconfigured:

```text
Claude Code
Official local status line

Not configured

[ Check Claude Code ]
```

Installed but login required:

```text
Sign in through Claude Code

[ Open Claude Code ]
[ Check Again ]
```

Configured:

```text
Claude Code
Official local status line

Connected / Waiting for activity / Stale
Updated <relative time>

[ Repair Relay ]
[ Disable Integration ]
```

Source Transparency must state:

```text
Credentials accessed by UMA: None
Raw Claude payload stored: No
Transcript read: No
Network requests made by UMA: None
```

### 17.14 Account-web fallback

An isolated Claude account-web fallback is not part of the main M5 implementation.

It may be investigated only when:

- M5 local-source admission returns NO-GO or the current account supplies no usable quota windows;
- the Founder explicitly activates the conditional fallback dossier;
- the fallback obeys Section 5;
- no API key is used.

### 17.15 Source admission result

M5 source dossier returns:

```text
GO
CONDITIONAL GO
NO-GO
SETUP REQUIRED
```

`SETUP REQUIRED` means the official CLI or provider-managed login is absent, not that the source contract failed.

---

## 18. Manus and retired external API paths

### 18.1 Manus status

```text
M4:
closed

Manus:
unsupported / hidden

External API route:
retired
```

### 18.2 Re-entry conditions

A future Manus program requires a new Founder instruction and one of:

- official documented local CLI Credits output;
- official documented local IPC/service Credits output;
- isolated official account-web usage source that passes Logic 1.5 fallback admission.

### 18.3 Permanent prohibitions

Do not revive:

- Manus API-key Settings;
- `x-manus-api-key` requests;
- `usage.availableCredits` external API client;
- Manus Keychain credential storage;
- manual Manus Credits;
- inferred Manus deduction.

---

## 19. Refresh and synchronization

### 19.1 One application-wide refresh

One global Manual Refresh produces at most:

- one Codex refresh;
- one WorkBuddy current read;
- one health/current-state action per additional admitted provider;
- one serialized presentation update per provider result.

### 19.2 Provider-specific cadence

Each provider owns its accepted cadence.

The Assistant never multiplies cadence.

### 19.3 Coalescing

For each provider:

```text
one active read or event reduction
→ redundant scheduled trigger dropped
→ manual trigger may request at most one bounded follow-up
```

### 19.4 No rendering reads

Relative time, countdown, animation, expansion, language, density, and appearance changes cause no provider read.

### 19.5 Local event sources

A local event source does not receive synthetic provider activity from UMA.

Manual Refresh may perform only:

- relay health check;
- read of an existing sanitized local snapshot when admitted;
- source eligibility check;
- no model request.

---

## 20. Settings and persistence

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
- WorkBuddy Keep Signed In choice;
- account-web fallback Keep Signed In choices;
- selected admitted source ID;
- schema versions.

Do not persist in normal settings:

- credentials;
- API keys;
- OAuth tokens;
- raw cookies;
- account identity;
- raw provider payload;
- conversation/task content;
- source code;
- process IDs as durable authority;
- an Assistant usage cache.

For new Western-provider local sources, normalized usage snapshots are memory-only by default.

A disk snapshot requires a separate provider-specific privacy justification and explicit Founder acceptance.

Future preference schemas fail closed.

---

## 21. Privacy and diagnostics

### 21.1 Never collect without a separate accepted contract

- passwords;
- raw access or refresh tokens;
- external API keys;
- Authorization headers;
- cookies exported from WebKit;
- SMS or QR data;
- account email, name, or ID;
- billing information;
- payment methods;
- invoices or orders;
- conversation text;
- task content;
- source code;
- transcript files;
- private provider databases;
- process memory;
- browser state outside an admitted isolated source;
- full environment or argv dumps.

### 21.2 Safe process diagnostics

Do not use diagnostics that print full command lines or environments.

Use bounded fields:

```text
pid
ppid
elapsed time
state
approved executable basename/path
owned-child count
```

### 21.3 Evidence

- raw provider responses remain temporary;
- local status-line payloads remain memory-only;
- normalize and redact before reporting;
- screenshots remain unstaged;
- real balances and exact account values are not published in fixtures;
- config backups remain outside Git;
- packages contain no session, snapshot, credentials, cookies, or governing docs unless explicitly part of source distribution.

---

## 22. Performance and reliability

Required:

- one connector per admitted provider;
- no duplicate observers, relays, WebViews, or timers;
- one WorkBuddy WebView maximum;
- one Claude relay maximum after M5;
- zero overlapping provider reads;
- no Assistant source ownership;
- stable provider IDs;
- failure isolation;
- bounded persistence;
- no missed-cycle burst;
- no immediate failure retry;
- bounded CPU, RSS, thread, descriptor, socket, timer, and write behavior;
- clean termination;
- no orphan child or helper process.

Debug milestones verify claim-matched resource behavior.

---

## 23. Packaging

Every accepted package must prove:

- exact commit provenance;
- version/build;
- bundle identity;
- architecture;
- minimum macOS;
- signature;
- expected dependencies;
- fixture isolation;
- no tests, logs, or screenshots;
- no raw provider response;
- no provider website data;
- no imported cookies;
- no API key or token;
- no configuration backup;
- no real account balance fixture;
- no private transcript or session data.

A Claude relay helper may be packaged only when:

- its source is in the repository;
- its binary provenance matches the package commit;
- it has no network entitlement or broad file access;
- it contains no provider credentials or private paths;
- installation and restore behavior are tested.

The installed Desktop application remains protected until explicit replacement authority.

Public release, Developer ID signing, notarization, and GitHub Release remain separate Release Mode work.

---

## 24. Required test matrix

### 24.1 Shared architecture

- zero providers;
- Codex only;
- WorkBuddy only fixture;
- Codex + WorkBuddy;
- Codex + Claude + WorkBuddy after M5;
- independent failures;
- stable order;
- no hidden spacing;
- main/Assistant parity;
- no duplicate connector.

### 24.2 Percentage

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

### 24.3 Credits

- 0;
- 1;
- large value;
- exact Decimal WorkBuddy;
- absolute-only balance;
- complete fraction;
- invalid negative or overflow;
- compact truncation;
- no unit prepromotion;
- no universal absolute warning threshold.

### 24.4 Account-web fallback

- explicit consent;
- nonpersistent default;
- persistent opt-in;
- domain and route restrictions;
- no browser cookie import;
- provider-controlled login;
- login cancellation;
- auth expiry;
- current read success;
- malformed/incomplete page;
- account-write controls blocked;
- Disconnect and Clear;
- no identity or raw page retention;
- manual-only default cadence for new providers.

### 24.5 WorkBuddy

Retain the complete accepted pool aggregation, duplicate handling, expiry, Auto Refresh, coalescing, auth expiry, disconnect, privacy, Settings, and surface-parity matrix.

### 24.6 Claude Code M5

Capability and setup:

- CLI absent;
- CLI present;
- unsupported version;
- valid signature/path;
- not logged in;
- provider-managed login complete;
- API-key-based auth detected without reading the key;
- status line disabled by managed settings;
- no settings file;
- empty settings;
- existing status line;
- complex existing command;
- recursion detection;
- exact restore.

Payload:

- malformed JSON;
- no `rate_limits`;
- five-hour only;
- seven-day only;
- both windows;
- missing reset;
- negative/out-of-range used percentage;
- timestamp bounds;
- unknown fields;
- transcript path present and rejected;
- workspace/session fields rejected;
- raw payload not persisted.

Relay:

- one helper;
- Unix socket permissions;
- no network;
- no raw file;
- original status-line output preserved;
- relay failure does not block Claude;
- app unavailable;
- socket replacement;
- burst coalescing;
- no duplicate observer;
- install/repair/disable/restore.

Connector:

- waiting for first event;
- fresh;
- stale;
- unsupported;
- failed;
- logout/config removal;
- relaunch with no stale disk value;
- one provider failure does not affect others;
- Maximum Decrement parity.

### 24.7 UI and accessibility

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
- stable position/focus;
- source transparency copy.

---

## 25. Acceptance criteria

Logic 1.5 is correctly implemented for the current product when:

1. Codex and WorkBuddy remain the only current production providers until M5 passes;
2. external API-key input is absent from every provider path;
3. no manual value or deduction path admits a provider;
4. local structured sources are preferred;
5. account-web login is available only as a bounded fallback;
6. login occurs on provider-controlled official pages;
7. UMA never receives login credentials;
8. no browser session is imported;
9. nonpersistent login is the default for new fallback providers;
10. raw web and local payloads are not retained;
11. provider observations remain independent;
12. current-read admission remains fail-closed;
13. main panel and Assistant share one provider set;
14. provider-native units remain honest;
15. Maximum Decrement remains centralized;
16. WorkBuddy’s accepted Account Web Sync and Auto Refresh remain intact;
17. Manus remains hidden and has no API route;
18. package, privacy, resource, and Git boundaries remain;
19. unsupported providers remain hidden;
20. remote delivery remains separately authorized.

The Claude M5 contract passes only when:

21. the official Claude Code CLI is present and provider-managed login is usable;
22. the status-line source is documented and proven on the installed version;
23. at least one valid plan-limit window is observed;
24. no Anthropic API key or token enters UMA;
25. the relay persists no raw payload;
26. transcript, session, workspace, and identity fields are rejected;
27. existing status-line behavior is preserved and restorable;
28. source events reach UMA without a provider request initiated by UMA;
29. used percentages convert correctly to remaining values;
30. selected-window behavior is shared and reset-safe;
31. Claude appears independently beside Codex and WorkBuddy;
32. live, privacy, package, and resource evidence pass;
33. the Assistant receives Claude only through shared presentation;
34. one commit-exact accepted package exists;
35. installed-app replacement remains separately authorized.

---

## Appendix A — Locked current decisions

1. `main` remains the canonical remote branch.
2. UMA 0.11 is qualified and installed.
3. The M4-N local closeout commit is accepted historical and planning authority.
4. Codex and WorkBuddy are current production providers.
5. M4 is closed; Manus is hidden.
6. External API-key input is prohibited for every provider.
7. Manual balance entry and manual deduction are prohibited.
8. Official provider-controlled login is permitted.
9. Local structured sources always receive first priority.
10. Account-web login is fallback, not the default source when local data exists.
11. WorkBuddy remains the proven login-source implementation.
12. Newly added login sources default to nonpersistent session and Manual-only refresh.
13. No provider credentials enter UMA business logic.
14. No private provider data is retained beyond an explicitly admitted normalized snapshot.
15. Claude Code is the M5 next provider.
16. Claude Code M5 uses official local status-line JSON, not an external API.
17. Claude authentication is provider-managed; no API key or setup token is used.
18. Claude raw payload, transcript, session, and workspace data are rejected.
19. The Assistant remains presentation-only.
20. Visible-provider count controls forced Minimalist.
21. Push, release, notarization, deployment, and publication remain separate.

---

## Appendix B — Current provider status

| Priority | Provider | Preferred source | Fallback source | Current status | Primary value |
|---:|---|---|---|---|---|
| 1 | Codex | Local app-server | None | Live-qualified | Remaining percentage |
| 2 | Claude Code | Official local status line | Conditional isolated account web | M5 NEXT | Remaining percentage |
| 3 | WorkBuddy | No accepted local balance source | Isolated account web | Live-qualified / Experimental | Exact Credits |
| 4 | Google Antigravity CLI | Official local status line | Conditional account web | Strong future candidate | Remaining fraction/percentage |
| 5 | Kiro | Official local CLI/ACP dossier required | Conditional account web | Conditional | Unknown |
| 6 | Kimi Code | Official local CLI/server dossier required | Conditional account web | Conditional | Unknown |
| 7 | Junie | Official local CLI/ACP dossier required | Conditional account web | Conditional | Unknown |
| 8 | Cursor/Windsurf/Manus/other | No admitted local source | Provider-specific account web dossier | Deferred | Unknown |

---

## Appendix C — Superseded Logic 1.4 rules

Superseded:

```text
Manus is the next provider.
External provider API keys may be entered through UMA.
Official remote usage API is a production source class.
Manus API key may be stored in Keychain.
Manus usage.availableCredits is an active target.
Account-web login is WorkBuddy-only.
```

Replacements:

```text
Claude Code local structured support is next.
External API-key input is prohibited.
There is no external API-key source class.
Manus API route is retired.
Provider-controlled account login is an admitted fallback source class.
Local source remains preferred for every provider.
```

---

## Appendix D — Governing references

Current source set after installation:

```text
UMA_Logic_1.5.md
Scroll_2.1.md
M5_Plan.md
M5_Goal.md
UMA_0.11_closeout.md
Goal_Mode_2.0.md
accepted M4-N closeout records
```

Historical references:

```text
UMA Logic 1.4
Scroll 2.0
M4 Plan / Goals
M3 Plan / Goals
UMA Logic 1.3.1
M2W Plan / Goals
DEV 3 shift report
Monitor Mechanism historical reference
```

Official Claude Code references retrieved 2026-07-28:

```text
https://code.claude.com/docs/en/statusline
https://code.claude.com/docs/en/authentication
https://code.claude.com/docs/en/installation
https://code.claude.com/docs/en/settings
https://code.claude.com/docs/en/commands
```

Current official documentation and live installed behavior outrank this static snapshot.
