# DEV 4 → DEV 5 Shift Change Report

**Project:** Usage Monitor Altoget (UMA)
**Outgoing ChatGPT role:** DEV 4
**Incoming ChatGPT role:** DEV 5
**Date:** 2026-08-08
**Current active program:** M6 — Google Antigravity
**Next provider after M6:** Cursor
**Claude M5:** Frozen pending Apple Developer Program activation

---

## 0. Required reading for DEV 5

Read in this order:

1. `UMA_Handover_ClaudeCode_to_ChatGPT_2026-08-08.md`
2. `M6_Antigravity_Feasibility_Analysis.md`
3. `M6_Plan.md`
4. `M6_Goals.md`
5. this Shift Change report
6. current live Git state
7. `UMA_Logic_1.5.md`
8. `Scroll_2.1.md`
9. `Goal_Mode_2.0.md`
10. `Dev_Default_2.1.md`

Authority:

```text
Current Founder instruction
→ live repository evidence
→ Claude handover
→ M6 current documents
→ current governing principles
→ historical plans/reports
```

Static M5 and Scroll documents contain superseded Claude/status-line assumptions. Do not let them override the accepted live Claude Browser Sync implementation or the current M6 decision.

---

## 1. Executive handoff

DEV 4 completed the provider-direction transition from Manus to Claude and then to Google Antigravity.

Current product truth:

```text
Codex       supported
Claude Code supported locally; signing/distribution pending Apple Developer Program
WorkBuddy   supported
Antigravity next active provider program
Cursor      next after Antigravity
```

Current repository truth:

```text
Workspace : /Users/juliushe/Developer/UMA-M5-Claude
Branch    : codex/uma-m5-claude
HEAD      : c6245f9cc745b3d45f53e115843b3152e84e8c46
Tree      : e3ac2df1d135dad4c85af06611dc05943e8089dd
Worktree  : clean
Index     : empty
```

The branch is local-only. New work must not start from remote `main`.

Immediate next task:

```text
M6-B0
```

---

## 2. Founder product vision

UMA is one native macOS menu-bar product that monitors multiple AI-agent quota systems without controlling the agents.

Core experience:

```text
one app
one status item
one main panel
one optional floating Desktop Assistant
many independent provider connectors
one shared presentation truth
```

### 2.1 Value semantics

- Compact percentages always mean **remaining**, never used.
- Percentage conversion occurs once in shared logic.
- Credit providers retain exact Credits.
- Missing is not zero.
- Unlimited is not 100%.
- Activity, cost, token count, or time may not be converted into account quota.
- No manual balance entry or manual deduction.
- No provider card without a current accepted observation and source dossier.

### 2.2 Selection

Percentage providers use centralized Maximum Decrement.

```text
rawChange = previousRemaining - currentRemaining
decrement = max(0, rawChange)
```

Selection is shared by main panel and Assistant. Views never choose independently.

### 2.3 UI

- Equal provider cards.
- Stable provider order.
- Regular and Minimalist Assistant only.
- More than four visible providers forces Minimalist.
- Light/Dark and macOS glass style.
- Low visual noise, one exterior contour, no unnecessary card layers.
- Main panel holds details; Assistant remains presentation-only.

### 2.4 Privacy and trust

Permanent prohibitions:

- user-entered API keys;
- copied OAuth/setup tokens;
- Keychain credential reads for provider access;
- browser cookie/profile import;
- private provider databases or endpoints as undeclared production sources;
- OCR/Accessibility/UI scraping represented as stable source;
- manual quota;
- quota-consuming refresh tasks;
- raw prompt/response/session retention without a separate contract.

Provider-controlled login is allowed when credentials remain opaque to UMA.

---

## 3. Development chronology

### 3.1 Foundation through UMA 0.11

Completed before DEV 4:

- Codex live connector and app-server usage source;
- multi-provider connector architecture;
- Desktop Assistant shell and production binding;
- WorkBuddy exact Credits model;
- WorkBuddy provider-controlled account-web login;
- WorkBuddy one-minute Auto Refresh;
- shared main/Assistant presentation;
- equal provider cards and independent Settings;
- Maximum Decrement;
- UMA 0.11 multi-Agent qualification and local install.

### 3.2 M4 Manus

M4 investigated Manus.

Progress:

- official API source dossier;
- secure API-key prototype;
- live route not used;
- Founder rejected API-key product entrance;
- local CLI investigation returned NO-GO;
- API-key production code retired;
- M4-G3 WIP removed;
- M4 closed unsupported.

Preference established:

```text
No API-key entry
No manual value/deduction
Local source first
Provider-controlled login may be considered
```

### 3.3 Logic 1.5 transition

Founder allowed provider-controlled login as a compromise after local-source failure, but kept the API-key/token ban.

M5 selected Claude Code.

### 3.4 Initial Claude local/status-line route

M5 originally followed official Claude CLI status-line data.

Completed historically:

- CLI installation and provider login;
- status-line relay and connector;
- 5h/7d used-to-remaining conversion;
- main-panel Claude card;
- Cached/Stale startup behavior;
- Desktop Assistant presentation;
- four-provider-neutral tests at that stage.

Founder then clarified that target users primarily use Claude Desktop, not Terminal.

### 3.5 Claude Desktop local investigation

Results:

- Claude Desktop did not execute the configured status line in the tested path;
- invocation-first probe confirmed no callback;
- embedded WKWebView account login failed Google OAuth compatibility;
- unsandboxed DOM-capable prototype was rejected;
- no credentials were retained.

### 3.6 Rejected Claude Keychain/OAuth broker

Open-source research showed exact Claude quota could be read by reusing provider OAuth credentials.

Founder rejected this design after macOS displayed a Keychain prompt granting a broker access to `Claude Code-credentials`.

Permanent decision:

```text
No Claude Keychain broker
No direct bearer-token quota request
No Always Allow credential ACL
```

### 3.7 Claude Safari Browser Sync

Accepted compromise:

```text
Safari official Claude Usage page
→ UMA Browser Companion
→ bounded quota extraction
→ native handoff
→ sanitized snapshot
```

Milestones completed:

- manual one-click Browser Sync;
- 5h/7d live match;
- no Keychain/token/cookie/identity/raw DOM transfer;
- automatic five-minute sync after persistent site permission;
- one inactive extension-owned Usage tab;
- one scheduler and one in-flight read;
- main/Assistant parity;
- no repeated toolbar click after setup.

### 3.8 Claude challenge and cleanup

A Claude-only adversarial package was created. Claude Code then completed four local commits:

```text
2e9cfdf  chore(m5): remove retired Claude status-line route
f5ff2b4  chore(m5): repair test and package delivery foundation
9fda887  feat(m5): add Claude local activity and cost estimate
c6245f9  chore(m5): migrate bundle identifier and prepare signing
```

#### Status-line retirement

Removed undeclared second Claude source, installed relay artifacts, configuration, targets, and 30 tests. Retirement guards now reject reintroduction.

#### Test/delivery foundation

- `script/test.sh` is mandatory because bare `swift test` fails under the current CLT 27.0 layout.
- Packages now deliver under `$HOME/Developer/UMA-Packages` because `/private/tmp` is purged.

#### Claude local activity

Added aggregate local activity and API-equivalent cost from `~/.claude/projects` as a separate locally estimated channel.

Important correctness findings:

- de-duplicate one response repeated across content blocks by request identifier;
- five-minute and one-hour cache-creation buckets have different price multipliers;
- Claude has four disjoint token buckets and cannot reuse Codex cached-input arithmetic.

Account quota remains Browser Sync only. Local activity never substitutes for quota.

#### Bundle/signing readiness

Bundle ID migrated:

```text
com.kevinchen.CodexUsageMonitor
→ com.silkrd.uma
```

Packaging gained Developer ID identity support, hardened runtime, timestamp, optional notary profile, staple, and assessment readiness.

### 3.9 Current Claude freeze

Apple Developer Program enrolment is paid and processing.

Claude line is paused at:

```text
c6245f9cc745b3d45f53e115843b3152e84e8c46
```

No in-flight Claude edit exists.

When Apple status becomes Active, Claude owner resumes signing/notarization. Codex must not touch the locked M5 area.

---

## 4. Current working provider mechanisms

### 4.1 Codex — protected

```text
local codex app-server --stdio
→ account/rateLimits/read
→ account/usage/read
→ thread/list
```

Separate local logs provide recent tasks and API-equivalent cost.

Do not change:

- app-server discovery/requests;
- authenticated session reuse;
- refresh lifecycle;
- Codex cost/session logic;
- Codex UI semantics.

### 4.2 Claude Code — frozen

Account quota:

```text
Safari Browser Companion
→ official Claude Usage page
→ automatic 5-minute sanitized read
```

Local activity:

```text
~/.claude/projects
→ aggregate tokens/activity/cost estimate
```

Do not change until Apple signing milestone resumes/completes.

### 4.3 WorkBuddy — protected

```text
isolated WorkBuddy account-web session
→ exact all-pool Credits
→ Decimal authority
→ one-minute Auto Refresh
```

Do not change:

- login/session ownership;
- credit aggregation;
- cadence/coalescing;
- cache/reconnect/disconnect;
- UI semantics.

---

## 5. Current repository and operational rules

### 5.1 Local-only lineage

M6 must branch from local `c6245f9...`, not remote main.

### 5.2 Tests

Use:

```text
script/test.sh
```

Do not treat bare `swift test` failure as code regression.

Accepted baseline:

```text
485 tests
467 CodexUsageUITests
18 ClaudeBrowserBridgeCoreTests
Debug PASS
Release PASS
```

### 5.3 Packages

Use:

```text
$HOME/Developer/UMA-Packages
```

Do not deliver final evidence to `/private/tmp`.

### 5.4 Bundle ID

```text
com.silkrd.uma
```

Never reintroduce `com.kevinchen.*` in active configuration.

### 5.5 Connector limits

- at most two channels per provider;
- local-activity persisted payload exactly six aggregate scalars;
- sourceVersion regex and 32-character limit;
- current-read admission;
- stable order;
- no provider failure blanks the product.

### 5.6 Git

Never:

```text
git add .
git add -A
git add -u
git reset --hard
git clean
force-push
```

Stage exact paths.

### 5.7 Protected installed app

```text
~/Desktop/UMA_0.11.app
Executable SHA-256:
88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

Do not replace without fresh Founder authorization.

---

## 6. Founder preference evolution

### 6.1 Output and interaction style

- Chinese layman explanations by default.
- English copy-ready Codex tasks.
- Direct, factual, no agreeable filler.
- Challenge ideas rather than blindly accepting them.
- One clear next action.
- Do not make the user repeat permissions unnecessarily.

### 6.2 Model preference

Codex development defaults to GPT-5.6 Sol, choosing Medium / High / Extra High by difficulty.

Terra may be used only when explicitly selected for unusually complex work; the current M6 plan stays Sol-series.

### 6.3 Source preference

Evolution:

```text
strict local-only
→ provider-controlled login permitted when needed
→ exact quota and smooth onboarding prioritized
→ dangerous credential access still rejected
```

Current rule:

```text
Official structured local/provider CLI first
Provider-controlled browser login only as fallback
No API key/token/Keychain/manual quota
```

### 6.4 User experience preference

Founder rejects workflows requiring users to:

- use Terminal merely to refresh a desktop provider;
- send a prompt to update quota;
- paste an API key/token;
- repeatedly click Repair;
- repeatedly authorize a secret broker;
- manually deduct quota.

Automatic current data is preferred once a safe source is proven.

### 6.5 Accessibility

Deterministic accessibility semantics remain required.

Physical VoiceOver interaction was deferred to later development and must not block current provider work unless reactivated.

### 6.6 Provider order

Current Founder priority:

```text
Google Antigravity now
Cursor after Antigravity
```

This supersedes the old Scroll ordering that placed Kiro/Kimi/Junie before Cursor.

---

## 7. M5 exclusion zone

### 7.1 Locked runtime

See the full path list in `UMA_Handover_ClaudeCode_to_ChatGPT_2026-08-08.md`.

Summary:

- Claude Browser protocol/native host/cache/connector/settings/localization;
- entire `BrowserExtension/**`;
- Claude local activity reader;
- M5 tests;
- M5 package helper;
- `script/test.sh`;
- M5 governance.

### 7.2 Shared additive-only zone

- Package.swift;
- provider types/registry/snapshot store/runtime;
- UsageStore;
- UsageSnapshot;
- SharedUsagePresentation;
- main panel;
- Desktop Assistant.

M6 edits must be minimal and additive.

### 7.3 M6 free zone

- new Antigravity connector/services/models/store/localization;
- non-M5 tests;
- non-M5 governance;
- new M6 package helper.

---

## 8. Antigravity current research decision

### 8.1 Official source update

Older source documents expected an Antigravity status line.

Latest official CLI capability is better:

```text
agy read-only print /usage
→ JSON
→ no agent turn
→ no quota spend
→ no conversation
```

Official `/usage` alias `/quota` refreshes current model quota.

Official status-line schema confirms quota bucket fields including remaining fraction and reset.

### 8.2 M6 source decision

```text
Primary:
Official Antigravity CLI structured read-only /usage output

Secondary:
Status-line schema as corroboration only

Optional:
/credits exact balance if separately admitted
```

### 8.3 Research verdict

```text
CONDITIONAL GO TO M6-G1 SOURCE ADMISSION
```

Not production GO until installed behavior and schema pass.

### 8.4 Antigravity unit handling

- quota buckets remain percentages/fractions;
- `remaining_fraction × 100` when explicit;
- never double-invert;
- multiple buckets remain independent;
- Credits remain exact Credits;
- Maximum Decrement selects compact quota window centrally.

---

## 9. M6 program

```text
M6-B0
→ M6-G1
→ M6-SETUP-G1 if needed
→ M6-G2
→ M6-G3
→ M6DBG-G1
→ M6A-G1
→ M6ADBG-G1
→ M6-CLOSE-G1
```

Immediate next task:

```text
M6-B0
```

M6-B0 is docs/baseline only. It does not call live Antigravity quota.

---

## 10. Cursor direction after M6

Founder has selected Cursor after Antigravity.

Cursor must begin with source admission, not connector implementation.

Current likely issue:

- no admitted official local quota source yet;
- third-party approaches often depend on local session tokens or internal dashboard endpoints;
- those routes conflict with current credential/private-endpoint rules.

Expected next program:

```text
M7 — Cursor Source Admission
```

Cursor will also be provider five, so it must own the first real forced-Minimalist transition.

Do not implement Cursor inside M6.

---

## 11. Open risks and unresolved items

### Project

- Apple Developer Program still pending.
- First Developer ID notarization and Safari appex entitlement acceptance unproven.
- CLT 27.0 default test path remains broken; wrapper is accepted workaround.
- One existing 1-second polling test can flake under load.
- All current key commits are local-only.

### Antigravity

- Installed `agy` status unknown.
- Installed structured print capability unknown.
- Exact JSON schema unknown until live probe.
- Login-required behavior during background read unknown.
- Enterprise quota semantics may differ.
- `/credits` suitability unknown.
- Official output may include identity/private fields that must be rejected.

---

## 12. DEV 5 startup checklist

Before issuing a task:

```text
1. Confirm current Founder instruction.
2. Confirm local source HEAD c6245f9 and clean state.
3. Confirm M5 freeze.
4. Confirm M6 documents are the active plan.
5. Use Sol model and appropriate effort.
6. Use script/test.sh.
7. Deliver packages to persistent root.
8. Avoid repeated permission blockers by compiling scope once.
9. Do not push or install.
10. Give exactly one next action.
```

## 13. DEV 5 first response expectation

DEV 5 should:

- acknowledge current state;
- treat M6-B0 as next;
- use the supplied Codex Sol prompt;
- review the resulting report against exact Git and freeze evidence;
- not start M6-G1 until M6-B0 is accepted.

---

## 14. Key paths and artifacts

```text
Current repo:
/Users/juliushe/Developer/UMA-M5-Claude

New M6 worktree:
/Users/juliushe/Developer/UMA-M6-Antigravity

Persistent packages:
/Users/juliushe/Developer/UMA-Packages

Protected installed app:
/Users/juliushe/Desktop/UMA_0.11.app
```

Generated handoff package includes:

```text
M6_Antigravity_Feasibility_Analysis.md
M6_Plan.md
M6_Goals.md
Dev_4to5_ShiftChange.md
Codex_DEV_Sol_M6_Update_Checkup_Prompt.md
```

---

## 15. Final shift status

```text
Outgoing DEV 4:
complete

Incoming DEV 5:
ready

Active milestone:
M6 Google Antigravity

Next Goal:
M6-B0

Claude M5:
frozen pending Apple Developer Program

Next provider after M6:
Cursor

Remote delivery:
not authorized
```
