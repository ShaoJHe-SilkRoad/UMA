# Usage Monitor Altoget — M4 Goals

**Program:** M4 — Manus Official API v2 Credits Integration  
**Version:** 2.0  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Execution standard:** Goal Mode 2.0  
**Default authority:** `LOCAL_FULL_THROTTLE`  
**Remote push/release:** Not authorized  
**Status:** Copy-ready execution reference; send one task at a time  
**Active Plan:** `M4_Plan.md` version 2.0

---

## 0. Governing sequence

```text
M4-B0
→ M4-G1
→ M4-G2 only after GO / CONDITIONAL GO
→ M4-G3
→ M4DBG-G1
→ M4A-G1
→ M4ADBG-G1
→ M4-CLOSE-G1
```

No task starts automatically.

Every report ends under Completion Lock.

Known current baseline:

```text
Repository:
ShaoJHe-SilkRoad/UMA

Remote branch:
main

Known merged main:
469be4d6cf411a89401c2341807a57aef176d852

Qualified 0.11 development source:
459ea1321817e391ba80fe79f19edb0352fc76cb

Installed Founder application:
/Users/juliushe/Desktop/UMA_0.11.app

Current production providers:
Codex
WorkBuddy
```

If current `origin/main` has advanced beyond the known commit, inspect the newer history. Do not hard-reset to the stale hash. Continue only when the advancement is understood and compatible with the Founder’s current direction.

---

# 1. M4-B0 — Merged-main worktree and governing-source installation

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Medium
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

TASK — UMA M4-B0: Create the canonical Manus worktree and install the current governing source
```

## Result target

Create one durable M4 branch/worktree from current merged `origin/main`, install the DEV 4 source/reference package as the active governing source, install the official Manus API documentation skill for Codex, create one exact docs-only local commit, and make no runtime/configuration change.

## Plan authority

Current Founder direction:

```text
UMA 0.11 is merged.
Install the current source/reference generation.
Proceed next to Manus integration.
```

Current governing files supplied with this task:

```text
Scroll_2.0.md
UMA_Logic_1.4.md
UMA_0.11_closeout.md
Provider_Status_Matrix.md
M4_Plan.md
M4_Goal.md
Source_Reference_Manifest.md
```

Historical documents remain read-only references.

## Source-pack input

The Human will provide one of:

1. the extracted `UMA_DEV4_Source_Pack` directory;
2. the ZIP archive;
3. the seven Markdown files as current-thread attachments.

DEV must locate the exact supplied package without guessing or downloading from an unofficial location.

Expected local staging variable when a directory is supplied:

```text
SOURCE_PACK_DIR=<Human-provided path>
```

## Required destination

```text
Branch:
codex/uma-m4-manus

Worktree:
/Users/juliushe/Developer/UMA-M4-Manus

Repository destination:
source/reference/
```

If the branch/worktree exists, inspect it. Preserve legitimate work. Do not overwrite or reset it.

## Preauthorized

- discover the canonical local clone for `ShaoJHe-SilkRoad/UMA`;
- inspect remotes, branches, worktrees, HEAD, index, ignored files, and current `origin/main`;
- run `git fetch origin --prune`;
- create the branch/worktree from current `origin/main`;
- inspect the supplied source pack and its hashes;
- create `source/reference/`;
- copy the exact governing files;
- preserve file content and names;
- make one bounded attempt to install the official Manus API skill with:

```bash
npx skills add https://open.manus.ai/docs --skill manus-api --agent codex --global --yes
```

- if the official skill command is unavailable or fails after one bounded attempt, record the exact nonsecret error, continue with direct official documentation, and do not install unrelated package-manager tooling;
- run documentation/diff checks;
- stage only the exact new source/reference files;
- create one local commit after PASS:

```text
docs(m4): install current governing source
```

## Not authorized

- runtime source edits;
- package/build metadata changes;
- API-key access;
- Manus live request;
- installed-app replacement;
- PR closure;
- push;
- merge;
- tag;
- release;
- notarization;
- deployment;
- deletion of historical source records.

## Execute

1. Discover the canonical clone by verifying the remote URL.
2. Record:
   - current branch;
   - local HEAD;
   - `origin/main`;
   - worktree list;
   - status;
   - index;
   - recent log.
3. Require current `origin/main` to contain the merged UMA 0.11 integration.
4. If `origin/main` differs from the known commit:
   - inspect the commits;
   - confirm they are legitimate descendants;
   - record the updated baseline;
   - stop if the change is unexplained or conflicts with M4.
5. Create `codex/uma-m4-manus` and the durable worktree.
6. Verify the new worktree starts clean.
7. Verify the supplied source pack:
   - expected files present;
   - UTF-8 readable;
   - no binaries/secrets;
   - hashes match when a manifest is supplied.
8. Copy the seven current governing files into `source/reference/`.
9. Add a short `source/reference/README.md` only when needed to point to `Source_Reference_Manifest.md`; do not duplicate the full documents.
10. Install the official Manus API skill.
11. Verify the skill installation without printing credentials or unrelated global configuration.
12. Run:
   - `git diff --check`;
   - Markdown structural check if an existing tool exists;
   - source-reference link/name check;
   - secret/private-path scan.
13. Stage exact files only.
14. Audit cached diff.
15. Commit.
16. Confirm clean index/worktree after commit.

## PASS

- current merged `main` is the parent;
- one durable M4 worktree exists;
- all current governing files exist under `source/reference/`;
- the official Manus API skill is installed, or one bounded failed attempt is recorded as a nonblocking environment risk while direct official documentation remains usable;
- no runtime/configuration file changed;
- one docs-only local commit exists;
- no remote action occurred;
- M4-G1 may begin.

## Final report

Return:

1. Verdict.
2. Canonical clone and remote.
3. Parent `origin/main`.
4. Branch/worktree.
5. Installed source files.
6. Source-pack hash result.
7. Manus skill result.
8. Exact staged files.
9. Commit.
10. Worktree/index state.
11. Confirmation of no runtime/live/remote action.
12. Next task: M4-G1 only.
13. Completion Lock.

## Completion Lock

Stop.

Do not inspect or request the Founder’s Manus API key.

Do not begin M4-G1 automatically.

---

# 2. M4-G1 — Manus API v2 source admission and secret-boundary dossier

```text
MODEL: GPT-5.6 Terra | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M4-G1 — Manus official API v2 Credit source admission and secret-boundary dossier
```

## Predecessor gate

Consume accepted M4-B0.

Expected worktree:

```text
/Users/juliushe/Developer/UMA-M4-Manus
```

Expected branch:

```text
codex/uma-m4-manus
```

Stop if the current governing source is absent or if the worktree does not descend from current merged `main`.

## Result target

Produce a commit-exact, privacy-safe Manus source dossier that verifies the current official API v2 balance endpoint, field semantics, authentication boundary, macOS Keychain design, request lifecycle, package feasibility, and a GO / CONDITIONAL GO / NO-GO decision.

No production Manus connector is completed in this Goal.

## Why now

Official Manus API v2 documentation currently describes:

```text
GET /v2/usage.availableCredits
```

with:

```text
x-manus-api-key
```

and an authoritative:

```text
total_credits
```

The source is promising, but documentation alone does not prove secure local integration or a successful Founder-account read.

## This is not

- API-key collection;
- live balance read;
- task creation;
- `usage.list` implementation;
- UI card implementation;
- Assistant integration;
- release work.

## Governing source

Read:

```text
source/reference/Scroll_2.0.md
source/reference/UMA_Logic_1.4.md
source/reference/Provider_Status_Matrix.md
source/reference/M4_Plan.md
Goal Mode 2.0
current source code and tests
official Manus API v2 skill/docs
```

## Preauthorized

- inspect current repository and relevant provider/Keychain/network/persistence architecture;
- use the installed official Manus API skill;
- read current official Manus API v2 documentation;
- inspect the endpoint schema, auth, rate limits, and deprecation status;
- inspect current macOS Keychain APIs and existing project security patterns;
- create docs, fixtures, schema samples, and tests needed to prove feasibility;
- run offline builds/tests;
- make one unauthenticated request only when useful to confirm safe 401/403 behavior, with:
  - no API key;
  - no retry;
  - no account mutation;
- stage exact docs/tests only;
- create one local commit:

```text
docs(m4): admit Manus Credit source
```

## Not authorized

- read or receive a Manus API key;
- inspect Keychain values;
- create a Manus task;
- intentionally consume Credits;
- use task/project/file/webhook/browser endpoints;
- read `usage.list` live;
- desktop/web scraping;
- cookie import;
- source runtime implementation beyond a bounded feasibility harness;
- installed-app replacement;
- push/release.

## Required source dossier

Create:

```text
source/UMA M4 Manus Source Dossier.md
source/UMA M4 Manus Admission Decision.md
source/UMA M4 Manus Secret Handling Contract.md
source/UMA M4 Manus QA Issue Ledger.md
source/UMA M4 Scope Lock.md
```

### Dossier must prove

1. current API version and host;
2. current endpoint path/method;
3. authentication method;
4. whether OAuth is accepted by the balance endpoint;
5. API-key creation workflow at a high level;
6. key sensitivity;
7. response schema;
8. `total_credits` authority;
9. component-field semantics;
10. quota versus current balance distinction;
11. personal/team scope;
12. rate-limit or conservative cadence decision;
13. timeout/redirect/body-size policy;
14. current error schema;
15. Keychain storage design;
16. safe disconnect;
17. no-task/no-history scope;
18. package/privacy feasibility;
19. live Human validation plan.

## Field classification

For every current documented field:

```text
accepted primary
accepted optional detail
accepted reset detail
quota only — never current balance
unknown/reject
private/reject
```

## Required source decision

### GO

Only when the documentation and local architecture prove:

- official stable source;
- exact authoritative balance;
- secure Keychain path;
- privacy-safe minimum field set;
- bounded request behavior;
- live validation can occur without DEV receiving the key.

### CONDITIONAL GO

Allowed when:

- source and secure implementation are feasible;
- live Founder-account read remains a later Human-controlled gate;
- optional fields are account-dependent.

### NO-GO

Required when:

- key cannot be safely stored;
- endpoint is not current or official;
- balance semantics are ambiguous;
- task creation is required;
- DEV must receive the secret;
- implementation requires scraping/private state.

## Required architecture decision

Return one recommended path:

```text
Keychain
→ narrow URLSession client
→ usage.availableCredits only
→ strict decoder
→ provider-neutral Credit snapshot
```

Reject unnecessary SDK/framework/platform additions.

## Subagents

Use distinct roles:

- Source/Protocol Auditor — current official endpoint/auth/schema.
- Secret Boundary Steward — Keychain and redaction.
- Connector Architect — minimum integration path.
- QA Runner — offline schema/error/build evidence.
- Examiner — GO/CONDITIONAL GO/NO-GO.

No role receives a real key.

## Verification

At minimum:

- official-doc source inventory;
- schema fixture decode;
- negative/overflow/missing-primary tests;
- request construction test with redacted header;
- exact-host/path test;
- redirect/timeout policy test;
- no-secret-persistence audit;
- package feasibility build;
- `git diff --check`;
- full affected test regression.

## PASS

- source decision is supported;
- no secret was requested/read;
- `total_credits` semantics are locked;
- Keychain design is locked;
- no task/history surface is admitted;
- local docs commit exists;
- M4-G2 may begin only on GO or CONDITIONAL GO.

## FAIL / BLOCKED

Return one consolidated owner packet only when the official source cannot be evaluated without an external Human action.

Do not ask for the API key.

## Final report

Return:

1. Verdict.
2. Model/authority.
3. Git baseline.
4. Official source facts.
5. Field classification.
6. Auth/secret design.
7. Cadence decision.
8. Source verdict.
9. Files created.
10. Tests/commands.
11. QA ledger.
12. Commit/index.
13. Exact M4-G2 admission.
14. Completion Lock.

## Completion Lock

Stop.

Do not implement the production connector.

Do not ask for the Manus API key.

---

# 3. M4-G2 — Secure Keychain, API client, connector, and Settings

```text
MODEL: GPT-5.6 Terra | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M4-G2 — Implement the secure Manus Credits source and Settings
```

## Queue gate

Consume accepted M4-G1 GO or CONDITIONAL GO.

If M4-G1 returned NO-GO, output:

```text
QUEUE HELD — MANUS SOURCE NOT ADMITTED
```

and stop without editing runtime files.

## Result target

Implement a production-shaped Manus Credits source using a Keychain-backed API key, a narrow official API v2 client, strict current-balance decoding, provider registration, source state, refresh coalescing, and bounded Settings.

Complete offline implementation and package evidence without DEV reading a real key or claiming live balance success.

## Core path

```text
Manus Settings
→ Keychain Manus API key
→ GET /v2/usage.availableCredits
→ strict normalized ManusCreditsSnapshot
→ ManusUsageConnector
→ AgentConnectorRegistry
→ UsageStore
→ shared presentation
```

Main-panel visual acceptance is completed in M4-G3.

## Core contracts

1. key exists only in Keychain and transient request memory;
2. normal preferences store only safe booleans/settings;
3. exact host/path/method/header;
4. `total_credits` required and authoritative;
5. optional component fields remain optional;
6. no component-sum requirement;
7. no fake percentage;
8. no `usage.list`;
9. no task API;
10. one connector;
11. one API client;
12. one optional timer;
13. zero overlapping reads;
14. safe auth/network/schema states;
15. current read required for admission;
16. disconnect deletes the key and current snapshot;
17. Assistant code remains read-only/unmodified unless shared compile changes require a neutral adapter.

## Expected implementation areas

- provider descriptor/catalog;
- source class/capabilities;
- Keychain service;
- Manus request/response models;
- API client;
- connector;
- refresh scheduler/coalescing;
- safe persistence;
- Settings coordinator/model/view;
- localization/accessibility;
- fixtures and tests;
- package/privacy contract.

Avoid broad refactoring.

## Preauthorized

- inspect/edit bounded provider, security, network, registry, store, settings, localization, test, package, and source-record files;
- use Security framework public APIs;
- use URLSession public APIs;
- create task-owned fixtures;
- use no real key;
- make one unauthenticated endpoint request only if required by an accepted test;
- run focused/full tests and builds;
- automatic in-scope repair;
- stage exact files;
- create one local commit:

```text
feat(manus): add secure Credit source
```

- build one commit-exact offline candidate under `/private/tmp`.

## Not authorized

- real API key access;
- authenticated live request;
- task creation;
- task/history endpoint;
- browser scraping;
- installed-app replacement;
- push/release;
- unrelated redesign;
- WorkBuddy/Codex source changes except required shared compatibility repairs.

## Keychain requirements

- stable service/account IDs;
- save/replace/delete;
- no plaintext fallback;
- safe duplicate-item handling;
- accessibility class selected and documented;
- no secret synchronization unless explicitly approved;
- no key in error descriptions;
- no key in Codable/UserDefaults;
- no key in process args/env;
- unit tests use an injected fake store, not the real key.

## API client requirements

- exact `https://api.manus.ai/v2/usage.availableCredits`;
- GET;
- `x-manus-api-key`;
- no request body;
- bounded timeout;
- bounded response size;
- standard TLS;
- unexpected redirects rejected;
- one request at a time;
- HTTP/status/error mapping;
- strict JSON decode;
- raw body not logged;
- unknown fields ignored safely;
- no automatic retries.

## Snapshot requirements

- nonnegative exact integers;
- safe Int64 conversion;
- missing `total_credits` rejects;
- optional fields nullable;
- timestamp seconds;
- interval allowlist;
- observation timestamp;
- source `officialAPIV2`;
- no request ID persisted.

## Refresh requirements

- launch read only when configured;
- Manual Refresh;
- Sync Now;
- optional Auto Refresh;
- no faster than accepted M4-G1 cadence;
- one in-flight gate;
- no catch-up burst;
- auth failure suspends;
- disconnect cancels.

## Settings requirements

Disconnected:

```text
Manus
Official API v2
Not connected
[ Connect Manus ]
```

Connection disclosure and SecureField.

Connected state with:

- updated time;
- Auto Refresh toggle;
- cadence;
- Sync Now;
- Disconnect;
- safe error.

No raw key reveal after save.

## Required tests

### Keychain abstraction

- add;
- replace;
- retrieve through internal request path;
- delete;
- duplicate item;
- denied/unavailable;
- no preference serialization;
- no log leakage.

### Decoder

- complete valid;
- only `total_credits`;
- optional fields absent;
- zero;
- max supported;
- negative;
- overflow;
- missing primary;
- malformed type;
- unknown field;
- interval values;
- timestamp bounds;
- `ok=false`.

### Network

- exact host/path/method;
- header present but redacted in diagnostics;
- timeout;
- redirect;
- 401/403;
- 429;
- 500;
- non-JSON;
- oversized body;
- cancellation.

### Connector

- not configured;
- configured waiting;
- refreshing;
- admitted;
- auth failed;
- transient failed;
- unsupported;
- disconnect;
- one in-flight;
- cadence;
- no task/history request.

### Privacy/package

- no key;
- no raw response;
- no real balance fixture;
- no Task API path;
- no `usage.list`;
- no secret in package;
- no Assistant ownership.

## Subagents

- Implementer.
- Secret Boundary Steward.
- QA Runner.
- Connector/Protocol Auditor.
- Packaging/Privacy Auditor.
- Examiner.

## PASS

- offline production implementation is complete;
- key handling is Keychain-only;
- only the admitted endpoint exists in runtime path;
- strict fixtures/tests pass;
- Codex/WorkBuddy regressions pass;
- commit-exact offline package passes;
- one local commit exists;
- no live claim is made;
- M4-G3 may begin.

## Final report

Full Goal report including:

- before/after architecture;
- exact files;
- tests and first failures/repairs;
- secret evidence;
- endpoint allowlist;
- package audit;
- commit/index;
- live status explicitly `NOT YET VALIDATED`;
- Completion Lock.

## Completion Lock

Stop.

Do not ask the Human for the key in chat.

Do not begin live acceptance automatically.

---

# 4. M4-G3 — Live main-panel and package acceptance

```text
MODEL: GPT-5.6 Terra | THINKING EFFORT: High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M4-G3 — Manus live Credit read, main-panel integration, and package acceptance
```

## Predecessor gate

Consume accepted M4-G2.

The offline candidate must already:

- store secrets only in Keychain;
- call only `usage.availableCredits`;
- pass offline tests;
- contain no secret;
- have one local commit.

## Result target

Produce one commit-exact candidate in which the Human can enter a Manus API key directly into UMA, obtain a current official Credit balance, and view Manus as an independent main-panel Agent card beside Codex and WorkBuddy.

## Human secret gate

The Human performs the only secret action.

DEV must provide one concise instruction packet:

```text
1. Open the exact M4 candidate.
2. Open Settings → Manus.
3. Select Connect Manus.
4. Create/retrieve an official Manus API key in the Manus web interface.
5. Paste it only into the UMA SecureField.
6. Select Save and Verify.
7. Do not paste the key into Codex, ChatGPT, Terminal, logs, or screenshots.
```

DEV does not read or request the key.

## Live authority

After Human configuration:

- read-only `usage.availableCredits` requests only;
- maximum 20 authenticated reads;
- maximum 45 minutes;
- no task creation;
- no API spend action;
- no retry storm;
- no other Manus endpoint;
- no account mutation;
- redacted evidence only.

## Required main-panel behavior

Collapsed:

- Manus;
- exact current Credits;
- Official API v2;
- last update.

Expanded:

- authoritative total;
- approved optional components;
- refresh details when present;
- source;
- update time;
- Sync Now;
- Agent Settings.

No key or account identity.

No fake percentage.

### Admission

Current successful read:

```text
visible
```

Missing/invalid key or current failure:

```text
hidden from usage surfaces
+ safe Settings reason
```

### Order

Stable registry priority:

```text
Codex
WorkBuddy
Manus
```

Claude remains hidden but retains its reserved priority.

## Preauthorized

- bounded main-panel/provider asset/presentation/localization/accessibility/test repairs;
- temporary candidate launch/termination;
- Human-controlled key entry;
- up to 20 read-only balance calls;
- compare the displayed value with the official Manus UI through Human confirmation;
- record only redacted result classes;
- run builds/tests/package audits;
- automatic in-scope repair;
- stage exact files;
- create one local commit:

```text
feat(m4): show Manus Credits in main panel
```

- produce one commit-exact package under `/private/tmp`.

## Not authorized

- key access by DEV;
- task/history endpoints;
- task creation;
- remote push/release;
- installed-app replacement;
- broad UI redesign;
- Assistant integration.

## Required live matrix

- valid key and successful current read;
- relaunch with Keychain credential;
- Manual Refresh;
- Sync Now;
- Auto Refresh ON;
- Auto Refresh OFF / Manual only;
- invalid/revoked key;
- network unavailable;
- 429;
- server failure;
- malformed response fixture;
- disconnect;
- reconnect;
- current failure hides Manus;
- Codex/WorkBuddy remain independent.

## Required privacy proof

- key absent from process args;
- key absent from normal preferences;
- key absent from logs;
- key absent from evidence;
- key absent from package;
- no raw response retained;
- no task/history API call.

## Required package proof

- exact commit;
- version/build recorded;
- signature;
- architecture;
- dependencies;
- privacy allowlist;
- no fixture/test/log/source pack;
- no key or Keychain export.

## PASS

- one real current Manus balance is read;
- Human confirms official balance parity;
- main panel shows exact Credits;
- key remains private;
- current failure removes the card;
- Codex and WorkBuddy remain correct;
- local commit/package pass;
- M4DBG may begin.

## PASS WITH RISKS

Only for a nonblocking optional-field absence or external service variability when current authoritative balance and security are proven.

## FAIL

- no successful current read;
- key leaks;
- task/history endpoint used;
- fake percentage;
- card remains visible after current failure;
- package contains secret/private state;
- Codex/WorkBuddy regression.

## Final report

Do not report the key.

Prefer not to report the exact real balance; use:

```text
current integer balance observed
official UI parity confirmed by Human
```

Return full evidence, commit, package, risks, and Completion Lock.

## Completion Lock

Stop.

Do not begin M4DBG automatically.

---

# 5. M4 Quick Patch rule

Use a Quick Patch only for a narrow confirmed M4 defect after M4-G3, such as:

- one decoder field;
- one safe error mapping;
- one localization string;
- one layout clip;
- one Keychain duplicate-item path;
- one cadence bug;
- one accessibility label.

A Quick Patch may not:

- add another endpoint;
- broaden secret access;
- introduce task history;
- change provider architecture;
- replace the installed app;
- push/release.

Required:

```text
reproduce
→ smallest repair
→ focused test
→ affected regression
→ privacy check
→ exact local commit
→ stop
```

---

# 6. M4DBG-G1 — Three-provider main-app debugging

```text
MODEL: GPT-5.6 Terra | THINKING EFFORT: High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M4DBG-G1 — Codex + WorkBuddy + Manus main-app debugging and commit-exact acceptance
```

## Predecessor gate

Consume accepted M4-G3 and any accepted Quick Patches.

Use the latest local M4 commit and commit-exact package.

## Result target

Stress and repair the three-provider main application before Manus enters the Desktop Assistant.

Prove independent source lifecycle, credential safety, refresh coalescing, state transitions, resources, Settings, and package provenance.

## Live authority

- use the already configured Keychain credential without reading/exporting it;
- maximum 80 Manus balance reads;
- maximum 75 minutes;
- no task/history endpoint;
- no account mutation;
- no task creation;
- no automatic retry beyond accepted cadence;
- bounded Codex reads through existing path;
- bounded WorkBuddy reads through existing source.

## Required matrix

### Provider combinations

- all three fresh;
- Codex failed / WorkBuddy+Manus fresh;
- WorkBuddy failed / Codex+Manus fresh;
- Manus failed / Codex+WorkBuddy fresh;
- each provider unavailable independently;
- all unavailable;
- recovery of each provider.

### Manus auth/source

- valid key;
- revoked/invalid key;
- missing Keychain item;
- Keychain error;
- 401/403;
- 429;
- 500;
- timeout;
- malformed/partial data;
- unsupported interval;
- disconnect/reconnect;
- current failure hides Manus.

### Refresh

- 50 global Manual Refresh actions with coalescing;
- 20 Manus Sync Now actions;
- timer + manual collision;
- WorkBuddy timer + Manus timer;
- slow request;
- no overlap;
- no catch-up burst;
- no immediate failure storm;
- Assistant hidden throughout this main-app gate.

### Lifecycle

- 10 relaunches;
- Settings open/close;
- Agent Settings navigation;
- expansion persistence;
- provider removal/reappearance;
- stable order;
- no hidden-provider spacing.

### Presentation

- exact Credits;
- compact card;
- no fake percent;
- exhausted 0;
- optional fields absent;
- Light/Dark;
- transparency/contrast/motion;
- English/Chinese;
- keyboard/VoiceOver.

### Resource run

- 30–60 minute bounded run;
- CPU;
- RSS;
- threads;
- descriptors;
- timers;
- owned processes;
- network request counts;
- one Manus client/timer/connector;
- one WorkBuddy WebView/timer;
- one Codex child maximum;
- clean shutdown.

## Preauthorized

- narrow runtime/test/docs/package repairs;
- use stored key only through the app;
- task-owned package/process control;
- automatic repair;
- exact staging;
- one local commit after PASS:

```text
fix(m4): close Manus main-panel defects
```

- create `source/UMA M4A Handoff.md`.

## Not authorized

- secret extraction;
- endpoint expansion;
- Assistant integration;
- installed-app replacement;
- push/release.

## QA Issue Ledger

Maintain:

```text
ID
Evidence
Severity
Acceptance impact
Repair
Focused retest
Regression retest
Status
```

Repair all in-scope blockers/majors and acceptance-required minors.

## PASS

- no blocking/major main-app defect;
- three providers remain independent;
- no secret leak;
- no request multiplication;
- resources bounded;
- package/privacy pass;
- local commit exists;
- M4A may begin.

## Final report

Full Goal report with redacted live evidence, resource tables, request counts, QA ledger, commit/package, and Completion Lock.

## Completion Lock

Stop.

Do not begin Desktop Assistant integration automatically.

---

# 7. M4A-G1 — Manus in Desktop Assistant

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

TASK — UMA M4A-G1: Add Manus shared Credit presentation to Desktop Assistant
```

## Predecessor gate

Consume accepted M4DBG-G1 and `source/UMA M4A Handoff.md`.

## Result target

Add Manus as the next Desktop Assistant row using only the accepted shared `AgentCardViewModel`, with no Keychain, network, timer, API client, decoder, or private snapshot logic in Assistant code.

## Required behavior

- stable visible order:
  - Codex;
  - WorkBuddy;
  - Manus;
- exact main/Assistant state and value parity;
- Regular shows exact integer Credits;
- Minimalist uses deterministic truncated k/M/B;
- no `%`;
- no proportional fill without a complete denominator;
- source-state mark independent from balance;
- exhausted 0 is explicit;
- tooltip/VoiceOver includes exact Credits, source, update time, and refresh detail when available;
- row action opens matching main-panel provider;
- Assistant show/hide does not trigger or reset Manus reads;
- no geometry redesign beyond required text fitting;
- no empty shell when all providers hidden.

## Scope

Edit bounded:

- Assistant presentation;
- shared provider asset mapping;
- row navigation;
- localization;
- accessibility;
- tests;
- package/source handoff.

Connector, Keychain, API client, and scheduler are read-only.

## Preauthorized

- bounded UI/shared-presentation edits;
- fixtures;
- appearance/accessibility rendering;
- focused/full affected tests;
- automatic repair;
- stage exact files;
- local commit:

```text
feat(assistant): add Manus Credit presentation
```

- commit-exact package.

## Not authorized

- live API-source changes;
- key access;
- cadence change;
- main-panel redesign;
- installed-app replacement;
- push/release.

## Required tests

- 0/1/2/3 visible providers;
- Manus only fixture;
- all three;
- Manus available/exhausted/unavailable/failed;
- large values;
- 999/1k/nonpromotion;
- Regular/Minimalist;
- visible count transitions;
- Light/Dark;
- Reduce Transparency;
- Increase Contrast;
- Reduce Motion;
- English/Chinese;
- VoiceOver;
- focus/position;
- show/hide ownership;
- no Assistant timer/client/Keychain import;
- package privacy.

## PASS

- Manus appears in the Assistant through shared presentation only;
- exact parity passes;
- no source ownership exists;
- all UI/accessibility/package tests pass;
- local commit exists;
- M4ADBG remains unstarted.

## Final report

Standard Task report with exact files, tests, ownership proof, commit/package, risks, and Completion Lock.

## Completion Lock

Stop.

Do not begin M4ADBG automatically.

---

# 8. M4ADBG-G1 — Three-provider combined closeout

```text
MODEL: GPT-5.6 Terra | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M4ADBG-G1 — Codex + WorkBuddy + Manus combined main/Assistant closeout
```

## Predecessor gate

Consume accepted M4A-G1.

Use the latest commit-exact candidate.

## Result target

Close the Manus runtime program with exact main-panel/Desktop Assistant parity, secure credential lifecycle, independent provider recovery, bounded refresh/resource behavior, package privacy, and one final commit-exact local package.

## Live authority

- use the app-configured Manus Keychain credential without DEV access;
- maximum 120 Manus balance reads;
- maximum 90 minutes;
- no task/history endpoint;
- no account mutation;
- no task creation;
- bounded Codex/WorkBuddy reads through accepted sources;
- no installed-app replacement.

## Required combined matrix

### Surface parity

- main open/closed;
- Assistant visible/hidden;
- exact provider IDs;
- exact value/state parity;
- expansion;
- provider navigation;
- zero-provider shell suppression.

### Provider states

- all fresh;
- each provider failed independently;
- Manus invalid key;
- WorkBuddy auth expiry;
- Codex recovery;
- staggered updates;
- simultaneous refresh events;
- current failure withdrawal.

### Assistant lifecycle

- 100 show/hide cycles;
- position restore;
- display changes;
- Always on Top;
- density transitions;
- manual preference restore;
- no focus stealing;
- no source-read multiplication.

### Refresh ownership

- one Manus timer/client/connector;
- one WorkBuddy timer/WebView/connector;
- one Codex connector/child maximum;
- global Manual Refresh coalescing;
- no catch-up bursts;
- no duplicate publication.

### Secret lifecycle

- save;
- relaunch;
- use;
- invalid;
- replace;
- disconnect/delete;
- no log/preference/package leak;
- no DEV read.

### Appearance/accessibility

- Light/Dark;
- transparency/contrast/motion;
- English/Chinese;
- keyboard;
- VoiceOver;
- Settings scrolling;
- Agent Settings.

### Endurance

- 45–60 minute combined run;
- CPU/RSS/thread/descriptor/network/timer samples;
- clean termination;
- no orphan resources.

### Package

- exact commit;
- signature;
- architecture;
- dependencies;
- no key;
- no Keychain export;
- no raw response;
- no real balance fixture;
- no tests/logs/screenshots/source pack.

## Preauthorized

- all narrow in-scope runtime/test/docs/package repairs;
- live reads within limits;
- automatic QA repair;
- exact staging;
- final runtime repair commit when required:

```text
fix(m4): close Manus combined defects
```

- docs closeout commit when runtime is already clean:

```text
docs(m4): close Manus integration
```

- create:
  - `source/UMA M4 Package Closure.md`;
  - `source/UMA M4 QA Issue Ledger.md`;
  - `source/UMA M4 Manus Closeout.md`;
  - `source/UMA M5 Handoff.md`;
- produce one final commit-exact package.

## Not authorized

- installed-app replacement;
- remote push;
- PR;
- merge;
- tag;
- release;
- notarization;
- next-provider implementation;
- Claude reassessment.

## Subagents

- Runtime/Connector Auditor.
- Secret Boundary Steward.
- QA Runner.
- Performance/Resource Auditor.
- Packaging/Privacy Auditor.
- Accessibility/Localization Auditor.
- Examiner.

## PASS

- current Manus Credits are live-qualified;
- main/Assistant parity passes;
- no secret exposure;
- no task/history API use;
- provider independence passes;
- resource ownership passes;
- package privacy/provenance passes;
- no blocking/major defect;
- final local commits/package exist;
- M4 runtime program is ready for closeout.

## PASS WITH RISKS

Only for a truly external optional-field/service limitation that does not affect current authoritative balance, credential safety, or provider independence.

## FAIL

- key leak;
- current balance not proven;
- stale current display after failure;
- task/history endpoint use;
- resource multiplication;
- main/Assistant mismatch;
- package contains private state;
- unresolved blocking/major defect.

## Final report

Return the complete Full Goal report.

Do not disclose:

- API key;
- raw response;
- unnecessary exact real balance;
- account identity.

End with M4-CLOSE-G1 as the only recommendation.

## Completion Lock

Stop.

Do not install the package.

Do not start another provider.

---

# 9. M4-CLOSE-G1 — Governing-source update and milestone closeout

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Medium
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

TASK — UMA M4-CLOSE-G1: Close Manus integration and update the governing source
```

## Predecessor gate

Consume accepted M4ADBG-G1.

Require:

- final runtime commit;
- final package;
- M4 QA ledger;
- M4 package closure;
- no open blocking/major defect.

## Result target

Update the current governing source to reflect the actual accepted M4 result, mark Manus accurately in the Provider Status Matrix, record exact commit/package evidence, identify the single next milestone, and stop.

## Required updates

Update exact current files under `source/reference/`:

```text
Scroll_2.0.md
UMA_Logic_1.4.md
Provider_Status_Matrix.md
M4_Plan.md status/header when needed
M4_Goal.md status/header when needed
Source_Reference_Manifest.md
```

Create:

```text
source/UMA_M4_closeout.md
```

Do not rewrite `UMA_0.11_closeout.md`.

## Current-truth rule

Use the accepted M4 evidence.

Do not copy planned behavior into the closeout unless proven.

Clearly distinguish:

- implemented;
- live-qualified;
- optional field unavailable;
- package built;
- installed/not installed;
- pushed/not pushed;
- released/not released.

## Next milestone decision

Default next route after successful M4:

```text
M5 — Cursor source admission and integration
```

But the closeout may recommend:

- a narrow M4 Quick Patch;
- a Founder field-test window;
- a documentation/CI task;
- Claude reassessment;

when current evidence supports that instead.

Do not start it.

## Preauthorized

- docs-only edits;
- exact tests/checks;
- source-reference consistency audit;
- exact staging;
- one local docs commit:

```text
docs(m4): record Manus integration closeout
```

## Not authorized

- runtime changes;
- installed-app replacement;
- push/release;
- next-provider work.

## PASS

- governing docs match actual M4 truth;
- no historical closeout is overwritten;
- one docs commit exists;
- one next recommendation is recorded;
- no next task starts.

## Final report

Return:

- verdict;
- exact runtime/package baseline;
- current provider matrix;
- updated files;
- consistency checks;
- commit/index;
- next recommendation;
- Completion Lock.

## Completion Lock

Stop completely.

M4 is closed.

Wait for a new Founder instruction.

---

## 10. Copy/run rule

```text
Send one task
→ receive the complete report
→ review claim-matched evidence
→ accept or return one correction
→ send the next task only after acceptance
```

Do not paste the complete file into one Codex execution turn.

---

## Appendix A — Human API-key instruction template

Use only when M4-G3 requests the secret gate:

```text
Step 1 — Open the exact M4 candidate application.
Step 2 — Open Settings → Manus.
Step 3 — Select Connect Manus.
Step 4 — In the official Manus web interface, create or retrieve an API key.
Step 5 — Paste the key only into UMA’s SecureField.
Step 6 — Select Save and Verify.
Step 7 — Confirm that the displayed Credit balance matches Manus.
Do not paste or screenshot the key anywhere else.
If verification fails, stop. Do not repeatedly create keys.
```

---

## Appendix B — Hard endpoint allowlist

Initial M4 runtime:

```text
GET https://api.manus.ai/v2/usage.availableCredits
```

No other Manus endpoint is authorized by this Goal set.
