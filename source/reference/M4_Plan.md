# Usage Monitor Altoget — M4 Plan

**Program:** M4 — Manus Official API v2 Credits Integration  
**Version:** 2.0  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Canonical starting branch:** `main`  
**Known current main:** `469be4d6cf411a89401c2341807a57aef176d852`  
**Qualified UMA 0.11 source:** `459ea1321817e391ba80fe79f19edb0352fc76cb`  
**Current installed review build:** `/Users/juliushe/Desktop/UMA_0.11.app`  
**Current production providers:** Codex and WorkBuddy  
**Execution standard:** Goal Mode 2.0  
**Default authority:** `LOCAL_FULL_THROTTLE`  
**Remote push/release:** Not authorized  
**Status:** Active M4 planning authority; replaces the earlier M4 pre-release/readiness proposal  
**Founder direction:** Proceed to Manus integration after installing the current governing source set

---

## 0. Plan authority

This plan consumes:

- merged Founder `main`;
- the DEV 3 shift report;
- UMA 0.11 final qualification;
- Scroll 2.0;
- UMA Logic 1.4;
- UMA 0.11 Closeout;
- Provider Status Matrix;
- Goal Mode 2.0;
- current official Manus API v2 documentation.

Current accepted lineage:

```text
Qualified development commit:
459ea1321817e391ba80fe79f19edb0352fc76cb

Main-history integration commit:
ff6553943280836fb0d3db5289f85b163c41c1a3

Merged main:
469be4d6cf411a89401c2341807a57aef176d852
```

The earlier M4 proposal centered on governing-source reconciliation, CI, field testing, and distribution readiness. Those remain valid later work, but the Founder has now selected Manus integration as the next milestone.

The source-reference reconciliation is therefore performed in `M4-B0`, then the milestone proceeds to Manus.

---

## 1. Why Manus is the next milestone

UMA 0.11 has already closed:

- multi-Agent architecture;
- Codex live monitoring;
- WorkBuddy exact Credit monitoring;
- Desktop Assistant parity;
- Agent Settings;
- source admission;
- provider failure isolation;
- final qualification;
- Desktop installation;
- Founder main merge.

The next product value is another real provider.

Claude Code remains deferred because the official CLI/source was not available on the current Mac.

Current official Manus documentation now exposes an explicit usage endpoint with an authoritative spendable Credit balance.

This makes Manus a stronger next source candidate than an inferred desktop-app source.

---

## 2. Current official Manus source findings

### 2.1 API v2 exists

Current official documentation describes Manus API v2 as the current programmatic interface.

Base host:

```text
https://api.manus.ai
```

### 2.2 Balance endpoint

Preferred endpoint:

```text
GET /v2/usage.availableCredits
```

Required header:

```text
x-manus-api-key: <secret>
```

The endpoint is documented as API-key-only.

### 2.3 Primary value

Documented primary field:

```text
total_credits
```

It is described as the authoritative spendable balance.

UMA must use this field as the primary Manus value.

UMA must not calculate a competing primary total from component fields.

### 2.4 Component fields

Current documented fields:

```text
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

Interpretation:

- `free_credits`, `periodic_credits`, `addon_credits`, `event_credits`, and `refresh_credits` are balance components;
- `pro_monthly_credits` is an issuance quota;
- `max_refresh_credits` is a refresh-grant amount;
- quota/grant values are not current balance and are not a remaining-percentage denominator;
- `next_refresh_time` is a Unix timestamp in seconds;
- `refresh_interval` is currently documented as daily, weekly, or empty.

### 2.5 Account scope

The endpoint is documented to return:

- personal balance for a personal account key;
- team shared-pool balance for a team sub-account key.

The initial response contract does not guarantee an explicit account-type field.

UMA should therefore present the general scope:

```text
Manus Credits
```

and explain in details:

```text
This balance belongs to the Manus account represented by the configured API key.
A team sub-account key may represent a shared team pool.
```

Do not infer account type from optional refresh fields without an accepted contract.

### 2.6 API-key risk

The official authentication documentation warns that API keys provide broad account access.

Therefore:

- the key is a high-sensitivity secret;
- the user creates it outside UMA through the official Manus interface;
- the user enters it directly into UMA;
- UMA stores it only in macOS Keychain;
- Codex never reads it;
- no command, log, report, fixture, or artifact contains it.

### 2.7 Excluded endpoints

The first integration does not use:

```text
usage.list
usage.teamStatistic
usage.teamLog
task.*
project.*
file.*
webhook.*
connector.*
browser.*
```

`usage.list` is not required for current balance and may expose task titles or collaborator information.

M4 is a narrow Credits monitor, not a Manus task-history or task-control integration.

---

## 3. M4 result target

At M4 closeout, the accepted package must provide:

1. current Codex monitoring;
2. current WorkBuddy monitoring;
3. current Manus Credits from the official API v2 source;
4. secure Keychain-backed Manus API-key configuration;
5. exact integer Manus Credits;
6. optional safe breakdown and next-refresh details;
7. one Manus connector in the main app;
8. one shared Manus presentation in the Desktop Assistant;
9. stable provider order;
10. independent failure/recovery;
11. no task creation or Credit-consuming validation;
12. no raw key exposure;
13. no task-history access;
14. commit-exact package/privacy/resource evidence;
15. no replacement of the installed Desktop app without separate authority.

The product may have three visible providers:

```text
Codex
WorkBuddy
Manus
```

Claude remains a hidden reserved registry slot.

---

## 4. This milestone is not

M4 does not include:

- Manus task creation;
- Manus message sending;
- Manus task-history display;
- Manus browser automation;
- Manus desktop-app scraping;
- web DOM scraping;
- cookie import;
- OAuth/Open App implementation;
- account identity display;
- team admin analytics;
- API-key generation by UMA;
- plan purchase or upgrade;
- public release;
- notarization;
- App Store;
- co-builder PR resolution;
- Claude Code reassessment;
- Cursor/Kimi+/Doubao work;
- broad visual redesign.

---

## 5. Architecture

### 5.1 Required path

```text
Manus Settings
→ ManusAPIKeyStore (Keychain)
→ ManusCreditsAPIClient
→ ManusUsageConnector
→ AgentConnectorRegistry
→ UsageStore
→ SharedUsagePresentationPolicy
→ AgentCardViewModel
├── main panel
└── Desktop Assistant
```

### 5.2 Keychain ownership

The app owns one Keychain item for the configured Manus key.

Conceptual service:

```text
com.kevinchen.CodexUsageMonitor.manus.api-key
```

The exact service/account identifiers may differ, but they must:

- be stable;
- avoid plaintext duplication;
- support save/replace/delete;
- never appear in public logs;
- remain outside normal app preferences.

### 5.3 API client

One narrow client:

```text
exact host
+ exact path
+ GET
+ x-manus-api-key
+ strict response decoder
```

No generic Manus SDK or task API is required for the first integration.

### 5.4 Connector

The connector owns:

- credential-configured state;
- current read;
- freshness;
- current strict snapshot;
- refresh coalescing;
- failure mapping;
- disconnect cleanup;
- safe presentation publication.

UsageStore does not branch on Manus-specific field names.

### 5.5 Shared presentation

Manus maps into the existing Credit value model.

The Assistant consumes the same `AgentCardViewModel`.

---

## 6. Source-admission contract

### 6.1 Admission decision

M4-G1 returns:

```text
GO
CONDITIONAL GO
NO-GO
```

GO requires:

- current official endpoint;
- clear balance semantics;
- secure key storage;
- privacy-safe field allowlist;
- bounded read behavior;
- feasible package support;
- no task creation;
- live validation path.

CONDITIONAL GO may be used when:

- official source and implementation are feasible;
- live Founder key entry is deferred to M4-G3;
- optional fields remain account-dependent.

NO-GO when:

- current balance requires unsupported scraping;
- key cannot be protected;
- endpoint semantics are ambiguous;
- a read requires task creation or account mutation;
- source use would expose credentials to DEV.

### 6.2 Documentation versus live proof

Official documentation can support source architecture.

It cannot alone prove:

- the Founder account can create a key;
- the current account returns the expected response;
- the displayed balance matches the official UI;
- key persistence works in the packaged app.

Those require later bounded live acceptance.

---

## 7. Data contract

### 7.1 Strict top-level response

Expected conceptual response:

```json
{
  "ok": true,
  "request_id": "safe-id",
  "data": {
    "total_credits": 123,
    "free_credits": 123,
    "periodic_credits": 123,
    "addon_credits": 123,
    "pro_monthly_credits": 123,
    "event_credits": 123,
    "refresh_credits": 123,
    "max_refresh_credits": 123,
    "next_refresh_time": 123,
    "refresh_interval": "daily"
  }
}
```

The app does not need to retain `request_id` as durable state.

### 7.2 Primary snapshot

Conceptual model:

```swift
struct ManusCreditsSnapshot {
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
}
```

### 7.3 Validation

Required:

- `total_credits >= 0`;
- all present Credit fields nonnegative;
- values fit the product’s supported exact range;
- timestamp is plausible;
- no millisecond/second confusion;
- unsupported interval fails safely;
- missing optional fields remain unavailable;
- missing `total_credits` rejects the observation;
- `ok=false` maps to safe error;
- oversized response is rejected;
- non-JSON response is rejected.

### 7.4 No component reconstruction

Do not require component fields to sum to `total_credits`.

Official documentation states component fields may not always sum directly due to membership and pool rules.

`total_credits` remains authoritative.

### 7.5 No fake percentage

Do not derive:

```text
remainingPercent = total_credits / pro_monthly_credits
```

or:

```text
remainingPercent = refresh_credits / max_refresh_credits
```

These are incomplete and scope-mismatched.

---

## 8. Secret and authentication design

### 8.1 User workflow

```text
Settings
→ Manus
→ Connect Manus
→ explain official API key requirement
→ user creates key in official Manus settings
→ user pastes key into SecureField
→ Save and Verify
→ Keychain save
→ one bounded read
→ connected state
```

### 8.2 Human-only secret handling

The user must never paste the key into:

- Codex;
- ChatGPT;
- Terminal history;
- issue;
- PR;
- report;
- screenshot.

The candidate app is the only intended entry surface.

### 8.3 Keychain behavior

Required:

- add;
- update;
- retrieve internally for request use;
- delete;
- inaccessible to normal settings serialization;
- no accidental sync unless explicitly selected and reviewed;
- safe failure message;
- no key fragment in errors.

### 8.4 Disconnect

Disconnect:

- cancels scheduled reads;
- deletes the Keychain item;
- clears current Manus snapshot;
- withdraws Manus admission;
- preserves nonsecret UI preferences if appropriate;
- leaves the official Manus account and other apps untouched.

### 8.5 Authentication failure

HTTP authentication failure:

- withdraw admission;
- suspend scheduled reads;
- show `API key needs attention`;
- do not retry every minute;
- require user action.

---

## 9. Refresh and lifecycle

### 9.1 Triggers

Allowed:

1. app launch when key configured;
2. application-wide Manual Refresh;
3. Manus Sync Now;
4. Save and Verify;
5. optional Auto Refresh.

### 9.2 Initial cadence

Target:

```text
no sooner than 60 seconds after prior Manus read completion
```

M4-G1 may choose a slower cadence if official guidance or product efficiency supports it.

### 9.3 Coalescing

All Manus triggers share one in-flight gate.

```text
one active read
→ scheduled duplicate dropped
→ manual request may queue at most one follow-up
```

### 9.4 Failure retry

Do not use immediate retry.

For transient non-auth failure:

- hide current Manus admission;
- show safe error;
- next ordinary scheduled cycle may make one new attempt if still enabled.

For auth failure:

- suspend cadence until user action.

### 9.5 Sleep/resume

No catch-up burst.

After resume, schedule at most one normal read.

### 9.6 Termination

Cancel task-owned timer/request state.

No secret or raw response is written during termination.

---

## 10. Main-panel UX

### 10.1 Unconfigured

```text
Manus is not connected.
Add an official Manus API key to monitor Credits.
```

No provider card appears in the usage surface. The setup state belongs in Settings.

### 10.2 Connected collapsed card

Example:

```text
Manus
8,420 Credits
Official API v2
Updated 1m ago
```

Do not show a fake percent.

### 10.3 Expanded details

May show:

- Total available Credits;
- Free Credits;
- Periodic Credits;
- Add-on Credits;
- Event Credits;
- Refresh Credits;
- next refresh;
- refresh cadence;
- source;
- updated time;
- Sync Now;
- Agent Settings.

Do not show:

- API key;
- account email/name;
- task titles;
- task history;
- collaborator details.

### 10.4 Exhausted

Use:

```text
Manus Credits exhausted
```

Do not say the entire Manus product is unavailable solely because the balance is zero.

### 10.5 Failure

The usage card is withdrawn when the current read fails.

Settings show the safe reason.

---

## 11. Desktop Assistant UX

### 11.1 Regular

Show:

- Manus mark;
- formal name;
- exact integer Credits;
- optional source/update detail.

### 11.2 Minimalist

Show:

```text
source-state mark
+ compact Credits
```

Examples:

```text
842
8.4k
105k
0
—
```

Use truncation, not rounding.

No `%`.

### 11.3 Tint

Without a complete valid same-scope total denominator:

- use neutral/source-appropriate glass;
- no proportional fill;
- no absolute low-Credits threshold.

Exhausted may use the accepted exhausted treatment.

### 11.4 Accessibility

VoiceOver example:

```text
Manus, 8,420 Credits available, Official API v2, updated one minute ago.
```

No key information.

### 11.5 Ownership

Assistant code may not import or own:

- Keychain client;
- URLSession Manus client;
- API key state;
- Manus timer;
- Manus response decoder;
- private snapshot cache.

---

## 12. Settings UX

### 12.1 Disconnected

Primary:

```text
Manus
Official API v2

Not connected

[ Connect Manus ]
```

### 12.2 First connection disclosure

Required meaning:

```text
UMA reads only the current Manus Credit balance through the official Manus API.
Your API key is stored in macOS Keychain and is not shown again.
UMA does not create Manus tasks or read task history.
```

### 12.3 Key entry

- SecureField;
- Paste supported;
- Save and Verify;
- Cancel;
- no reveal toggle by default;
- no key strength/format guess beyond safe nonempty/bounded validation;
- no key in accessibility value after save.

### 12.4 Connected

```text
Manus
Official API v2

Connected
Updated <relative time>

Auto Refresh [On/Off]
[ Sync Now ] [ Disconnect ]
```

### 12.5 Safe errors

```text
API key not accepted
Current Credits could not be read
Unsupported Manus response
Network unavailable
```

Do not show raw HTTP body or headers.

---

## 13. Privacy and security

### 13.1 Allowed data

Allowlist:

- current Credit fields;
- next refresh metadata;
- safe source state;
- observation timestamp;
- configured boolean;
- Auto Refresh preference;
- safe error category.

### 13.2 Forbidden data

- raw API key outside Keychain;
- Authorization/header dumps;
- account identity;
- task titles;
- collaborator names;
- task content;
- messages;
- file metadata;
- project data;
- browser sessions;
- cookies;
- billing/order/payment information;
- raw provider payload in Git;
- raw provider payload in package.

### 13.3 Network boundary

- exact host;
- standard TLS;
- no insecure transport;
- no broad redirects;
- no proxy logging added by UMA;
- no analytics;
- no UMA backend.

### 13.4 Logs

Logs may include:

```text
Manus read started
Manus read succeeded
Manus authentication failed
Manus schema invalid
```

Logs must not include:

- headers;
- key;
- full body;
- account value in public evidence unless explicitly sanitized;
- task or collaborator data.

---

## 14. Testing strategy

### 14.1 M4-G1

- official documentation inventory;
- endpoint/field table;
- auth and Keychain design;
- source admission verdict;
- no live key.

### 14.2 M4-G2 offline implementation

- URL request contract;
- decoder;
- Keychain abstraction;
- Settings workflow;
- connector state;
- fixtures;
- no live key;
- full affected tests/builds.

### 14.3 M4-G3 live main-panel acceptance

- user-controlled key entry;
- one successful read;
- official UI parity;
- invalid-key state;
- relaunch;
- Manual Refresh;
- bounded cadence;
- no secret leakage;
- package proof.

### 14.4 M4DBG

- repeated reads;
- network failure;
- auth failure;
- malformed/partial data;
- concurrent global refresh;
- WorkBuddy timer plus Manus timer;
- Codex recovery;
- relaunch;
- resource run;
- stable order.

### 14.5 M4A

- shared presentation only;
- Regular/Minimalist;
- exact/compact formatting;
- accessibility;
- no source ownership.

### 14.6 M4ADBG

- main/Assistant parity;
- all visibility combinations;
- no cadence multiplication;
- Keychain/package privacy;
- resource ownership;
- final commit-exact package.

---

## 15. Goal sequence and model routing

| Goal | Model | Class | Result |
|---|---|---|---|
| M4-B0 | GPT-5.6 Sol / Medium | Standard Task | merged-main worktree and governing-source installation |
| M4-G1 | GPT-5.6 Terra / Extra High | Full Goal | Manus API source, credential, and admission dossier |
| M4-G2 | GPT-5.6 Terra / Extra High | Full Goal | secure Keychain + API client + connector + Settings |
| M4-G3 | GPT-5.6 Terra / High | Full Goal | live main-panel and package acceptance |
| M4DBG-G1 | GPT-5.6 Terra / High | Full Goal | three-provider main-app debugging |
| M4A-G1 | GPT-5.6 Sol / High | Standard Task | Manus shared presentation in Desktop Assistant |
| M4ADBG-G1 | GPT-5.6 Terra / Extra High | Full Goal | combined closeout |
| M4-CLOSE-G1 | GPT-5.6 Sol / Medium | Standard Task | update governing source and close M4 |

Each task ends under Completion Lock.

---

## 16. Git and worktree policy

Expected new branch:

```text
codex/uma-m4-manus
```

Expected durable worktree:

```text
/Users/juliushe/Developer/UMA-M4-Manus
```

M4-B0 must discover the actual canonical local clone and use current `origin/main`.

Hard rules:

```text
Do not use git add .
Do not use git add -A.
Do not use git add -u.
Do not reset --hard.
Do not clean for convenience.
Do not discard unrelated WIP.
Do not amend accepted commits.
Do not force-push.
```

Local commits are allowed only when the exact Goal authorizes exact-file/hunk staging.

Remote push, merge, tag, release, and notarization remain forbidden.

---

## 17. Package and installation policy

Development packages use task-owned paths under `/private/tmp`.

Do not replace:

```text
/Users/juliushe/Desktop/UMA_0.11.app
```

without a separate current Founder instruction.

M4 package must exclude:

- API key;
- Keychain export;
- raw API response;
- real balance fixture;
- logs;
- screenshots;
- source-reference pack;
- tests;
- task history.

---

## 18. Risk register

| ID | Risk | Handling |
|---|---|---|
| M4-R01 | API key has broad account access | Keychain-only; user enters in app; no DEV access |
| M4-R02 | `usage.availableCredits` changes | Versioned strict decoder; fail closed |
| M4-R03 | Component fields do not sum | `total_credits` authoritative |
| M4-R04 | Personal/team scope ambiguous | General `Manus Credits` label; no unsupported assertion |
| M4-R05 | Key invalid/expired | Withdraw admission; suspend timer; user action |
| M4-R06 | Network/API outage | No stale current display; bounded retry |
| M4-R07 | Secret leaks through logs/errors | Redaction tests and package/privacy audit |
| M4-R08 | Remote timer multiplies with Assistant | Source layer owns one timer; Assistant presentation-only |
| M4-R09 | M4 expands into task automation | Explicit endpoint allowlist and prohibited routes |
| M4-R10 | Current main advances | Inspect and record; do not hard-reset to stale hash |

---

## 19. M4 PASS criteria

M4 closes only when:

1. M4 starts from current merged `main`;
2. governing source is installed;
3. official API v2 source is admitted;
4. secure Keychain storage works;
5. Codex/DEV never reads the key;
6. the API client calls only the accepted initial endpoint;
7. `total_credits` is authoritative;
8. optional fields remain optional;
9. no fake percentage exists;
10. no task is created;
11. no task history is read;
12. Manus appears only after a current successful read;
13. main panel shows exact Credits;
14. Assistant shows the same shared value;
15. failure/recovery is independent;
16. one timer/client/in-flight request maximum;
17. Codex and WorkBuddy do not regress;
18. Light/Dark/accessibility/localization pass;
19. package contains no secret or raw account data;
20. resource and lifecycle checks pass;
21. local commits and commit-exact package exist;
22. installed Desktop app remains protected;
23. no remote action occurs;
24. M4 closeout documents the result;
25. no next provider starts automatically.

---

## 20. Immediate next action

```text
Run M4-B0
→ create the merged-main Manus worktree
→ install source/reference files
→ install the official Manus API skill for Codex
→ stop

Then run M4-G1
→ source admission and secret-boundary dossier
→ no API key in Codex
→ no connector implementation before admission
```

---

## Appendix A — Official Manus references

Retrieved 2026-07-28:

```text
https://open.manus.im/docs/v2/introduction
https://open.manus.im/docs/v2/authentication
https://open.manus.im/docs/v2/usage.availableCredits
https://open.manus.im/docs/v2/usage.list
https://open.manus.im/docs/v2/rate-limits
https://open.manus.im/docs/v2/manus-api-skill
https://manus.im/help/credits
https://help.manus.im/en/articles/12520235-where-can-i-check-my-credit-consumption-usage
https://help.manus.im/en/articles/14134826-understanding-credit-consumption-in-the-manus-desktop-app
```

Current official documentation outranks this snapshot.

---

## Appendix B — Official Codex skill installation command

The current official Manus API documentation publishes:

```bash
npx skills add https://open.manus.ai/docs --skill manus-api --agent codex --global --yes
```

This installs documentation guidance only.

It does not install, request, or contain a Manus API key.
