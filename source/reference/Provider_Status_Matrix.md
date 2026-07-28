# UMA Provider Status Matrix

**Version:** 2.0  
**Date:** 2026-07-28  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Canonical main:** `469be4d6cf411a89401c2341807a57aef176d852`  
**Current production providers:** Codex and WorkBuddy  
**Next provider:** Manus  
**Status:** Current provider/source decision reference; replaces provider tables in Scroll 1.2 and Logic 1.3.1

---

## 0. Status definitions

| Status | Meaning |
|---|---|
| `Live-qualified` | Real source, current read, UI, recovery, package, and privacy evidence accepted |
| `Implemented / not live-qualified` | Runtime exists but required live acceptance is incomplete |
| `Conditional source candidate` | Official source is documented; local/account admission remains unproven |
| `Researched / deferred` | Investigation completed; no current acceptable source or required runtime |
| `Not started` | No accepted source dossier or implementation |
| `Hidden` | Provider must not appear in usage surfaces |
| `Visible after current read` | Provider appears only after a valid current admitted observation |

---

## 1. Master provider matrix

| Priority | Provider | Stable role | Native unit | Source class | Current source | Authentication/configuration | Refresh/update model | Current implementation | Surface status | Next action |
|---:|---|---|---|---|---|---|---|---|---|---|
| 1 | Codex | Primary local structured provider | Remaining percentage; token/cost details | `localStructured` | `codex app-server --stdio`; approved local Codex session logs for recent tasks/cost | Reuses existing Codex session; no separate API key | Launch/manual/current connector cadence; one owned child maximum | `Live-qualified` | Visible after current successful read | Preserve through M4 regressions |
| 2 | Claude Code | Reserved second registry slot | Unknown until source is admitted | None admitted | Official statusLine class researched, but official CLI/source absent on current Mac | Not configured | None | `Researched / deferred` | Hidden | Reassess only after official CLI/source exists |
| 3 | WorkBuddy | Buddy AI shared Credit provider | Exact Credits | `authenticatedAccountWeb` | Isolated UMA-owned official WorkBuddy Plan and Usage page | Provider-controlled login inside isolated WKWebView | Auto Refresh ON by default; no sooner than 60 seconds after prior read completion; Manual-only option | `Live-qualified` | Visible after complete current all-pool read | Preserve; Quick Patch only on reproduced page drift |
| 4 | Manus | Next official API provider | Exact Credits | `officialRemoteUsageAPI` candidate | Official API v2 `usage.availableCredits` | API key required; planned macOS Keychain storage | Planned launch/manual/provider sync; optional no-faster-than-60-second cadence | `Conditional source candidate` | Hidden | Execute M4 source admission, secure connector, live acceptance |
| 5 | Cursor | Later coding-agent provider | Unknown | None admitted | None | Unknown | None | `Not started` | Hidden | Source dossier after M4 closeout |
| 6 | Kimi+ | Later Chinese-provider slot | Unknown | None admitted | None | Unknown | None | `Not started` | Hidden | Source dossier after earlier provider program |
| 7 | Doubao | Later Chinese-provider slot | Unknown | None admitted | None | Unknown | None | `Not started` | Hidden | Source dossier after provider list freeze |
| 8 | Approved emerging slot | Frozen at future M7 start | Unknown | None admitted | None | Unknown | None | `Not started` | Hidden | Founder freezes exact provider before work |

---

## 2. Current live-provider details

### 2.1 Codex

| Field | Current contract |
|---|---|
| Formal name | Codex |
| Source | Local Codex app-server |
| Authentication | Existing Codex signed-in session |
| Primary compact value | Remaining percentage |
| Supported windows | Provider-supplied finite windows; five-hour and seven-day where available |
| Selection | Centralized Maximum Decrement |
| Reset/refill behavior | Increases do not win; expired epochs do not win |
| Additional details | Recent tasks, account token totals, local API-equivalent cost estimate |
| Cost meaning | Estimate only; not account bill |
| Failure | Current read failure withdraws admission |
| Local secret handling | No plaintext API key collected by UMA |
| Surface status | Main panel + Desktop Assistant |
| Current verdict | Live-qualified |

### 2.2 WorkBuddy

| Field | Current contract |
|---|---|
| Formal name | WorkBuddy |
| Credit scope | Buddy AI shared Credits; shared with CodeBuddy |
| Source | Account Web Sync |
| Source status | Experimental |
| Runtime requirement | WorkBuddy.app not required |
| Authentication | Provider-owned web login inside isolated UMA WKWebView |
| Primary compact value | Exact available Credits |
| Account total | Subscription + add-on + benefit/gift pools |
| Arithmetic | Exact Decimal |
| Observation | Atomic; partial observations rejected |
| Auto Refresh | ON by default; every minute, no overlap |
| Manual mode | Supported |
| Failure | Auth/extraction failure withdraws admission; no manual/stale visible fallback |
| Surface status | Main panel + Desktop Assistant |
| Current verdict | Live-qualified |

---

## 3. Deferred provider

### Claude Code

| Question | Current answer |
|---|---|
| Was source research completed? | Yes |
| Was the official Claude Code CLI found on the current Mac? | No |
| Was Claude Desktop accepted as a usage source? | No |
| Was a production connector implemented? | No |
| Is Claude shown in the UI? | No |
| Does Claude block Manus? | No |
| Reentry condition | Official CLI or another admitted structured source exists |
| Required next step if reopened | Fresh capability/source dossier |

Claude’s priority slot remains reserved so stable provider ordering does not need to change later.

---

## 4. Manus source-admission matrix

### 4.1 Official source candidate

| Item | Current research result | M4 handling |
|---|---|---|
| API version | v2 current documentation | Verify at M4 start |
| Balance endpoint | `GET /v2/usage.availableCredits` | Preferred initial source |
| API host | `https://api.manus.ai` | Exact-host allowlist |
| Authentication | `x-manus-api-key` | Keychain-only secret |
| OAuth support for balance endpoint | Not documented; endpoint states API Key only | Do not design OAuth fallback in M4 |
| Primary balance | `total_credits` | Treat as authoritative spendable balance |
| Free component | `free_credits` | Optional detail |
| Periodic component | `periodic_credits` | Optional current-balance detail |
| Add-on component | `addon_credits` | Optional current-balance detail |
| Event component | `event_credits` | Optional current-balance detail |
| Refresh component | `refresh_credits` | Optional current-balance detail |
| Monthly quota | `pro_monthly_credits` | Issuance quota; not current balance |
| Per-refresh grant | `max_refresh_credits` | Grant amount; not current balance |
| Next refresh | `next_refresh_time` | Optional reset detail |
| Refresh cadence | `refresh_interval` | `daily`, `weekly`, or empty under current docs |
| Personal/team scope | Personal balance or team shared pool based on key caller | Use conservative generic scope unless explicit trusted field exists |
| Data type | Current docs describe integer Credit fields | Preserve exact integer authority |
| API key sensitivity | Broad account access | High-sensitivity secret; never expose to DEV/logs |
| Live proof | Not yet completed in UMA | Human-controlled M4 gate |
| Current admission | `CONDITIONAL` | GO only after secure local read |

### 4.2 Field mapping

| API field | Product meaning | Main value? | Percentage denominator? | Display rule |
|---|---|---:|---:|---|
| `total_credits` | Current spendable balance | Yes | No | Full Credits; compact k/M/B in Minimalist |
| `free_credits` | Free/system-granted component | No | No | Expanded detail only |
| `periodic_credits` | Remaining periodic subscription component | No | No | Expanded detail only |
| `addon_credits` | Remaining purchased add-on component | No | No | Expanded detail only |
| `event_credits` | Remaining active-event component | No | No | Expanded detail only |
| `refresh_credits` | Remaining auto-refresh component | No | No | Expanded detail only |
| `pro_monthly_credits` | Monthly issuance quota | No | Never | Optional plan detail |
| `max_refresh_credits` | Amount granted by next refresh | No | Never | Optional refresh detail |
| `next_refresh_time` | Next refresh timestamp | No | N/A | Detail/tooltip when valid |
| `refresh_interval` | Refresh cadence | No | N/A | Detail/tooltip when known |

### 4.3 Excluded initial Manus API surfaces

| API surface | M4 first-version decision | Reason |
|---|---|---|
| `usage.list` | Excluded | Not required for current balance; may return task titles and collaborator information |
| `usage.teamStatistic` | Excluded | Team analytics beyond minimum monitor scope |
| `usage.teamLog` | Excluded | Team activity detail beyond minimum monitor scope |
| `task.*` | Prohibited | UMA monitors usage; must not create/control tasks |
| `project.*` | Prohibited | Unrelated |
| `file.*` | Prohibited | Unrelated |
| `webhook.*` | Prohibited | No need for initial balance monitor |
| `connector.*` | Prohibited | Unrelated to balance |
| Browser APIs | Prohibited | No scraping or browser automation |

---

## 5. Authentication and secret matrix

| Provider | Secret/session source | Where it lives | May Codex read it? | May normal preferences store it? | Disconnect behavior |
|---|---|---|---:|---:|---|
| Codex | Existing local Codex session | Codex-managed state | No | No | Existing Codex flow |
| WorkBuddy | Isolated WebKit session | UMA-owned WebKit website data | No | Only safe consent/settings | Clear UMA-owned WorkBuddy website data |
| Manus | API key | macOS Keychain | No | No; only configured boolean/settings | Delete Keychain item and current snapshot |
| Future provider | Source-specific | Must be admitted first | Default no | Default no | Defined by source dossier |

### Manus key rules

- User creates the key through official Manus settings.
- User pastes it directly into UMA.
- The app stores it only in Keychain.
- No plaintext backup.
- No command-line argument.
- No environment variable used by automated reports.
- No log or diagnostic echo.
- No reveal-after-save by default.
- No screenshot containing the key.
- No raw key in tests.
- No key in package.
- No key in Codex or ChatGPT.

---

## 6. Value and UI matrix

| Provider | Main compact value | Expanded value | Regular Assistant | Minimalist Assistant | Low-state rule |
|---|---|---|---|---|---|
| Codex | Remaining % | All valid windows, reset, details | Remaining % | Remaining % | Central % thresholds |
| WorkBuddy | Exact Credits | Pool categories and updated time | Exact Credits | Truncated k/M/B Credits | Fraction only when complete same-scope total valid; otherwise no absolute threshold |
| Manus | Planned exact integer Credits | Official balance components and refresh info | Planned exact Credits | Planned truncated k/M/B Credits | No absolute low threshold; 0 exhausted |
| Unsupported provider | Hidden | Safe Settings reason only | Hidden | Hidden | N/A |

No compact value includes the word `used`.

No global combined percentage exists.

---

## 7. Refresh and lifecycle matrix

| Provider | Launch read | Manual Refresh | Scheduled read | Minimum cadence | One in-flight gate | Current failure behavior |
|---|---:|---:|---:|---:|---:|---|
| Codex | Yes when eligible | Yes | Existing connector policy | Existing accepted policy | Yes | Withdraw current admission |
| WorkBuddy | Yes when connected | Yes | Yes when Auto Refresh ON | 60s after completion | Yes | Hide; no manual/stale fallback |
| Manus | Planned when key configured | Planned | Optional planned | No faster than 60s unless M4 dossier tightens | Required | Hide; safe Settings error |
| Claude/Cursor/Kimi+/Doubao | No | No | No | N/A | N/A | Hidden |

Showing/hiding the Desktop Assistant causes no provider read.

---

## 8. Surface-admission matrix

| Condition | Codex | WorkBuddy | Manus after M4 |
|---|---:|---:|---:|
| Provider registered | Required | Required | Required |
| Local app running | Required only as defined by current Codex source | Not required | Not required |
| Authentication/configuration valid | Required | Required | Required API key |
| Source admitted | Required | Required | Required |
| Current successful read | Required | Required | Required |
| Last-valid snapshot only | Not enough | Not enough | Not enough |
| Placeholder card allowed | No | No | No |
| Settings reason allowed | Yes | Yes | Yes |

---

## 9. Current roadmap action

```text
NEXT:
M4-B0 — install current governing source and create merged-main worktree

THEN:
M4-G1 — Manus official API v2 source admission and secret-boundary dossier
```

Do not start M4-G2 unless M4-G1 returns GO or CONDITIONAL GO.

---

## Appendix A — Provider stable order

```text
1 Codex
2 Claude Code
3 WorkBuddy
4 Manus
5 Cursor
6 Kimi+
7 Doubao
8 Approved emerging slot
```

Hidden providers do not occupy visible rows.

Forced Minimalist depends on visible provider count greater than four.

---

## Appendix B — Current source references

```text
Scroll_2.0.md
UMA_Logic_1.4.md
UMA_0.11_closeout.md
M4_Plan.md
M4_Goal.md
Goal_Mode_2.0.md
DEV 3 shift report
```

Official Manus references are recorded in Scroll 2.0 and M4 Plan.
