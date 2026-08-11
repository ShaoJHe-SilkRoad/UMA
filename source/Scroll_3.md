# UMA Development Scroll 3.0

**Document type:** Master product-development sequence and progress ledger
**Version:** 3.0
**Date:** 2026-08-11
**Language:** English
**Product:** UMA — Usage Monitor Altoget
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`
**Current accepted runtime commit:** `e72bd92c476e05152b95ccb9ba95c22be78efef1`
**Current accepted runtime tree:** `c1358c5b4176383021e87605afc45ca3e347ab89`
**Current accepted M6 closeout commit:** `a6b846ea2785448c4d4e51ec0e775ff9220d33f5`
**Current accepted M7 closeout commit:** `e47f7de3e71f80d45a5561dad40e37f37ff11fd1`
**Current accepted M7 closeout tree:** `d836312beb29005e7b5abe882f9919d05a9b49f4`
**Current accepted package:** `/Users/juliushe/Developer/UMA-Packages/uma-m6adbg-final-e72bd92c476e05152b95ccb9ba95c22be78efef1/UMA.app`
**Protected installed Founder build:** `/Users/juliushe/Desktop/UMA_0.11.app`
**Current supported providers:** Codex, Claude Code, WorkBuddy, Google Antigravity
**Current unsupported provider decision:** Cursor — source not admitted
**Next provider program:** M8 — Kimi Unified Usage Source Admission
**Status:** Active governing roadmap; replaces Scroll 2.1 and retires its provider ordering and pre-M5/M6 assumptions

---

## 0. Current-state summary

```text
UMA 0.11 multi-provider foundation                 DONE
Codex                                               SUPPORTED
Claude Code                                         SUPPORTED
WorkBuddy                                           SUPPORTED
Google Antigravity                                  SUPPORTED — LIVE ACCEPTED
Cursor                                              UNSUPPORTED — SOURCE NO-GO
Manus                                               UNSUPPORTED — SOURCE NO-GO
Current visible-provider maximum                    4
Regular Assistant at 0–4 visible providers         ALLOWED
Forced Minimalist at >4 visible providers          LOCKED PRODUCT RULE
Next provider candidate                             Kimi ecosystem
M8 source-admission viability                       CONDITIONAL GO
M8 production implementation                        NOT YET AUTHORIZED
Next platform after Kimi                            TRAE / TraeWork
Next after TRAE                                     Qoder / QoderWork
CodeBuddy as separate provider                      PROHIBITED — WorkBuddy ecosystem overlap
External API-key input                              PROHIBITED
Manual quota entry or deduction                     PROHIBITED
Raw credential/token/cookie access                  PROHIBITED
Remote push/release/notarization/deployment         NOT AUTHORIZED
```

M6 is closed with Google Antigravity accepted as the fourth provider. M7 proved that Cursor's browser architecture is technically viable, but Cursor remains unsupported because the Free-plan dashboard does not reliably represent enforceable remaining usage and paid-plan pools were not live-qualified.

The next provider program is Kimi, not Qoder. This change is based on current market momentum, direct product fit, and source feasibility:

```text
Kimi.com + Kimi Work + Kimi Code
→ one account ecosystem
→ one shared membership credit pool
→ Kimi Code-specific 5-hour and weekly limits
→ official Kimi Code /usage command
→ provider-controlled OAuth login
```

This is a **GO to source admission**, not a production GO. M8 must prove the installed and live source behavior before any connector or fifth provider card is implemented.

---

## 1. Purpose

This Scroll defines:

- the accepted local Git, runtime, package, and installed-build baselines;
- the current supported and unsupported provider set;
- the current source-priority and authentication rules;
- the revised Chinese-platform sequence;
- why Kimi is the next provider candidate;
- the boundary between source admission, setup, implementation, live main-panel acceptance, five-provider density acceptance, Desktop Assistant integration, debugging, and closeout;
- the first required production proof of the `>4 → forced Minimalist` rule;
- later TRAE and Qoder source-admission programs;
- which documents are current and which are historical.

A provider name appearing in this Scroll does not mean that a production connector exists. A provider becomes supported only after a source is admitted, current live observations are proven, all protected providers remain unchanged, and the main panel and Desktop Assistant pass claim-matched acceptance.

---

## 2. Source authority

Use this priority:

```text
Current Founder instruction
→ current live repository evidence
→ latest accepted DEV report and independent audit
→ current accepted package/runtime evidence
→ Scroll 3.0
→ active milestone Plan and Goal file
→ UMA Logic 1.5 product principles
→ Goal Mode 2.0
→ Dev Default 2.1
→ retained historical plans, reports, screenshots, and packages
```

Consequences:

1. Scroll 2.1 is historical. It selected Claude status-line support as current, Antigravity as future, and Kiro/Kimi/Junie before Cursor. Those sequencing assumptions are superseded.
2. Current live evidence establishes Claude Browser Sync, not the retired Claude status-line route, as the accepted Claude quota source.
3. Current live evidence establishes Antigravity official read-only CLI `/usage`, not a status-line relay, as the accepted Antigravity source.
4. M7's accepted source decision establishes Cursor as unsupported under current policy. A technically workable browser extractor is not sufficient when the displayed quantity does not reliably predict enforceable usage.
5. Current official Kimi documentation and live installed behavior will outrank the research snapshot in this Scroll.
6. Historical source and checksum-locked `source/reference/**` files are evidence records. Do not rewrite them to make them appear current.

---

## 3. Canonical baseline

### 3.1 Accepted runtime lineage

The latest accepted production runtime remains the M6 combined closeout runtime:

```text
Runtime commit:
e72bd92c476e05152b95ccb9ba95c22be78efef1

Runtime tree:
c1358c5b4176383021e87605afc45ca3e347ab89

Final accepted package:
/Users/juliushe/Developer/UMA-Packages/
uma-m6adbg-final-e72bd92c476e05152b95ccb9ba95c22be78efef1/UMA.app

Bundle ID:
com.silkrd.uma

Version/build:
0.11 / 202608090106

Architecture:
arm64
```

M7 changed source-admission tests and documentation only. No Cursor runtime, browser extension, provider registration, package script, or existing provider mechanism was added.

### 3.2 Accepted M7 terminal closeout

```text
Workspace:
/Users/juliushe/Developer/UMA-M7-Cursor

Branch:
codex/uma-m7-cursor

Current accepted HEAD:
e47f7de3e71f80d45a5561dad40e37f37ff11fd1

Tree:
d836312beb29005e7b5abe882f9919d05a9b49f4

Result:
M7 CLOSED — CURSOR UNSUPPORTED — SOURCE NOT ADMITTED
```

Historical M7-G1C source-decision evidence remains:

```text
Historical commit:
fcb51ab48bb076704431742b7b0300c235975f8e

Historical tree:
43dac9a01be51c3f19b3e510d3ff6923ca4bae57

Historical result:
NO-GO — CURSOR PRODUCTION SUPPORT REMAINS LOCKED
```

That historical commit is the direct parent of the accepted closeout. It is
retained as evidence, not used as the M8 branch point.

The M7 browser proof established:

- provider-controlled Safari authentication was feasible;
- sanitized dashboard extraction was feasible;
- the Free-plan percentage represented used percentage;
- `remaining = 100 - used` was deterministic;
- dashboard/IDE enforcement reliability was not admitted;
- paid-plan two-pool layouts were documented but not live-qualified;
- temporary Safari companions were removed;
- Safari unsigned-extension mode was restored to Off;
- Cursor remained hidden and unsupported.

### 3.3 M8 branch and worktree rule

M8 must branch from the exact accepted M7 terminal closeout, not from remote `main`, the historical M7-G1C source-decision commit, or the older M6 runtime branch.

Expected:

```text
Source workspace:
/Users/juliushe/Developer/UMA-M7-Cursor

Source branch:
codex/uma-m7-cursor

Parent commit:
e47f7de3e71f80d45a5561dad40e37f37ff11fd1

Parent tree:
d836312beb29005e7b5abe882f9919d05a9b49f4

M8 branch:
codex/uma-m8-kimi

M8 worktree:
/Users/juliushe/Developer/UMA-M8-Kimi
```

M8-B0 must stop if the parent lineage, worktree state, or source hierarchy materially differs.

### 3.4 Package and installed-build distinction

The accepted M6 package is a local commit-exact verification package. It was not installed as the protected Founder Desktop app and was not publicly distributed.

```text
Protected installed app:
/Users/juliushe/Desktop/UMA_0.11.app

Protected executable SHA-256:
88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

M8 may build new packages under:

```text
/Users/juliushe/Developer/UMA-Packages
```

M8 may not replace the protected installed app without a separate current Founder instruction.

---

## 4. Accepted progress

### 4.1 Foundation and product shell

```text
M1A Codex stability                              DONE
M2 Desktop Assistant                            DONE
M2DBG / M2A / M2ADBG                            DONE
P0.10.1 UI/settings/package corrections         DONE
R0 source reconstruction                        DONE
UMA 0.11 multi-provider architecture            DONE
```

### 4.2 WorkBuddy program

```text
Provider-native exact Credits                   DONE
Provider-controlled account-web login           DONE
Complete all-pool aggregation                   DONE
One-minute Auto Refresh                         DONE
Main-panel and Assistant parity                 DONE
Combined qualification                          DONE
```

CodeBuddy remains part of the same Buddy AI ecosystem. It must not receive a second quota card unless future official evidence proves a genuinely distinct account balance.

### 4.3 M5 Claude Code

```text
Claude Browser Sync quota source                DONE
Automatic five-minute provider-page read        DONE
Separate local activity/cost estimate           DONE
Retired status-line route removed               DONE
Main-panel and Assistant parity                 DONE
Current runtime support                         SUPPORTED
Developer ID/notarization distribution work     NOT PROVEN
```

Claude account quota comes from Browser Sync. Claude local activity is an estimate channel and never substitutes for account quota.

### 4.4 M6 Google Antigravity

```text
Official agy CLI installed and admitted         DONE
Read-only structured /usage source              DONE
Remaining-fraction decoder                      DONE
Five-minute completion-relative scheduler       DONE
Main-panel fourth provider                      DONE
Desktop Assistant fourth provider               DONE
Four-provider combined acceptance               DONE
Final package                                   DONE
M6 closeout                                     DONE
```

Antigravity Credits remain deferred. Individual-account quota is supported; enterprise/unclassified modes fail closed.

### 4.5 M7 Cursor

```text
Direct local/CLI source                         NO-GO
Official dashboard browser architecture         VIABLE
Free-plan used-percent semantic                 PROVEN
Free-plan enforcement reliability               NOT ADMITTED
Paid-plan two-pool contract                      DOCUMENTED / NOT LIVE-QUALIFIED
Production connector                            NOT IMPLEMENTED
Cursor provider card                            HIDDEN
Final M7 decision                               UNSUPPORTED
```

M7 is a successful source-admission NO-GO. It prevented an unreliable quantity from entering the product.

---

## 5. Current accepted user value

UMA currently provides:

- one native macOS menu-bar application;
- one status item;
- one compact multi-provider main panel;
- one optional floating Desktop Assistant;
- four supported providers in stable order;
- equal provider cards and independent details/settings;
- shared main-panel/Assistant presentation truth;
- centralized Maximum Decrement for percentage windows;
- provider-native exact Credits where appropriate;
- current-read admission and provider-specific failure isolation;
- Light, Dark, transparency, contrast, motion, English, and Simplified Chinese support;
- commit-exact local package evidence.

Current providers:

```text
1. Codex
2. Claude Code
3. WorkBuddy
4. Google Antigravity
```

UMA does not yet provide:

- Kimi unified membership and Kimi Code quota monitoring;
- a fifth supported provider;
- live proof of forced Minimalist caused by a real fifth provider;
- TRAE or Qoder monitoring;
- Cursor support;
- Antigravity Credits;
- a notarized public release;
- a stable 1.0 distribution channel.

---

## 6. Updated source policy

### 6.1 Mandatory source order

```text
1. Official local service or IPC
2. Official local status line, hook, or event
3. Official read-only CLI or documented local metadata
4. Provider-controlled official account/browser surface
5. Unsupported
```

A source may perform provider-owned network activity internally. UMA must not receive the credential.

### 6.2 External credential ban

UMA does not accept:

- user-entered provider API keys for quota monitoring;
- copied OAuth/access/refresh tokens;
- setup tokens;
- personal access tokens;
- exported cookies;
- browser-profile imports;
- Keychain credential reads;
- local authentication database parsing;
- credential brokers.

An official provider CLI may own and use its own login state. UMA may invoke an admitted read-only command without inspecting credential storage.

### 6.3 Provider-controlled browser fallback

Browser/account fallback is permitted only when:

- local/CLI source admission failed or is incomplete;
- the provider has an official usage surface;
- login occurs through the provider-controlled page;
- UMA imports no browser session or cookie;
- extraction is route-bound, semantic, sanitized before native handoff, and fail-closed;
- no private endpoint is promoted into a production contract;
- Disconnect clears UMA-owned state but does not alter provider credentials.

### 6.4 Prohibited substitutes

No:

- private provider databases or caches;
- undocumented internal account APIs as production source;
- DevTools network-token extraction;
- OCR or screenshot scraping as a stable source;
- Accessibility/UI scraping represented as a stable API;
- packet capture;
- process memory;
- broad process argv/environment capture;
- manual values;
- manual deduction;
- activity-derived estimated balance.

---

## 7. Current provider feasibility and direction

### 7.1 Current provider matrix

| Priority | Provider | Native unit | Accepted/candidate source | Current decision | Direction |
|---:|---|---|---|---|---|
| 1 | Codex | Remaining percentages; token/cost details | Local app-server + approved local logs | Supported | Preserve |
| 2 | Claude Code | Remaining quota percentages; separate activity estimate | Browser Sync + local activity reader | Supported | Preserve |
| 3 | WorkBuddy | Exact Credits | Provider-controlled account web | Supported | Preserve |
| 4 | Google Antigravity | Remaining percentages | Official read-only `agy /usage` | Supported | Preserve |
| 5 | **Kimi ecosystem** | Shared membership remaining percentage (account/cycle dependent) + Kimi Code limits; optional native Extra Usage detail | Official Kimi Code `/usage`; official Kimi account/console fallback | **Conditional GO to source admission** | **M8 NEXT** |
| 6 | TRAE / TraeWork | Platform Credits / plan usage, account-mode dependent | Official platform source dossier required | Strong later candidate | M9 |
| 7 | Qoder / QoderWork | Qoder Credits | Official CLI/account source dossier required | Strong later candidate | M10 |
| 8 | Baidu Comate | Unknown | No admitted individual quota source | Watchlist | Later research |
| — | Cursor | Dashboard used percentage, enforcement mismatch | Browser architecture viable but source unreliable | Unsupported | Reopen only on explicit conditions |
| — | Manus | No admitted source under current policy | Prior API-key/local investigation failed | Unsupported | Deferred |

### 7.2 Why Kimi is next

Current official evidence establishes:

- Kimi K3 is available on Kimi.com, Kimi Work, Kimi Code, and Kimi API;
- Kimi Work is a local desktop Agent for knowledge workers and uses Kimi Code as its kernel;
- Kimi Code is an official terminal/IDE coding Agent;
- current Kimi membership documentation describes one shared credit pool across membership features;
- general membership pages describe a monthly cycle, while current Kimi Code benefit pages also describe weekly credit periods and an upcoming membership/Code plan split;
- Kimi Code also has independent rolling five-hour and weekly limits;
- Kimi Code provides an official `/usage` command for quota information;
- Kimi Code supports provider-controlled OAuth device-code login;
- Kimi K3 demand was high enough that Moonshot temporarily paused new subscriptions after usage exceeded capacity forecasts.

Public Douyin indexing also exposes multiple current long-tail query families for Kimi K3, Kimi Code installation, plan limits, quota, API configuration, and tutorials. Public Douyin and Xiaohongshu pages do not expose reliable raw search-volume counts, so Scroll 3 records social discoverability as directional evidence rather than inventing exact search numbers.

### 7.3 Why Qoder is not first

Qoder has a clear Credits model and officially supports Kimi K3. It remains a viable later provider. It is not the next provider because:

- Kimi is the first-party ecosystem that owns Kimi K3;
- Kimi spans both knowledge work and coding, matching UMA's WorkBuddy/Codex use cases;
- current Kimi demand and social discoverability are stronger;
- supporting Kimi directly avoids monitoring a host platform while missing the first-party Kimi account limits.

### 7.4 Why TRAE follows Kimi

TRAE and TraeWork officially include Kimi K3 in paid tiers and have broad Chinese market visibility. TRAE remains after Kimi because its quota model varies across personal, regional, product, and enterprise modes and requires a separate source-admission program.

### 7.5 Kimi provider identity

Kimi must be one provider, not separate cards:

```text
Kimi.com
Kimi Work
Kimi Code
Kimi Agent / Slides / Research / other membership features
→ shared Kimi membership account
→ one Kimi provider identity
```

Kimi Code-specific limits may appear as a second channel/details inside the same provider.

Kimi Open Platform API balance is a separate API product and is not part of M8. It requires API-key authentication and is explicitly excluded.

---

## 8. Revised master sequence

```text
M1A       Codex stability                                      DONE
M2        Desktop Assistant                                    DONE
M2DBG     Assistant shell debugging                            DONE
M2A       Production Codex Assistant binding                   DONE
M2ADBG    Main + Assistant closeout                            DONE
P0.10.1   UI/settings/package correction                       DONE

R0        Source reconstruction                                DONE
M2W       WorkBuddy Credit foundation                          DONE
M2W-LIVE  WorkBuddy Account Web Sync                           DONE
M2W-R1    WorkBuddy one-minute Auto Refresh                    DONE
STAB      Stability and 0.11 preparation                       DONE
UMA011    Multi-provider architecture and final DBG            DONE
GIT011    Founder main integration                             DONE

M4        Manus investigation                                  CLOSED / NO-GO
M5        Claude Code support                                  CLOSED / SUPPORTED
M6        Google Antigravity support                           CLOSED / SUPPORTED
M7        Cursor source admission                              CLOSED / NO-GO

M8        Kimi unified usage source admission                  NEXT
M8-G2+    Runtime only after unified-source GO                 CONDITIONAL
M8A       Kimi Assistant + first real forced-Minimalist proof  CONDITIONAL

M9        TRAE / TraeWork source admission                     QUEUED
M10       Qoder / QoderWork source admission                   QUEUED
M11       Additional Chinese-platform source dossiers          QUEUED

M12       Product feedback and narrow fixes                    QUEUED
M13       Product formation and long stability qualification  QUEUED
M14       Release-candidate closure                            QUEUED
M15       Stable 1.0 release                                   QUEUED
M16       Post-launch hot-fix window                           QUEUED
M17       Additional security hardening                       QUEUED
```

No provider program starts automatically.

---

## 9. M8 Kimi program sequence

```text
M8-B0
→ M8-G1
→ M8-SETUP-G1 only when official CLI/login is missing
→ M8-G1R after setup when required
→ M8-WEB-G1 only when the official CLI cannot provide the shared membership metric
→ M8-G2 only after overall unified-source GO / implementation-ready CONDITIONAL GO
→ M8-G3
→ M8DBG-G1
→ M8A-G1
→ M8ADBG-G1
→ M8-CLOSE-G1
```

Source decisions are channel-aware:

```text
Channel A:
Kimi shared membership credits with provider-supplied cycle

Channel B:
Kimi Code rolling 5-hour + weekly limits

Continuation detail:
Extra Usage enable/balance state when present
```

M8 must not implement a Kimi unified provider if only Kimi Code limits are available while the ecosystem-wide shared membership pool remains unknown. That would omit the limit capable of stopping Kimi Work, Kimi Agent, Kimi Code, and other membership features.

---

## 10. Kimi source decision boundary

### 10.1 Current official product contract

Current official documentation supports this research hypothesis:

```text
All Kimi membership features
→ one shared membership credit pool
→ current balance shown as a percentage
→ provider-supplied cycle/reset (current official pages differ across general membership and Kimi Code benefit modes)

Kimi Code
→ consumes the same shared pool
→ also has rolling 5-hour and weekly limits

Extra Usage
→ separate pay-as-you-go balance
→ may continue work after subscription credits are exhausted
```

M8 must verify the live account because Kimi plan presentation is changing and legacy/new plan availability remains in transition.

### 10.2 Preferred source

Primary candidate:

```text
Official Kimi Code CLI
→ provider-controlled Kimi Code OAuth
→ operational /usage command
→ remaining quota and optional Extra Usage information
```

The official docs prove that `/usage` exists, but they do not yet prove a stable machine-readable, non-interactive quota output. M8-G1/G1R must prove whether the command can be invoked without an agent turn and parsed deterministically without reading credential files.

### 10.3 Conditional browser source

When CLI output does not contain the shared membership credit balance:

```text
Official Kimi Subscription / My Quota page
or
Official Kimi Code Console
→ provider-controlled login
→ bounded semantic extraction
→ sanitized observation
```

M8 may use one Kimi provider with at most two admitted channels. It must not create separate Kimi Work, Kimi Code, Kimi.com, or Kimi API cards.

### 10.4 Rejected source classes

M8 does not use:

- Kimi Open Platform balance API;
- Kimi Open Platform API key;
- Kimi Code API key copied into UMA;
- OAuth token files under Kimi Code storage;
- private Kimi account endpoints called directly by UMA;
- local token/activity estimation as account quota;
- Kimi Work task logs or conversations;
- screenshot/OCR extraction;
- manual credit entry.

### 10.5 Extra Usage rule

Extra Usage cannot be silently ignored when enabled because it may allow continued work after subscription quota is exhausted.

M8 source admission must classify:

```text
extra usage unavailable
extra usage disabled
extra usage enabled with exact balance
extra usage enabled but balance unreadable
```

A production implementation may defer the Extra Usage compact channel only when it is absent or disabled, or when an explicit continuation state can be presented honestly. It must not show `0% remaining → work stops` while a positive Extra Usage balance keeps work available.

---

## 11. Roadmap interpretation rules

### 11.1 One active milestone

Only one implementation milestone may be active unless the Founder explicitly authorizes parallel work.

### 11.2 Source admission first

Every provider program begins with source, authentication, unit, privacy, and lifecycle admission.

### 11.3 Local/provider CLI before browser fallback

Browser fallback is considered only when official local/CLI sources cannot provide the complete required metric.

### 11.4 Main app first, Assistant second

The Desktop Assistant never owns provider transport, login, WebView, CLI process, decoder, cache, timer, or quota selection.

### 11.5 Visible-provider count controls density

```text
visible providers <= 4
→ Regular or user-selected Minimalist allowed

visible providers > 4
→ forced Minimalist
```

Kimi is expected to be provider five. M8A must be the first live production proof of the forced transition.

When the visible count returns to four or fewer, the product must restore the user's valid prior mode according to the existing shared density contract; it must not remain permanently forced.

### 11.6 Provider-native units

- Codex, Claude, Antigravity, and percentage Kimi windows remain percentages.
- WorkBuddy remains exact Credits.
- Kimi shared credits remain the provider's explicit current percentage unless an exact native credit balance is live-admitted.
- Kimi Extra Usage remains its native currency/balance; never convert it to percentage without a complete same-scope denominator.
- Missing is not zero.
- Unlimited is not 100%.
- Stale is not current.

### 11.7 No manual quota substitute

No source failure may trigger manual entry, manual deduction, or inferred balance.

### 11.8 Remote delivery remains separate

Local commits may be authorized by exact Goals.

Push, merge, tag, release, signing, notarization, publication, deployment, and protected Desktop replacement require separate current authority.

---

## 12. Cross-milestone product contracts

### 12.1 One-host architecture

```text
registered provider catalog
→ source admission
→ one connector per admitted provider
→ one serialized UsageStore
→ one shared presentation policy
├── main panel
└── Desktop Assistant
```

### 12.2 Current-read admission

A provider appears only after a current successful admitted observation or an explicitly permitted provider-specific stale state.

Kimi installation or login alone does not admit the provider.

### 12.3 Maximum Decrement

Percentage-window selection remains centralized. Refill increases and expired epochs do not win.

Kimi shared-membership and Kimi Code windows must preserve provider-supplied cycle, scope labels, and identities. The compact selector may choose the most urgent admitted percentage window only after the product proves that doing so remains honest for the provider's current continuation state.

### 12.4 Status and quota are separate

A healthy source may report low quota. A disconnected source may have unknown quota. Do not combine source health and quota value into one state.

### 12.5 Provider settings

Per-provider settings:

- use stable IDs;
- persist across relaunch;
- remain available while hidden;
- fail closed on future schema;
- contain no external API-key field;
- explain exact source and login behavior.

### 12.6 Privacy

Do not collect or retain:

- passwords;
- provider API keys or tokens;
- exported cookies;
- Keychain secrets;
- account identity unless separately justified and minimized;
- conversation/task content;
- source code;
- transcript files;
- private databases;
- raw provider payloads;
- full process argv or environment dumps.

### 12.7 Safe process inspection

Allowed process evidence is bounded to:

- exact executable path/name;
- exact PID;
- owned parent/child relation;
- process count;
- resource counters;
- exit/absence state.

Broad command-line and environment enumeration is prohibited.

### 12.8 Source transparency

Every provider Settings page must disclose:

- exact source type;
- login requirement;
- credentials visible to UMA;
- data retained;
- provider/network behavior;
- update cadence;
- disable/disconnect behavior;
- known unsupported account modes.

---

## 13. Open nonblocking work

The following do not block M8 source admission:

- the protected installed Desktop app remains the older Founder build;
- the accepted M6 package is ad-hoc signed and not notarized;
- Developer ID signing/notarization and Safari entitlement acceptance remain unproven;
- Antigravity Credits remain deferred;
- enterprise account coverage is incomplete for some providers;
- Cursor remains unsupported;
- remote main may not contain every accepted local branch commit;
- public README/product wording may lag current local source truth;
- physical VoiceOver remains deferred where already accepted.

Do not mix these into Kimi source admission unless they directly block M8.

---

## 14. Risk register

| ID | Risk | Status | Handling |
|---|---|---|---|
| S3-R01 | M8 parent is source-only M7 branch, not remote main | Controlled | M8-B0 verifies exact local parent and creates isolated worktree |
| S3-R02 | Kimi CLI absent | Expected possible blocker | M8-G1 returns SETUP REQUIRED; M8-SETUP uses official installer/login |
| S3-R03 | `/usage` is interactive and not machine-readable | Blocking candidate | Live PTY/read-only admission; fail closed or use official browser source |
| S3-R04 | `/usage` omits shared membership credit | High | Conditional M8-WEB-G1; no unified implementation without shared pool |
| S3-R05 | Kimi plan structure is changing | High | Account-mode/version classification; no hard-coded legacy/new plan assumptions |
| S3-R06 | Kimi Code OAuth token is stored locally | Controlled | UMA invokes provider CLI only; never reads token files |
| S3-R07 | Kimi Open Platform is confused with membership | High | Explicit product isolation; API-key/balance API excluded |
| S3-R08 | Extra Usage allows continuation after 0% | High | Detect enable/balance/continuation state; do not misstate pause condition |
| S3-R09 | Browser fallback increases privacy surface | Controlled | Provider-controlled login, route/field allowlist, no cookie/token import |
| S3-R10 | Fifth provider density regresses Assistant | High | M8A owns live >4 forced-Minimalist acceptance and restore behavior |
| S3-R11 | Existing four provider mechanisms regress | High | Frozen-zone audits and full regressions in every implementation Goal |
| S3-R12 | Kimi server demand/capacity variability | External | Fail closed; do not confuse provider outage with account quota |
| S3-R13 | No notarized release | Distribution only | Separate Release Mode |
| S3-R14 | Popularity pressure encourages weak source | Product risk | No implementation before source admission, regardless of market demand |

---

## 15. Required progress-update format

After every accepted major Goal, update current truth with:

```text
Current milestone:
Latest accepted local commit:
Latest accepted tree:
Latest accepted package:
Milestone verdict:
Proven user value:
Unproven items:
Open blocking risks:
Open nonblocking risks:
Next authorized Goal:
Explicitly paused work:
Canonical workspace:
```

Do not rewrite historical closeout records.

---

## 16. Immediate next action

```text
M8-B0
→ verify M7 terminal closeout e47f7de... and clean state
→ create codex/uma-m8-kimi worktree
→ install Scroll 3.0, M8 Plan, M8 Goal, M8 Scope Lock, and M7 terminal closeout truth
→ run deterministic baseline through script/test.sh
→ verify four existing provider mechanisms unchanged
→ create one docs-only local commit
→ stop
```

After accepted M8-B0:

```text
M8-G1
→ inspect current official Kimi products, CLI, account modes, and source candidates
→ return GO / CONDITIONAL GO / SETUP REQUIRED / NO-GO
→ do not implement runtime automatically
```

---

## Appendix A — Status legend

| Marker | Meaning |
|---|---|
| `DONE` | Accepted with claim-matched evidence |
| `SUPPORTED` | Live source, UI, lifecycle, package, and privacy accepted |
| `ACTIVE` | Current authorized execution |
| `NEXT` | Immediate next program, not yet executing |
| `QUEUED` | Ordered but not authorized to start |
| `CONDITIONAL` | Requires source, setup, or explicit Founder gate |
| `DEFERRED` | Valid future route, not current |
| `UNSUPPORTED` | No admitted source under current policy |
| `BLOCKED` | Cannot continue until a defined external gate closes |
| `RELEASED` | Published through an authorized release channel |

---

## Appendix B — Current governing source set

```text
Scroll_3.md
M8_Plan.md
M8_Goal.md
UMA_Logic_1.5.md
Goal_Mode_2.0.md
Dev_Default_2.1.md
UMA M6 Closeout and Cursor Handoff.md
accepted M7 Cursor source-admission records
accepted M6/M5 closeout records
```

Historical:

```text
Scroll 2.1 and earlier
M7 planning assumptions superseded by accepted NO-GO
M6 Plan / Goals after closeout
M5 Plan / Goals after closeout
M4 Plan / Goals
older provider matrices
older QA ledgers and packages
```

---

## Appendix C — Current official Kimi research references

Retrieved 2026-08-11:

```text
https://www.kimi.com/blog/kimi-k3
https://www.kimi.com/
https://www.kimi.com/help/kimi-work/overview
https://www.kimi.com/help/kimi-work/release-notes
https://www.kimi.com/code
https://www.kimi.com/code/docs/en/
https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html
https://www.kimi.com/code/docs/en/kimi-code-cli/reference/slash-commands.html
https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html
https://www.kimi.com/code/docs/en/kimi-code-cli/release-notes/changelog.html
https://www.kimi.com/help/membership/membership-pricing
https://www.kimi.com/help/membership/membership-overview
https://www.kimi.com/help/membership/update-rules
https://www.kimi.com/help/membership/membership-extra-usage
https://www.kimi.com/help/agent/quota-and-billing
https://www.kimi.com/help/kimi-code/benefits
https://www.kimi.com/help/kimi-blackboard/plan-adjustment-notice
https://www.kimi.com/help/kimi-api/api-troubleshooting
https://github.com/MoonshotAI/kimi-code
```

Current official documentation and installed live behavior outrank this static snapshot.

---

## Appendix D — Popularity evidence note

Popularity is a prioritization input, not a source-admission substitute.

Current public evidence includes:

- Moonshot's official Kimi K3 launch across Kimi.com, Kimi Work, Kimi Code, and API;
- Reuters reporting that demand exceeded forecasts and caused a temporary new-subscription pause;
- active Kimi Work and Kimi Code release cadence in August 2026;
- public Douyin search indexing for Kimi K3, Kimi Code plans, quota, installation, and tutorials;
- broad open-source and developer discussion after the K3 release.

Exact Douyin and Xiaohongshu keyword search counts are not publicly exposed in a reliable, comparable form. Scroll 3 therefore does not fabricate raw search volume.
