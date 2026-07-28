# UMA 0.11 Closeout

**Document type:** Milestone and release-line closeout  
**Version:** 1.0  
**Date:** 2026-07-28  
**Product:** UMA — Usage Monitor Altoget  
**Milestone:** UMA 0.11 Multi-Agent Monitor  
**Verdict:** `PASS — IMPLEMENTED, QUALIFIED, INSTALLED, AND MERGED TO FOUNDER MAIN`  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Canonical main commit:** `469be4d6cf411a89401c2341807a57aef176d852`  
**Qualified development commit:** `459ea1321817e391ba80fe79f19edb0352fc76cb`  
**Main-history integration commit:** `ff6553943280836fb0d3db5289f85b163c41c1a3`  
**Version/build:** `0.11 / 202607270003`  
**Installed Founder application:** `/Users/juliushe/Desktop/UMA_0.11.app`

---

## 0. Closeout statement

UMA 0.11 is complete for its accepted scope.

The product moved from a Codex-centered menu-bar monitor into a qualified multi-Agent architecture with two production-capable providers:

```text
Codex
+
WorkBuddy
```

The final accepted development tree passed deterministic, live, package, privacy, accessibility, appearance, and bounded endurance validation. That tree was then applied to the Founder repository’s existing `main` history through a non-destructive integration commit and merged by pull request #3.

UMA 0.11 is therefore no longer a feature-branch-only product.

It is now the canonical source on Founder `main`.

This closeout does not claim:

- public release;
- Apple notarization;
- stable 1.0;
- Claude Code support;
- Manus support;
- co-builder upstream merge.

---

## 1. Provenance and Git lineage

### 1.1 Qualified development source

```text
Workspace:
/Users/juliushe/Developer/UMA-0.11-MultiAgent

Branch:
codex/uma-0.11-multiagent

Final qualified commit:
459ea1321817e391ba80fe79f19edb0352fc76cb

Final qualified tree:
deb62b6420b3528583e26235cfabcf3060933ada

Commit subject:
fix(uma): close 0.11 multi-agent defects
```

### 1.2 Main-history integration

The original development branch had reconstructed history and did not merge directly into the existing Founder `main`.

A dedicated integration branch was created from the prior `main`, and the complete qualified 0.11 tree was applied as one integration commit:

```text
Integration commit:
ff6553943280836fb0d3db5289f85b163c41c1a3

Commit subject:
feat: integrate UMA 0.11 multi-agent monitor
```

The integration preserved:

- prior Founder main history;
- the complete qualified 0.11 source tree;
- no force push;
- no unrelated-history merge;
- no rewrite of accepted commits.

### 1.3 Canonical merge

```text
Pull request:
ShaoJHe-SilkRoad/UMA #3

State:
MERGED

Merge commit:
469be4d6cf411a89401c2341807a57aef176d852
```

### 1.4 Superseded and optional pull requests

```text
Founder PR #2:
still open
superseded by PR #3
not a current product blocker

Co-builder PR #5:
open
not mergeable
optional upstream collaboration
not a Founder product blocker
```

PR #2 may be closed with a short note pointing to PR #3 after the Founder chooses to perform repository cleanup.

PR #5 requires an upstream collaboration decision and may remain open, be narrowed, or be closed separately.

---

## 2. Qualified package

```text
Package:
/private/tmp/uma-0.11-dbg-final-459ea1321817/UMA.app

Marketing version:
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

Hashes recorded by DEV 3:

```text
Executable SHA-256:
88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a

Source archive SHA-256:
810a10e96d70a1db76b759caac47c948b045aa0e4623df67bacec3a35ac9ce51

Package manifest SHA-256:
994c8fdcb79d8ed58678b66cdd76fbd825e9b7ea8b2c817ca61e48d381b25dcc
```

---

## 3. Installed Founder application

```text
Current application:
/Users/juliushe/Desktop/UMA_0.11.app

Version/build:
0.11 / 202607270003

Backup:
/Users/juliushe/Desktop/UMA_0.11.backup-20260727-213223.app

Historical reference:
/Users/juliushe/Desktop/UMA_0.10.1.app
```

The current installed application was smoke-tested from its exact Desktop path.

This closeout does not authorize later tasks to replace it.

---

## 4. Delivered product scope

### 4.1 Multi-Agent architecture

Delivered:

- one host application;
- one status item;
- one connector registry;
- one connector instance per provider;
- one serialized UsageStore;
- one shared presentation policy;
- provider-independent state and failure isolation;
- main-panel/Desktop Assistant parity.

### 4.2 Main panel

Delivered:

- compact provider-neutral UMA header;
- equal Codex and WorkBuddy Agent cards;
- independent Agent details;
- independent Agent Settings;
- Show All / Hide All;
- stable provider ordering;
- current-admission filtering;
- no global combined percentage;
- compact footer.

### 4.3 Agent discovery and preferences

Delivered:

- first Agent search is manual;
- later Auto Search is optional;
- only registered providers are scanned;
- per-Agent settings persist across relaunch;
- settings persist while a provider is inactive;
- future unsupported setting schema fails closed;
- stored settings apply when the provider becomes available later.

### 4.4 Selected-window policy

Delivered:

- one centralized Maximum Decrement result;
- remaining-only percentages;
- refill increases do not win;
- expired quota epochs do not win;
- depleted and critical overrides;
- deterministic tie handling;
- obsolete or unlimited five-hour Codex data remains secondary;
- all UI surfaces consume the same selected-window output.

### 4.5 Codex

Delivered:

- current limit/account reads;
- current selected percentage window;
- Recent Tasks inside Codex details;
- Token Cost inside Codex details;
- reset-credit details;
- child recovery;
- existing authenticated Codex session reuse;
- local-only session-log cost estimation.

### 4.6 WorkBuddy

Delivered:

- provider-native exact Credits;
- fractional Decimal support;
- authenticated Account Web Sync;
- isolated UMA-owned official WorkBuddy session;
- complete subscription, add-on, and benefit/gift aggregation;
- exact all-pool balance;
- atomic current observation;
- one-minute Auto Refresh default ON;
- Manual-only mode;
- Sync Now;
- Check Again;
- disconnect;
- auth-expiry suspension;
- no manual or stale current fallback;
- WorkBuddy.app not required.

### 4.7 Desktop Assistant

Delivered:

- Regular and Minimalist modes;
- same provider set as the main panel;
- stable provider-native values;
- position restore;
- Always on Top;
- no focus stealing during ordinary display;
- no provider client, timer, scanner, WebView, or private cache owned by the Assistant;
- zero-provider shell suppression;
- forced Minimalist when more than four providers are visible.

### 4.8 Visual system

Delivered:

- one visible contour owner;
- medium-transparency glass;
- removal of nested full-shell glass;
- no duplicate borders;
- no Dark Mode white slab;
- public macOS APIs;
- Light/Dark;
- Reduce Transparency;
- Increase Contrast;
- Reduce Motion;
- system-serif Latin typography;
- native CJK fallback;
- tabular numeric values.

---

## 5. Final verification

### 5.1 Tests and builds

```text
Focused repair suite:
54/54 PASS

Full suite:
308/308 PASS across 38 suites

Debug:
PASS

Release:
PASS

Strict-concurrency Release:
PASS
```

### 5.2 Live evidence

```text
Live Codex:
PASS

Live WorkBuddy:
PASS

WorkBuddy Auto Refresh:
PASS

Read coalescing:
PASS

Current provider parity:
PASS
```

Historical acceptance observations included:

```text
Codex:
36% remaining, seven-day selected

WorkBuddy:
6,302.88 Credits
Minimalist: 6.3k
```

These values are historical evidence only. They are not runtime constants or future live test oracles.

### 5.3 Endurance

```text
Duration:
45 minutes

Samples:
46 one-minute samples

Average CPU:
12.30%

RSS:
49,232–150,272 KiB

File descriptors:
106–118

Threads:
8–13

Owned Codex children:
exactly one per sample
```

### 5.4 Lifecycle matrix

Passed:

- 100 Assistant show/hide cycles;
- 50 main-panel cycles;
- 30 Settings cycles;
- 30 Agent Settings navigation cycles;
- 20 Show All / Hide All cycles;
- 20 density transitions;
- 10 Auto/manual transitions;
- 10 Always-on-Top transitions;
- position restoration;
- off-screen frame repair;
- Codex child recovery;
- WorkBuddy sync;
- clean shutdown;
- no resource multiplication.

### 5.5 Appearance and accessibility

Passed:

- Light;
- Dark;
- Reduce Transparency;
- Increase Contrast;
- Reduce Motion;
- English;
- Simplified Chinese;
- keyboard;
- VoiceOver;
- Settings scrolling;
- compact and expanded presentation.

### 5.6 Package and privacy

Passed:

- deep ad-hoc signature validation;
- expected architecture;
- system-only dependencies;
- bounded package allowlist;
- no provider sessions;
- no browser cookies;
- no tokens;
- no raw provider snapshot;
- no manual record;
- no fixtures/tests/logs/screenshots;
- no copied Anthropic/Claude font.

---

## 6. Source reconstruction and truthfulness

The earlier accepted source commit became unavailable.

DEV 3 created a truthful reconstructed successor rather than claiming the missing commit had been recovered.

The final 0.11 line therefore has two distinct provenance concepts:

```text
historical development continuity
+
current qualified source-tree truth
```

The current `main` integration preserves the usable product and current source tree without falsifying the missing historical object.

Future documentation must not claim that the unrecovered historical commit was restored.

---

## 7. Provider closeout status

| Provider | 0.11 result |
|---|---|
| Codex | Production-capable and live-qualified |
| WorkBuddy | Production-capable and live-qualified |
| Claude Code | Source investigation complete; deferred |
| Manus | Not started in 0.11 |
| Cursor | Not started |
| Kimi+ | Not started |
| Doubao | Not started |

WorkBuddy and CodeBuddy share one Credit scope. UMA must not duplicate the same balance as two providers.

---

## 8. Accepted limitations

### 8.1 Not publicly released

The app is:

- locally installed;
- ad-hoc signed;
- not notarized;
- not a stable GitHub Release asset;
- not an App Store/TestFlight product.

This is a distribution limitation, not a failure of 0.11 implementation.

### 8.2 Exact Anthropic Serif unavailable

No verified package-safe Anthropic Serif source was accepted.

UMA uses:

- macOS system serif;
- native CJK fallback;
- tabular numeric typography.

This is accepted and nonblocking.

### 8.3 WorkBuddy source fragility

WorkBuddy Account Web Sync depends on the official web page structure.

Mitigation:

- versioned bounded extractor;
- exact route/domain rules;
- atomic observation;
- fail closed;
- no manual fallback;
- Quick Patch after a reproduced provider-page change.

### 8.4 Remote CI

The final 0.11 result was strongly validated locally. Remote CI coverage is limited or absent.

This remains a repository-quality gap, not a reason to reopen 0.11.

### 8.5 Repository public documentation

Some repository-facing public wording may still describe the older Codex-only product.

This should be corrected through a narrow documentation task and not mixed into provider transport work.

---

## 9. Historical documents retired as active authority

Retain for history:

```text
Scroll 1.2
M3_Plan.md
M3_Goal.md
M2W_Plan.md
M2W_Goals.md
UMA_Logic_1.3.1.md
DEV 3 shift report
older scope locks and QA ledgers
```

Replace active authority with:

```text
Scroll_2.0.md
UMA_Logic_1.4.md
UMA_0.11_closeout.md
Provider_Status_Matrix.md
M4_Plan.md
M4_Goal.md
Source_Reference_Manifest.md
```

Do not delete historical evidence unless separately authorized.

---

## 10. M4 handoff

Founder direction:

```text
Next provider:
Manus
```

Current official documentation identifies a promising read-only source:

```text
GET /v2/usage.availableCredits
Authentication: x-manus-api-key
Primary field: total_credits
```

M4 must begin with:

```text
source admission
+
secure Keychain credential boundary
```

It must not begin with:

- Manus desktop scraping;
- browser scraping;
- task creation;
- usage inference;
- API key pasted into Codex;
- general Manus task automation.

Expected M4 sequence:

```text
M4-B0
→ M4-G1 source admission
→ M4-G2 secure connector
→ M4-G3 main-panel live acceptance
→ M4DBG
→ M4A
→ M4ADBG
→ M4 closeout
```

---

## 11. Closeout decision

```text
UMA 0.11:
CLOSED

Founder main:
CANONICAL

Installed review build:
PRESERVED

Next active program:
M4 Manus Integration

Release/notarization:
SEPARATE

Claude:
DEFERRED

Co-builder upstream merge:
OPTIONAL
```

---

## 12. Completion lock

This closeout authorizes no automatic runtime change.

Do not automatically:

- modify the installed app;
- close PRs;
- push;
- merge;
- tag;
- release;
- notarize;
- begin Manus implementation;
- access a Manus API key.

M4 begins only through an exact accepted Goal.
