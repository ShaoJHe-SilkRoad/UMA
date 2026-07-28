# UMA Development Scroll 2.1

**Document type:** Master product-development sequence and progress ledger  
**Version:** 2.1  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Canonical remote branch:** `main`  
**Current canonical main commit:** `469be4d6cf411a89401c2341807a57aef176d852`  
**Accepted post-M4 local closeout commit:** `178e6ca47e514dc257ddd5db82a223e5eeb42b85`  
**Accepted post-M4 local closeout tree:** `1871b59ebe8ffdb59784292bf0a52cbde70e4925`  
**Current installed Founder build:** `/Users/juliushe/Desktop/UMA_0.11.app`  
**Current installed version/build:** `0.11 / 202607270003`  
**Current milestone:** `M5 — Claude Code Local Structured Usage Support`  
**Status:** Active governing roadmap; replaces Scroll 2.0 and retires the Manus-first/API-key direction

---

## 0. Current-state summary

```text
UMA 0.11 local implementation                DONE
UMA 0.11 final qualification                 DONE
Founder Desktop installation                 DONE
Founder main integration                     DONE through PR #3
M4 Manus API investigation                   CLOSED / NO-GO
M4 API-key runtime path                      RETIRED
M4-G3 WIP                                    CLEARED
Current production-capable providers         Codex + WorkBuddy
Next provider program                        Claude Code
Preferred source direction                   Official local structured source
Fallback source direction                    Isolated provider-controlled login
External API-key input                       PROHIBITED
Manual balance entry/deduction               PROHIBITED
Public GitHub Release                        NOT STARTED
Apple notarization                           NOT STARTED
```

M4 is closed. Manus remains hidden. The external API-key product route was removed from production source and package output by M4-N.

The immediate next program is Claude Code through its official local status-line JSON. This is a local structured integration, not an Anthropic API integration.

---

## 1. Purpose

This Scroll defines:

- the current accepted Git and package baseline;
- the current provider set;
- the source-priority and authentication direction;
- the next provider sequence based on current feasibility;
- the boundary between local source, login fallback, connector implementation, main-panel acceptance, Desktop Assistant integration, and closeout;
- the forced-Minimalist threshold;
- later feedback, productization, release, and hardening stages;
- which documents are current and which are historical.

It is a sequencing and status contract. A provider name appearing here does not mean that a production connector already exists.

---

## 2. Source authority

Use this priority:

```text
Current Founder instruction
→ current live repository evidence
→ latest accepted DEV report
→ current accepted package/runtime evidence
→ UMA Logic 1.5
→ Goal Mode 2.0
→ this Scroll 2.1
→ active milestone Plan and Goals
→ historical plans, reports, screenshots, and packages
```

Consequences:

1. Scroll 2.0 is historical because it selected Manus and an API-key route.
2. Logic 1.4 is historical because it admitted an external remote-API source class.
3. M4 Plan and Goals remain historical execution records, not current direction.
4. M4-N commit `178e6ca...` is the accepted local closeout authority even though remote `main` remains at `469be4d...` until a later controlled integration.
5. M3 Plan and Goals contain useful Claude relay concepts but have stale baselines, model routing, and provider sequence.
6. Current official provider documentation and live installed behavior outrank static capability assumptions.

---

## 3. Canonical baseline

### 3.1 Remote main lineage

```text
Qualified UMA 0.11 development source:
459ea1321817e391ba80fe79f19edb0352fc76cb

UMA 0.11 main-history integration:
ff6553943280836fb0d3db5289f85b163c41c1a3

Merged remote main:
469be4d6cf411a89401c2341807a57aef176d852
```

### 3.2 Accepted post-M4 local successor

```text
Workspace:
/Users/juliushe/Developer/UMA-M4-Manus

Branch:
codex/uma-m4-manus

M4-N closeout commit:
178e6ca47e514dc257ddd5db82a223e5eeb42b85

Tree:
1871b59ebe8ffdb59784292bf0a52cbde70e4925

Result:
M4 CLOSED — MANUS UNSUPPORTED — NO API-KEY PRODUCT PATH
```

The M4-N runtime matches the accepted pre-M4-G2 product behavior while preserving M4 research and closeout history.

### 3.3 Current package and installed build

```text
Current installed application:
/Users/juliushe/Desktop/UMA_0.11.app

Version/build:
0.11 / 202607270003

Bundle ID:
com.kevinchen.CodexUsageMonitor

Architecture:
arm64

Minimum macOS:
14.0
```

No M5 task may replace the installed application without a separate explicit installation instruction.

### 3.4 M5 starting rule

M5-B0 should create a new worktree from the exact accepted M4-N commit when that commit is present and clean.

Expected:

```text
Branch:
codex/uma-m5-claude

Worktree:
/Users/juliushe/Developer/UMA-M5-Claude

Parent:
178e6ca47e514dc257ddd5db82a223e5eeb42b85
```

If the commit is missing, dirty, or unrelated to the canonical repository, M5-B0 must stop and produce one reconciliation packet. It must not silently branch from stale `main` or rewrite accepted history.

---

## 4. Accepted progress

### 4.1 Foundation and product shell

```text
M1A Codex stability                           DONE
M2 Desktop Assistant                         DONE
M2DBG / M2A / M2ADBG                         DONE
P0.10.1 UI/settings/package corrections      DONE
R0 source reconstruction                     DONE
```

### 4.2 WorkBuddy program

```text
Provider-neutral Credit model                DONE
WorkBuddy Account Web Sync                   DONE
Complete all-pool aggregation                DONE
One-minute Auto Refresh                      DONE
Main-panel and Assistant parity              DONE
Combined stability/qualification             DONE
```

### 4.3 UMA 0.11 multi-Agent product

```text
Equal Agent cards                            DONE
Independent Agent details                    DONE
Independent Agent Settings                   DONE
Show All / Hide All                          DONE
Preference persistence                       DONE
First manual Agent search                    DONE
Optional later Auto Search                   DONE
Maximum Decrement centralization             DONE
Single-contour glass                         DONE
Main/Assistant parity                        DONE
Final DBG                                    DONE
Founder main integration                     DONE
```

### 4.4 M4 Manus program

```text
Official API source dossier                  DONE historically
Offline API-key prototype                    DONE historically
Founder API-key rejection                    DONE
CLI-only source investigation                NO-GO
API-key production path retirement           DONE
M4-G3 WIP cleanup                            DONE
Final M4 status                              CLOSED / UNSUPPORTED
```

M4 did not install or release a Manus integration.

### 4.5 Final accepted M4-N verification

```text
Focused retirement tests                     7/7 PASS
Full suite                                   325/325 PASS across 40 suites
Debug build                                  PASS
Release build                                PASS
Strict-concurrency Release                   PASS
Codex regressions                            PASS
WorkBuddy regressions                        PASS
Package privacy/provenance                   PASS
```

---

## 5. Current accepted user value

UMA currently provides:

- one native macOS menu-bar application;
- one status item;
- one compact multi-Agent main panel;
- one optional floating Desktop Assistant;
- equal Codex and WorkBuddy cards;
- independent Agent details and Agent Settings;
- shared main-panel/Assistant truth;
- Codex remaining-limit monitoring;
- Codex recent tasks and API-equivalent cost details;
- WorkBuddy exact all-pool Credits;
- WorkBuddy provider-controlled Account Web Sync;
- WorkBuddy one-minute Auto Refresh and Manual-only mode;
- persistent per-Agent settings;
- manual first Agent search and optional later Auto Search;
- Light, Dark, transparency, contrast, motion, VoiceOver, English, and Simplified Chinese support;
- package-safe typography and glass.

UMA does not yet provide:

- Claude Code remaining limits;
- Google Antigravity quota;
- Kiro, Kimi Code, Junie, Cursor, Windsurf, Manus, TRAE, or Doubao usage;
- a notarized public release;
- a stable 1.0 distribution channel.

---

## 6. Updated source policy

### 6.1 Mandatory source order

```text
1. Official local service or IPC
2. Official local status line, hook, or event
3. Official read-only CLI or documented local metadata
4. Isolated provider-controlled account login fallback
5. Unsupported
```

### 6.2 External API-key ban

UMA does not accept:

- provider API keys;
- copied OAuth tokens;
- setup tokens;
- personal access tokens;
- cloud credentials;
- API-key helpers configured for UMA.

A provider CLI may manage its own login internally. UMA may read an admitted local usage output without receiving credentials.

### 6.3 Login fallback

Login is permitted when:

- local source admission has failed or lacks the needed current metric;
- the provider has an official usage page;
- login occurs on the provider-controlled page;
- UMA imports no browser session;
- extraction is usage-only, route-bound, and fail-closed;
- the user consents;
- Disconnect clears UMA-owned provider session state.

New fallback providers default to:

```text
Keep Signed In: OFF
Auto Refresh: OFF / Manual only
```

Provider-specific testing may later admit opt-in persistence or Auto Refresh.

WorkBuddy retains its accepted default behavior.

### 6.4 Prohibited substitutes

No:

- private databases or caches;
- OCR;
- Accessibility extraction;
- UI automation represented as a stable source;
- packet capture;
- process memory;
- cookie or token extraction;
- manual values;
- manual deduction;
- estimated balance.

---

## 7. Current provider feasibility and direction

| Priority | Provider | Preferred source | Login fallback | Current decision | Direction |
|---:|---|---|---|---|---|
| 1 | Codex | Local app-server | Not required | Live-qualified | Preserve |
| 2 | Claude Code | Official local status-line JSON | Conditional only if local quota unavailable | Strong GO candidate | M5 NEXT |
| 3 | WorkBuddy | No admitted local balance source | Existing isolated account login | Live-qualified / Experimental | Preserve |
| 4 | Google Antigravity CLI | Official local status-line JSON | Conditional | Strong future candidate | M6 |
| 5 | Kiro | Official CLI/ACP dossier | Conditional | Research candidate | M7 |
| 6 | Kimi Code | Official CLI/local-server dossier | Conditional | Research candidate | M8 |
| 7 | Junie | Official CLI/ACP dossier | Conditional | Research candidate | M9 |
| 8 | Cursor | No admitted local quota source | Official account usage login candidate | Fallback candidate | M10 cohort |
| 9 | Windsurf | No admitted local quota source | Official account usage login candidate | Fallback candidate | M10 cohort |
| 10 | Manus | No admitted local source | Future account-web dossier permitted | Deferred after M4 closeout | M10 cohort / low priority |
| 11 | TRAE / Doubao / Ark | Source dossier required | Conditional official login only | Unproven | Watchlist |

CodeBuddy must not receive a second balance card because it shares the WorkBuddy Buddy AI Credit pool.

Multi-provider shells such as OpenCode, Cline, Roo Code, or Aider should not receive independent quota cards unless they own a distinct quota pool. Monitor the underlying provider instead.

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
UMA011    Multi-Agent architecture and final DBG               DONE
GIT011    Founder main integration                             DONE

M4        Manus investigation and API-route retirement         CLOSED / NO-GO

M5        Claude Code local status-line support                NEXT
M5DBG     Codex + Claude + WorkBuddy main-app debugging        QUEUED
M5A       Claude Code in Desktop Assistant                     QUEUED
M5ADBG    Three-provider combined closeout                     QUEUED

M6        Google Antigravity local status-line support         QUEUED
M6DBG/A   Main + Assistant acceptance                          QUEUED

M7        Kiro local-source admission                          QUEUED
M7-L      Local connector only after GO                        CONDITIONAL
M7-W      Account-login fallback only after local NO-GO        CONDITIONAL

M8        Kimi Code local-source admission                     QUEUED
M8-L/W    Local or account-login implementation                CONDITIONAL

M9        Junie local-source admission                         QUEUED
M9-L/W    Local or account-login implementation                CONDITIONAL

M10       Account-web fallback candidates, one at a time       QUEUED
           Cursor → Windsurf → Manus/other by Founder priority

M11       Product feedback and narrow fixes                    QUEUED
M12       Product formation and long stability qualification  QUEUED
M13       Release-candidate closure                            QUEUED
M14       Stable 1.0 release                                   QUEUED
M15       Post-launch hot-fix window                           QUEUED
M16       Additional security hardening                       QUEUED
```

No provider program starts automatically.

---

## 9. M5 Claude Code program sequence

```text
M5-B0
→ M5-G1
→ M5-SETUP-G1 only when installation/login is missing
→ M5-G2 after source GO / CONDITIONAL GO
→ M5-G3
→ M5DBG-G1
→ M5A-G1
→ M5ADBG-G1
→ M5-CLOSE-G1
```

Conditional alternate route:

```text
M5-G1 local source NO-GO or no usable quota windows
→ Founder decision
→ M5-WEB-G1 account-web fallback dossier
```

M5-WEB-G1 does not start automatically.

### M5-B0 — Post-M4 baseline and source installation

- verify exact M4-N commit and clean state;
- create `codex/uma-m5-claude`;
- create `/Users/juliushe/Developer/UMA-M5-Claude`;
- install Logic 1.5, Scroll 2.1, M5 Plan, and M5 Goals;
- make no runtime change.

### M5-G1 — Claude local source admission dossier

Prove:

- official Claude Code CLI presence/version/signature;
- provider-managed authentication mode;
- current settings hierarchy;
- status-line source behavior;
- five-hour/seven-day field availability;
- privacy allowlist;
- reversible configuration;
- GO / CONDITIONAL GO / NO-GO / SETUP REQUIRED.

### M5-SETUP-G1 — Official CLI installation and login checkpoint

Only when required:

- install Claude Code through the official current installer after explicit authorization;
- Human completes official browser login;
- no API key or setup token;
- no credential enters DEV or UMA;
- capture only sanitized capability evidence.

### M5-G2 — Reversible relay and connector

Implement:

```text
Claude status-line JSON
→ strict allowlist relay
→ local Unix socket
→ Claude connector
→ registry/store
```

Preserve existing status-line output and exact restore.

### M5-G3 — Main-panel live and package acceptance

- receive a real provider-generated local status-line event;
- show Claude as an independent main-panel Agent;
- compare sanitized relay data with UMA presentation;
- preserve Codex and WorkBuddy;
- create a commit-exact package.

### M5DBG-G1 — Three-provider main-app debugging

Stress source lifecycle, relay repair, event bursts, stale/failure states, resources, and package privacy.

### M5A-G1 — Claude in Desktop Assistant

Consume the accepted shared Claude presentation only.

### M5ADBG-G1 — Combined closeout

Prove main/Assistant parity, lifecycle, resources, accessibility, and commit-exact provenance.

### M5-CLOSE-G1 — Current-source update

Update current provider status and close M5 without starting M6.

---

## 10. Claude Code source decision boundary

The current official status-line contract provides a strong source candidate:

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
```

Each window may be independently absent.

`rate_limits` may be absent before the first provider response or for unsupported accounts/authentication modes.

M5 admission requires:

1. official CLI installed and trusted;
2. provider-managed login usable;
3. no active API-key-based UMA route;
4. official status-line JSON observed;
5. at least one valid quota window;
6. strict rejection of transcript, session, workspace, and identity fields;
7. no raw payload persistence;
8. no UMA network request;
9. reversible existing-status-line preservation;
10. no synthetic provider task initiated by UMA.

M5 does not use:

- `ANTHROPIC_API_KEY`;
- `CLAUDE_CODE_OAUTH_TOKEN`;
- `claude setup-token`;
- `apiKeyHelper`;
- transcript files;
- Claude private credential stores;
- account-web login unless the conditional fallback dossier is separately authorized.

---

## 11. Roadmap interpretation rules

### 11.1 One active milestone

Only one implementation milestone may be active unless the Founder explicitly authorizes parallel work.

### 11.2 Local source first

Every provider program begins with a local-source dossier.

### 11.3 Login fallback second

A provider-controlled account login is considered only after local-source NO-GO or proven metric insufficiency.

### 11.4 Main app first, Assistant second

The Desktop Assistant never creates provider transport, login, WebView, relay, timer, or connector.

### 11.5 Visible-provider count controls density

```text
visible providers <= 4
→ Regular or user-selected Minimalist allowed

visible providers > 4
→ forced Minimalist
```

Adding a roadmap slot does not force Minimalist while that provider remains hidden.

### 11.6 Provider-native units

- Codex percentages remain percentages.
- Claude quota remains remaining percentage.
- WorkBuddy Credits remain Credits.
- Missing is not zero.
- Unlimited is not 100%.
- Stale is not current.

### 11.7 No manual quota substitute

No source failure may trigger manual entry, local deduction, or inferred balance.

### 11.8 Remote delivery remains separate

Local commits may be authorized by exact Goals.

Push, merge, tag, release, signing, notarization, publication, and deployment require separate authority.

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

A provider appears only after a current successful admitted read or a provider-contract-approved explicit stale state.

### 12.3 Maximum Decrement

Percentage-provider window selection is centralized. Refill increases and expired epochs do not win.

### 12.4 Status and quota are separate

A provider can have:

```text
healthy source + low quota
```

### 12.5 Agent Settings

Per-Agent settings:

- use stable IDs;
- persist across relaunch;
- remain available while hidden;
- fail closed on future schema;
- contain no external API-key field.

### 12.6 Privacy

Do not collect or retain:

- passwords;
- external API keys or tokens;
- exported cookies;
- account identity unless explicitly required and minimized;
- conversation/task content;
- source code;
- transcript files;
- private databases;
- raw provider payloads;
- full argv or environment dumps.

### 12.7 Source transparency

Every provider Settings page must disclose:

- exact source type;
- login requirement;
- credentials visible to UMA;
- data retained;
- UMA network behavior;
- update behavior;
- disable/disconnect action.

---

## 13. Open nonblocking work

The following do not block M5 source admission:

- remote `main` does not yet include the local M4-N closeout commit;
- README/public product wording may remain stale;
- PR #2 should eventually be closed as superseded;
- co-builder PR #5 needs a collaboration decision;
- remote CI is limited or absent;
- the installed app is ad-hoc signed;
- no notarized GitHub Release exists;
- exact Anthropic Serif is not bundled.

Do not mix these into the Claude connector unless they directly block M5.

---

## 14. Risk register

| ID | Risk | Status | Handling |
|---|---|---|---|
| R-01 | M4-N closeout not on remote main | Open operational risk | M5-B0 verifies exact local parent; later controlled integration |
| R-02 | Claude CLI absent | Expected possible blocker | M5-G1 returns SETUP REQUIRED; M5-SETUP handles official install/login |
| R-03 | Claude status-line rate limits absent for current account | Conditional | Local NO-GO or partial GO; optional login fallback dossier by Founder decision |
| R-04 | Existing Claude status line may be complex | Conditional | Exact backup, wrapper preservation, restore; stop on unsafe command |
| R-05 | Managed settings may block status-line changes | External | Report precise managed-policy blocker; do not bypass |
| R-06 | Raw status payload contains private fields | Controlled | Strict allowlist before socket publication; no persistence |
| R-07 | WorkBuddy page may change | Accepted product risk | Versioned extractor and fail-closed behavior |
| R-08 | Account-web fallback increases privacy surface | Controlled | Local-first gate, nonpersistent default, exact route/field allowlist |
| R-09 | No notarized release | Distribution blocker only | Separate Release Mode |
| R-10 | Provider count pressure may encourage weak sources | Product risk | Do not trade source quality for card count |

---

## 15. Required progress-update format

After every accepted major Goal, update the current-state block with:

```text
Current milestone:
Latest accepted local commit:
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
Install the Logic 1.5 / Scroll 2.1 / M5 source set
→ create the M5 worktree from accepted M4-N closeout commit
→ run M5-G1 Claude Code local source admission
→ use only official CLI/status-line evidence
→ if CLI or login is missing, run M5-SETUP-G1 after Human authorization
→ do not implement an account-web fallback unless the local route returns NO-GO and the Founder explicitly activates M5-WEB-G1
→ do not request or store any Anthropic API key or token
```

---

## Appendix A — Status legend

| Marker | Meaning |
|---|---|
| `DONE` | Accepted with claim-matched evidence |
| `ACTIVE` | Current authorized execution |
| `NEXT` | Immediate next program, not yet executing |
| `QUEUED` | Ordered but not authorized to start |
| `CONDITIONAL` | Requires a source, setup, or explicit Founder gate |
| `DEFERRED` | Valid future route, not current |
| `UNSUPPORTED` | No admitted source under current policy |
| `BLOCKED` | Cannot continue until a defined external gate closes |
| `RELEASED` | Published through an authorized release channel |

---

## Appendix B — Current governing source set

```text
UMA_Logic_1.5.md
Scroll_2.1.md
M5_Plan.md
M5_Goal.md
UMA_0.11_closeout.md
Goal_Mode_2.0.md
accepted M4-N closeout records
```

Historical:

```text
Scroll 2.0
UMA Logic 1.4
M4 Plan / Goals
M3 Plan / Goals
UMA Logic 1.3.1
M2W Plan / Goals
DEV 3 shift report
older QA ledgers and packages
```

---

## Appendix C — Official Claude Code source references

Retrieved 2026-07-28:

```text
https://code.claude.com/docs/en/statusline
https://code.claude.com/docs/en/authentication
https://code.claude.com/docs/en/installation
https://code.claude.com/docs/en/settings
https://code.claude.com/docs/en/commands
```

Current live official documentation remains authoritative over this snapshot.
