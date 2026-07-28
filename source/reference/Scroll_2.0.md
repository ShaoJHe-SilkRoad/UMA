# UMA Development Scroll 2.0

**Document type:** Master product-development sequence and progress ledger  
**Version:** 2.0  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Canonical remote branch:** `main`  
**Current canonical main commit:** `469be4d6cf411a89401c2341807a57aef176d852`  
**UMA 0.11 main-history integration commit:** `ff6553943280836fb0d3db5289f85b163c41c1a3`  
**Qualified UMA 0.11 development commit:** `459ea1321817e391ba80fe79f19edb0352fc76cb`  
**Current installed Founder build:** `/Users/juliushe/Desktop/UMA_0.11.app`  
**Current version/build:** `0.11 / 202607270003`  
**Current milestone:** `M4 — Manus Official API v2 Integration`  
**Status:** Active governing roadmap; replaces Scroll 1.2 and all earlier Scroll variants

---

## 0. Current-state summary

```text
UMA 0.11 local implementation                DONE
UMA 0.11 final qualification                 DONE
Founder Desktop installation                 DONE
Feature branch push                          DONE
Founder main integration                     DONE through PR #3
Public GitHub Release                        NOT STARTED
Apple notarization                           NOT STARTED
Current production-capable providers         Codex + WorkBuddy
Claude Code                                  DEFERRED
Next provider program                        Manus
```

The current development line is no longer waiting for the UMA 0.11 merge. The qualified 0.11 tree was integrated into the Founder repository through a clean main-history integration commit and merged by pull request #3.

The immediate next product program is Manus integration, starting with its official API v2 usage source and secure credential boundary. Manus implementation must not begin by scraping the desktop application or web UI.

---

## 1. Purpose

This Scroll defines:

- the canonical current baseline;
- the accepted product state;
- the current provider set;
- the next provider sequence;
- the relationship between source admission, connector implementation, main-panel acceptance, Desktop Assistant integration, and debug closeout;
- the threshold at which the Assistant is forced into Minimalist mode;
- release and productization stages after provider expansion;
- the documents that are current versus historical.

It is a sequencing and status contract. A provider name appearing in this Scroll does not mean that the provider is already supported.

---

## 2. Source authority

Use this priority:

```text
Current Founder instruction
→ current live GitHub/main evidence
→ latest accepted DEV execution report
→ current accepted package/runtime evidence
→ UMA Logic 1.4
→ Goal Mode 2.0
→ this Scroll 2.0
→ active milestone Plan and Goals
→ historical plans, reports, screenshots, and packages
```

Important consequences:

1. The DEV 3 shift report is the primary historical handoff, but its statement that no pull request was merged is superseded by current GitHub evidence.
2. The qualified development commit remains important for provenance, but `main` is now the canonical development starting point.
3. `UMA_Logic_1.3.1.md` is historical after Logic 1.4 is installed.
4. `M3_Plan.md`, `M3_Goal.md`, `M2W_Plan.md`, and `M2W_Goals.md` remain useful development history, not active execution authority.
5. The earlier M4 pre-release/readiness proposal is superseded by the Founder’s current direction to proceed with Manus integration.
6. A current live repository read always outranks a hard-coded commit in this document when `main` has legitimately advanced. Any advancement must be inspected rather than silently accepted.

---

## 3. Canonical baseline

### 3.1 Git lineage

```text
Qualified development source:
459ea1321817e391ba80fe79f19edb0352fc76cb
fix(uma): close 0.11 multi-agent defects

Main-history integration:
ff6553943280836fb0d3db5289f85b163c41c1a3
feat: integrate UMA 0.11 multi-agent monitor

Merged main:
469be4d6cf411a89401c2341807a57aef176d852
Merge pull request #3 from codex/uma-0.11-main-integration
```

Interpretation:

- `459ea132...` is the commit-exact qualified development source.
- `ff655394...` applies the qualified 0.11 tree on top of the prior Founder `main` history.
- `469be4d6...` is the merge commit currently making 0.11 canonical on `main`.
- No force push or unrelated-history merge was required.

### 3.2 GitHub state

```text
Founder repository:
ShaoJHe-SilkRoad/UMA

Default branch:
main

PR #3:
MERGED — canonical UMA 0.11 integration

PR #2:
OPEN — superseded development-line PR; administrative cleanup only

Co-builder PR #5:
OPEN / NOT MERGEABLE — optional upstream collaboration, not a Founder product blocker
```

Closing or replacing PR #2 and deciding the disposition of co-builder PR #5 are repository-hygiene decisions. They do not block M4.

### 3.3 Qualified package

```text
Qualified package:
/private/tmp/uma-0.11-dbg-final-459ea1321817/UMA.app

Version:
0.11

Build:
202607270003

Bundle ID:
com.kevinchen.CodexUsageMonitor

Architecture:
arm64

Minimum macOS:
14.0
```

### 3.4 Installed Founder build

```text
Current:
 /Users/juliushe/Desktop/UMA_0.11.app

Backup:
 /Users/juliushe/Desktop/UMA_0.11.backup-20260727-213223.app

Historical reference:
 /Users/juliushe/Desktop/UMA_0.10.1.app
```

No M4 task may replace or modify these applications without a new explicit installation instruction.

---

## 4. Accepted progress

### 4.1 Foundation and source recovery

```text
M1A Codex stability                           DONE
M2 Desktop Assistant                         DONE
M2DBG / M2A / M2ADBG                         DONE
P0.10.1 UI/settings/package corrections      DONE
R0 source reconstruction                     DONE
```

### 4.2 Claude investigation

```text
Claude Code capability investigation         DONE
Official CLI/source on current Mac            NOT AVAILABLE
Production connector                         DEFERRED
Current surface status                        HIDDEN
```

Claude is not a blocker for Manus. Claude may be reassessed later only after the official Claude Code CLI or another admitted source is present.

### 4.3 WorkBuddy program

```text
Provider-neutral Credit model                DONE
Manual WorkBuddy source                      DONE as compatibility infrastructure
Main-panel WorkBuddy                         DONE
Desktop Assistant WorkBuddy                  DONE
Fractional Credit support                    DONE
Local-live provider admission                DONE
Login assistance                             DONE
Authenticated Account Web Sync               DONE
All-pool Credit aggregation                  DONE
One-minute Auto Refresh                      DONE
Combined stability/qualification             DONE
```

The production WorkBuddy source is Account Web Sync. The manual record is retained but is not a live fallback.

### 4.4 UMA 0.11 multi-Agent product

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
Typography fallback                          DONE
Main/Assistant parity                        DONE
Final DBG                                    DONE
Main merge                                   DONE
```

### 4.5 Final verification inherited from DEV 3

```text
Focused repair tests                         54/54 PASS
Full suite                                   308/308 PASS across 38 suites
Debug build                                  PASS
Release build                                PASS
Strict-concurrency Release                   PASS
Live Codex                                   PASS
Live WorkBuddy                               PASS
WorkBuddy read coalescing                    PASS
45-minute endurance                          PASS
Appearance/accessibility/localization        PASS
Package privacy/provenance                   PASS
```

These results prove the qualified 0.11 development tree. M4 must preserve them proportionally and rerun affected tests rather than assuming all old evidence automatically covers new code.

---

## 5. Current accepted user value

UMA currently provides:

- one native macOS menu-bar host application;
- one status item;
- one compact multi-Agent main panel;
- one optional floating Desktop Assistant;
- equal Codex and WorkBuddy cards;
- independent Agent details and Agent Settings;
- shared main-panel/Assistant presentation truth;
- Codex remaining-limit monitoring;
- Codex recent tasks and API-equivalent cost details;
- WorkBuddy exact all-pool Credits;
- WorkBuddy Account Web Sync;
- WorkBuddy one-minute Auto Refresh and Manual-only mode;
- persistent per-Agent settings;
- manual first Agent search and optional later Auto Search;
- Light, Dark, transparency, contrast, motion, VoiceOver, English, and Simplified Chinese support;
- package-safe typography and glass.

UMA does not yet provide:

- Manus Credits;
- Claude Code usage;
- Cursor, Kimi+, Doubao, or other later-provider usage;
- a notarized public release;
- a stable 1.0 distribution channel.

---

## 6. Current provider status

| Priority | Provider | Current source | Native value | Status | Surface state |
|---:|---|---|---|---|---|
| 1 | Codex | Local `codex app-server --stdio` plus approved local session-log reads | Remaining percentage; token/cost details | Live-qualified | Visible after current successful read |
| 2 | Claude Code | No admitted source on current Mac | Unknown | Deferred | Hidden |
| 3 | WorkBuddy | Isolated authenticated Account Web Sync | Exact Credits | Live-qualified | Visible after complete current all-pool read |
| 4 | Manus | Official API v2 source candidate: `usage.availableCredits` | Exact Credits | M4 NEXT / conditional admission | Hidden until implementation and successful read |
| 5 | Cursor | No admitted source | Unknown | Not started | Hidden |
| 6 | Kimi+ | No admitted source | Unknown | Not started | Hidden |
| 7 | Doubao | No admitted source | Unknown | Not started | Hidden |
| 8 | Approved emerging slot | Not frozen | Unknown | Not started | Hidden |

Provider priority is stable registry order. Hidden providers reserve no visual space.

WorkBuddy and CodeBuddy share one Credit scope and must not appear as duplicate balances.

---

## 7. Revised master sequence

```text
M1A       Codex stability                                      DONE
M2        Desktop Assistant                                    DONE
M2DBG     Assistant shell debugging                            DONE
M2A       Production Codex Assistant binding                   DONE
M2ADBG    Main + Assistant closeout                            DONE
P0.10.1   UI/settings/package correction                       DONE

R0        Source reconstruction                                DONE
M3-C      Claude capability investigation                      DONE / DEFERRED
M2W       WorkBuddy Credit and manual-source foundation        DONE
M2W-LIVE  WorkBuddy Account Web Sync                           DONE
M2W-R1    WorkBuddy one-minute Auto Refresh                    DONE
STAB      0.10.1 stability and 0.11 preparation                DONE
UMA011    Multi-Agent architecture, visual system, final DBG   DONE
GIT011    Founder main integration                             DONE

M4        Manus official API v2 integration                    NEXT
M4DBG     Codex + WorkBuddy + Manus main-app debugging         QUEUED
M4A       Manus in Desktop Assistant                           QUEUED
M4ADBG    Three-admitted-provider combined closeout            QUEUED

M5        Cursor source admission and integration              QUEUED
M5DBG     Affected-provider main-app debugging                 QUEUED
M5A       Cursor in Desktop Assistant                          QUEUED
M5ADBG    Combined closeout                                    QUEUED

M6        Kimi+ source admission and integration               QUEUED
M6A/DBG   Kimi+ combined acceptance                            QUEUED

M7        Doubao and frozen emerging-provider set              QUEUED
M7A/DBG   Up-to-approved-provider combined acceptance          QUEUED

M8        Product feedback narrow fixes, round 1               QUEUED
M8DBG     Regression/stability                                 QUEUED
M9        Desktop Assistant daily-use/aesthetic optimization   QUEUED
M10       Product formation and release qualification         QUEUED
M10A      Product feedback round 2                             QUEUED
M10ADBG   Release-candidate closure                            QUEUED
M11       Stable 1.0 release                                   QUEUED
M12       Post-launch hot-fix window                           QUEUED
M13       Additional security hardening                       QUEUED
```

Claude reassessment is a separate deferred route. It does not automatically retake priority over the Founder-selected Manus program.

---

## 8. M4 program sequence

```text
M4-B0
→ M4-G1
→ M4-G2 only after source GO / CONDITIONAL GO
→ M4-G3
→ M4DBG-G1
→ M4A-G1
→ M4ADBG-G1
→ M4-CLOSE-G1
```

### M4-B0 — Canonical merged-main baseline and source installation

- start from current `origin/main`;
- create a durable `codex/uma-m4-manus` worktree;
- install the current governing source set;
- optionally install the official Manus API documentation skill for Codex;
- make no runtime change.

### M4-G1 — Manus source admission and secret-boundary dossier

Investigate and prove:

- official API v2 availability;
- `usage.availableCredits`;
- field semantics;
- API-key-only authentication;
- secure local Keychain storage;
- request cadence and error behavior;
- personal/team scope limitations;
- GO / CONDITIONAL GO / NO-GO.

No production connector is completed in this Goal.

### M4-G2 — Secure Manus Credits connector

After admission:

- add Keychain-backed API-key configuration;
- add a narrow API client;
- decode only approved Credit fields;
- publish a provider-neutral Credit snapshot;
- add deterministic settings, disconnect, and failure handling;
- use fixtures and no real key in Codex logs.

### M4-G3 — Main-panel live and package acceptance

- Human enters the API key directly into the candidate app;
- perform bounded read-only live validation;
- display Manus as an independent Agent card;
- keep exact Credits and source scope honest;
- produce a commit-exact package.

### M4DBG-G1 — Three-provider main-app debugging

Prove Codex, WorkBuddy, and Manus coexist independently.

### M4A-G1 — Manus in Desktop Assistant

Consume the shared Manus presentation only. The Assistant owns no key, API client, timer, or cache.

### M4ADBG-G1 — Combined closeout

Prove main/Assistant parity, credential safety, cadence, resources, package privacy, and commit-exact provenance.

### M4-CLOSE-G1 — Current-source update

Update Scroll, Logic, Provider Matrix, and the M4 closeout without starting another provider.

---

## 9. Manus source decision boundary

Current official documentation provides a strong source candidate:

```text
GET https://api.manus.ai/v2/usage.availableCredits
Header: x-manus-api-key
```

The endpoint documents an authoritative `total_credits` value plus component fields and refresh metadata.

This is not yet a shipped UMA source.

M4 admission requires:

1. official endpoint and schema remain current;
2. an API key can be created through the official Manus interface;
3. the key can be stored in macOS Keychain without exposure to Codex, logs, UserDefaults, or Git;
4. one current successful read works on the Founder account;
5. `total_credits` is confirmed as the spendable balance;
6. missing/optional fields fail safely;
7. request cadence is bounded;
8. account/task identity is not collected;
9. no task is created and no Credits are consumed for validation.

M4 must not use:

- desktop UI scraping;
- web DOM scraping;
- browser-cookie import;
- Keychain extraction by DEV;
- private databases;
- process memory;
- task creation to infer usage;
- task history as the primary balance source.

---

## 10. Roadmap interpretation rules

### 10.1 One active milestone

Only one implementation milestone may be active unless the Founder explicitly authorizes parallel work.

### 10.2 Source admission first

Every provider program follows:

```text
official-source dossier
→ admission decision
→ connector implementation
→ main-panel live/package acceptance
→ main-app debugging
→ Assistant adapter
→ combined debugging
→ closeout
```

No acceptable source means no production connector.

### 10.3 Main app first, Assistant second

The Desktop Assistant never creates provider transport.

### 10.4 Visible-provider count controls density

The forced-Minimalist rule depends on the number of currently visible admitted providers, not the roadmap priority number.

```text
visible providers <= 4
→ Regular or user-selected Minimalist allowed

visible providers > 4
→ forced Minimalist
```

If Claude remains hidden, adding Manus does not by itself create four visible providers.

### 10.5 Provider-native units

- Codex percentages remain percentages.
- WorkBuddy Credits remain Credits.
- Manus Credits remain Credits.
- No fake percent is created from an absolute Credit balance.
- Missing is not zero.
- Unlimited is not 100%.
- Stale is not current.

### 10.6 Remote delivery remains separate

Local commits may be authorized by exact Goals.

Remote push, merge, tag, release, signing, notarization, publication, and deployment require separate current authority.

---

## 11. Cross-milestone product contracts

### 11.1 One-host architecture

```text
registered provider catalog
→ source admission
→ one connector per admitted provider
→ one serialized UsageStore
→ one shared presentation policy
├── main panel
└── Desktop Assistant
```

### 11.2 Current-read admission

A provider appears only after a current successful read through an admitted source.

Last-valid data may be retained internally for recovery, but it is not shown as current after admission is withdrawn unless the provider contract explicitly exposes an honest stale state.

### 11.3 Maximum Decrement

Percentage-provider window selection is centralized.

Refill increases do not win decrement selection.

Expired reset epochs cannot win.

Credit providers do not use this window selector.

### 11.4 Status and quota are separate

A provider can have:

```text
healthy source + low quota
```

Connection/auth/source indicators do not change merely because quota is low.

### 11.5 Agent Settings

Per-Agent settings:

- use stable provider IDs;
- persist across relaunch;
- remain available while the provider is inactive;
- fail closed on an unsupported future schema;
- never store raw credentials in normal preference storage.

### 11.6 Privacy

Do not collect or retain:

- passwords;
- API keys outside Keychain;
- raw tokens;
- cookies exported to app logic;
- account identity unless explicitly required and safely minimized;
- conversation/task content;
- source code;
- private provider databases;
- raw provider payloads in Git;
- full process argv or environment dumps.

---

## 12. Open nonblocking work

The following remain open but do not block M4 source admission:

- the Founder repository README/public product wording may still be stale;
- PR #2 should eventually be closed as superseded;
- co-builder PR #5 needs an upstream-collaboration decision;
- remote CI is limited or absent;
- the installed app is ad-hoc signed;
- no notarized GitHub Release exists;
- exact Anthropic Serif is not bundled.

These should be handled through narrow documentation, CI, collaboration, or Release Mode tasks rather than mixed into the Manus connector.

---

## 13. Required progress-update format

After each accepted major Goal, update this Scroll header or current-state block with:

```text
Current milestone:
Latest accepted main/branch commit:
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

## 14. Immediate next action

```text
Install the DEV 4 governing source pack
→ create a clean M4 branch/worktree from merged origin/main
→ install the official Manus API documentation skill for Codex
→ run M4-G1 source-admission and secret-boundary dossier
→ do not request or expose the Founder’s Manus API key in Codex
→ do not implement the connector until M4-G1 returns GO or CONDITIONAL GO
```

---

## Appendix A — Status legend

| Marker | Meaning |
|---|---|
| `DONE` | Accepted with claim-matched evidence |
| `ACTIVE` | Current authorized execution |
| `NEXT` | Immediate next program, not yet executing |
| `QUEUED` | Ordered but not authorized to start |
| `CONDITIONAL` | Requires an explicit source/admission gate |
| `DEFERRED` | Valid future route, not current |
| `BLOCKED` | Cannot continue until a defined external gate closes |
| `RELEASED` | Published through an authorized release channel |

---

## Appendix B — Current governing source set

```text
Scroll_2.0.md
UMA_Logic_1.4.md
UMA_0.11_closeout.md
Provider_Status_Matrix.md
M4_Plan.md
M4_Goal.md
Source_Reference_Manifest.md
```

Historical references remain available but are not active authority:

```text
Scroll 1.2
UMA Logic 1.3.1
M3 Plan / Goals
M2W Plan / Goals
DEV 3 shift report
older QA ledgers and scope locks
```

---

## Appendix C — Official Manus source references for M4

Retrieved 2026-07-28:

```text
https://open.manus.im/docs/v2/introduction
https://open.manus.im/docs/v2/authentication
https://open.manus.im/docs/v2/usage.availableCredits
https://open.manus.im/docs/v2/usage.list
https://open.manus.im/docs/v2/rate-limits
https://open.manus.im/docs/v2/manus-api-skill
https://manus.im/help/credits
```

Current live documentation remains authoritative over this snapshot.
