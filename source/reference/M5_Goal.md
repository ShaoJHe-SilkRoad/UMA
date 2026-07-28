# Usage Monitor Altoget — M5 Goals

**Program:** M5 — Claude Code Local Structured Usage Support  
**Version:** 1.0  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Execution standard:** Goal Mode 2.0  
**Default authority:** `LOCAL_FULL_THROTTLE`  
**Model family:** GPT-5.6 Sol only; effort selected by task difficulty  
**Remote push/release:** Not authorized  
**Status:** Copy-ready execution reference; send one task at a time

---

## 0. Governing sequence

```text
M5-B0
→ M5-G1
→ M5-SETUP-G1 only when M5-G1 returns SETUP REQUIRED
→ M5-G2 only after GO / CONDITIONAL GO
→ M5-G3
→ M5DBG-G1
→ M5A-G1
→ M5ADBG-G1
→ M5-CLOSE-G1
```

Conditional alternate:

```text
M5-G1 local source NO-GO or no usable quota window
→ explicit Founder decision
→ M5-WEB-G1 account-web fallback dossier
```

No task begins automatically.

Current accepted predecessor:

```text
Workspace:
/Users/juliushe/Developer/UMA-M4-Manus

Branch:
codex/uma-m4-manus

HEAD:
178e6ca47e514dc257ddd5db82a223e5eeb42b85

Tree:
1871b59ebe8ffdb59784292bf0a52cbde70e4925

Result:
M4 CLOSED — MANUS UNSUPPORTED — NO API-KEY PRODUCT PATH
```

Hard program policy:

```text
Local source first
Provider-controlled login permitted as fallback
External API-key input prohibited
Manual balance entry prohibited
Manual deduction prohibited
```

---

# 1. M5-B0 — Post-M4 baseline and governing-source installation

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Medium
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

TASK — UMA M5-B0: Post-M4 baseline, Claude worktree, and governing-source installation
```

## Result target

Create one clean M5 branch/worktree from the exact accepted M4-N closeout commit, install the four current M5 governing documents, verify source identity, and make no runtime, Claude configuration, provider, package, or installed-app change.

## Plan authority

Accepted predecessor:

- workspace: `/Users/juliushe/Developer/UMA-M4-Manus`;
- branch: `codex/uma-m4-manus`;
- HEAD: `178e6ca47e514dc257ddd5db82a223e5eeb42b85`;
- tree: `1871b59ebe8ffdb59784292bf0a52cbde70e4925`;
- worktree/index expected clean/empty;
- M4 closed;
- Manus unsupported;
- no API-key product path;
- Codex and WorkBuddy preserved.

## Required destination

```text
Branch:
codex/uma-m5-claude

Worktree:
/Users/juliushe/Developer/UMA-M5-Claude
```

If either exists, inspect it. Do not overwrite, reset, or discard legitimate work.

## Source input

Install exact supplied copies of:

```text
UMA_Logic_1.5.md
Scroll_2.1.md
M5_Plan.md
M5_Goal.md
```

Recommended destination:

```text
source/reference/
```

Do not rewrite their contents during installation.

## Preauthorized

- inspect canonical repository, worktrees, refs, status, index, ignored files, and exact predecessor commit/tree;
- verify the four supplied source files and their checksums when supplied;
- create branch `codex/uma-m5-claude` from exact accepted predecessor;
- create the durable worktree;
- add only the four governing Markdown files;
- run source-secret and consistency scans;
- stage exact four files;
- create one local docs commit after PASS:
  `docs(m5): install Claude local-source program`.

## Not authorized

- runtime or test edits;
- Claude installation;
- Claude login;
- Claude settings inspection beyond repository docs;
- status-line configuration;
- provider process launch;
- API key or token access;
- package build;
- installed-app replacement;
- push, PR, merge, tag, release, notarization, deployment, or publication.

## Execute

1. Verify the predecessor:
   - `git status --short --branch`
   - `git rev-parse HEAD`
   - `git rev-parse HEAD^{tree}`
   - `git diff --name-status`
   - `git diff --cached --name-status`
   - `git log --oneline --decorate -10`
2. Require exact predecessor commit and tree.
3. Confirm the M4-N runtime contains no Manus API-key path.
4. Create the branch/worktree from exact HEAD.
5. Copy the four source files to `source/reference/` without content mutation.
6. Verify:
   - exact file list;
   - byte identity/checksums;
   - no credentials or private data;
   - no runtime path changed;
   - `git diff --check`.
7. Stage exact four files only.
8. Perform independent cached-diff review.
9. Commit with the authorized subject.
10. Confirm clean worktree and empty index.

## PASS

- exact accepted parent preserved;
- durable M5 branch/worktree exists;
- four current source files installed exactly;
- no runtime/config/package/installed-app change;
- local docs commit exists;
- worktree clean and index empty;
- M5-G1 is the only next task.

## Final report

Verdict; model/authority; predecessor identity; new worktree/branch; exact source files and hashes; commit/tree; secret scan; no runtime/config mutation; final Git state; next task M5-G1 only; Completion Lock.

## Completion Lock

Stop. Do not inspect, install, launch, or configure Claude Code.

---

# 2. M5-G1 — Claude Code local source, authentication, and configuration dossier

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M5-G1 — Claude Code local status-line source, authentication, and configuration admission dossier
```

## Predecessor gate

Use only the accepted M5-B0 worktree:

```text
/Users/juliushe/Developer/UMA-M5-Claude
```

Expected branch:

```text
codex/uma-m5-claude
```

Require clean worktree and empty index before investigation.

## Result target

Produce a commit-exact, privacy-safe capability dossier proving whether the installed Claude Code CLI can supply current five-hour and/or seven-day plan usage through the official local status-line JSON without any external API key, copied token, transcript read, private-data access, or synthetic provider task.

Return exactly one:

```text
GO
CONDITIONAL GO
SETUP REQUIRED
NO-GO
```

No production connector is implemented in this Goal.

## Why now

Official current documentation defines a local structured status-line payload with plan rate-limit fields. The earlier Claude investigation returned NO-GO because the CLI was not installed on the then-current Mac. M5 must inspect current reality instead of carrying that historical absence forward.

## This is not

- relay implementation;
- main-panel integration;
- Desktop Assistant integration;
- account-web fallback;
- Anthropic API access;
- token setup;
- transcript parsing;
- Claude task execution;
- provider redesign.

## Governing source

Read:

- `source/reference/UMA_Logic_1.5.md`;
- `source/reference/Scroll_2.1.md`;
- `source/reference/M5_Plan.md`;
- current official Claude Code documentation.

Official documentation scope:

```text
status line
authentication
installation
settings
commands
```

## Preauthorized

- inspect the installed `claude` executable path, version, architecture, file identity, signature/trust evidence where supported, and safe help/version output;
- inspect only the Claude user/settings hierarchy required to locate the active `statusLine` object;
- inspect the `statusLine` object and `disableAllHooks` state without printing the full settings file;
- inspect whether provider-managed login is available through safe status classification;
- determine whether secret-based authentication appears active without reading or printing any secret;
- inspect official docs online;
- create one temporary task-owned local status-line probe only when the CLI is installed, authenticated, and exact backup/restore is feasible;
- capture only allowlisted field names/types and redacted values;
- wait for one Human-normal Claude interaction when required to obtain a provider-generated status-line event;
- create source dossier, admission decision, configuration/restore contract, Scope Lock, tests, and QA ledger;
- exact staging and one local docs/test commit after PASS.

## Not authorized

- install Claude Code;
- perform login;
- receive password, code, token, API key, cookie, or credential;
- read Keychain values or credential files;
- use `claude setup-token`;
- use `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`;
- add `apiKeyHelper`;
- open transcript files;
- read prompts, responses, tasks, tool output, source code, repository content, or workspace history;
- run a synthetic Claude task;
- retain raw payload;
- production relay or runtime implementation;
- push/release.

## Required installed-source evidence

1. executable found/not found;
2. executable path and version;
3. architecture and trust/signature evidence where available;
4. official install method classification;
5. authentication mode classification:
   - provider-managed Claude.ai subscription;
   - logged out;
   - API-key/secret-based method active;
   - enterprise/cloud mode;
   - unknown;
6. active settings source(s);
7. active status-line configuration present/absent;
8. `disableAllHooks` or managed-policy blocker present/absent;
9. previous status-line preservation feasibility;
10. exact restore feasibility.

Do not print the existing status-line command in the report.

## Required payload evidence

Classify:

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
version
```

For each:

```text
present and valid
present but malformed
absent on current account/session
unsupported
```

Also prove rejection of:

```text
session_id
session_name
prompt_id
transcript_path
workspace paths
repository/worktree data
account identity
raw JSON
```

## Temporary probe rules

If a probe is feasible:

1. create exact owner-only backup of the affected settings file;
2. install one task-owned allowlist probe;
3. do not log stdin;
4. do not open any path included in the payload;
5. capture only sanitized schema evidence;
6. preserve prior status-line output when present;
7. restore exact original settings immediately;
8. prove byte-equivalent restore;
9. delete probe artifacts after evidence extraction.

If current source requires one normal provider response, pause and request only:

```text
Use Claude Code normally once, then report that one response completed.
```

Do not ask for prompt text or output.

## Admission decision

### GO

- official local source proven;
- provider-managed login active;
- at least one valid quota window;
- strict privacy boundary feasible;
- reversible configuration feasible.

### CONDITIONAL GO

- one quota window valid;
- optional window absent;
- all security and restore conditions pass.

### SETUP REQUIRED

- CLI absent;
- login absent;
- no provider response has populated fields;
- exact official setup is the only missing condition.

### NO-GO

- no quota windows;
- only API-key/secret auth is usable;
- managed configuration blocks safe relay;
- prior status line cannot be preserved;
- only private data/UI scraping would work;
- semantics remain ambiguous.

## Required durable records

Recommended exact records:

```text
source/UMA M5 Claude Local Source Dossier.md
source/UMA M5 Claude Admission Decision.md
source/UMA M5 Claude Configuration and Restore Contract.md
source/UMA M5 Scope Lock.md
source/UMA M5 Claude QA Issue Ledger.md
Tests/CodexUsageUITests/M5G1ClaudeSourceAdmissionTests.swift
```

Create only records that add evidence.

## Subagents

- Source/Protocol Auditor: official schema and installed capability.
- Configuration Steward: settings hierarchy, backup, recursion, restore.
- Privacy Steward: field allowlist, forbidden data, artifact review.
- QA Runner: deterministic dossier tests and restore evidence.
- Examiner: independent GO / CONDITIONAL GO / SETUP REQUIRED / NO-GO decision.

## Verification

- focused source-contract tests;
- settings/restore fixture tests;
- secret and private-data scan;
- `git diff --check`;
- affected provider-neutral tests;
- independent staged-index audit;
- no runtime/source package change.

## Delivery

On GO, CONDITIONAL GO, or SETUP REQUIRED with a complete dossier:

```text
docs(m5): record Claude local-source capability
```

Do not commit raw payloads, config backups, private paths, screenshots, or real account values.

## PASS

- current capability is truthfully classified;
- no credential/private data accessed;
- exact setup or implementation gate is clear;
- dossier and tests pass;
- local commit exists;
- next task is one of:
  - M5-G2 after GO/CONDITIONAL GO;
  - M5-SETUP-G1 after SETUP REQUIRED;
  - Founder decision after NO-GO.

## FAIL / BLOCKED

Return FAIL only for evidence, privacy, restore, or repository failure.

Return BLOCKED only after all preauthorized read-only alternatives are exhausted and one consolidated Human action packet exists.

## Final report

Verdict; model/authority; Git state; CLI identity; auth classification; settings/status-line state; field capability table; private-field rejection; probe/restore evidence; tests; exact files; commit/tree; one next task; Completion Lock.

## Completion Lock

Stop. Do not install Claude, perform login, implement the relay, or activate account-web fallback.

---

# 3. M5-SETUP-G1 — Official Claude Code installation and provider-controlled login

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

LIVE SETUP TASK — UMA M5-SETUP-G1: Official Claude Code installation and provider-controlled login
```

## Queue gate

Run only when accepted M5-G1 returned `SETUP REQUIRED` and identified the exact missing condition.

This task itself must be sent by the Founder as the explicit authorization for installation/login work.

## Result target

Install the official Claude Code CLI when absent, allow the Human to complete provider-controlled subscription login, prove the local CLI is usable, and return to M5-G1 capability collection without exposing any credential or starting connector implementation.

## Authorized setup

When CLI is absent:

- use only the current official Claude Code native installer or another exact official installation method identified by M5-G1;
- install for the current user;
- verify executable path, version, architecture, and trust evidence;
- record file identity without publishing private paths beyond the normalized install path.

When login is absent:

- launch the official `claude` CLI;
- allow it to open the official provider-controlled browser login;
- pause for Human completion;
- receive only `login succeeded` or `login failed`;
- run a safe status check after completion.

## Human checkpoint

Return exactly:

```text
HUMAN ACTION REQUIRED — CLAUDE CODE LOGIN

1. Complete the login only in the official Claude/Anthropic page opened by Claude Code.
2. Do not paste a password, login code, token, API key, or screenshot into Codex or ChatGPT.
3. Return only: LOGIN SUCCEEDED or LOGIN FAILED.
```

Pause until the Human responds.

## Forbidden

- `claude setup-token`;
- `CLAUDE_CODE_OAUTH_TOKEN`;
- `ANTHROPIC_API_KEY`;
- Console API-key login for UMA;
- `apiKeyHelper`;
- reading Keychain or credential files;
- copying login URLs/codes into reports;
- reading prompts, responses, transcripts, tasks, or repositories;
- automatically sending a Claude prompt;
- status-line production configuration;
- runtime edits;
- staging/commit;
- push/release.

## Optional first event

If M5-G1 requires one provider response to expose `rate_limits`, request:

```text
Use Claude Code normally once. Return only: ONE RESPONSE COMPLETED.
```

Do not prescribe, capture, or read the prompt or response.

## Verification

- CLI resolves from expected path;
- version is supported;
- provider-managed login classification is safe;
- no secret-based environment/helper route was created by this task;
- no credential appears in logs, command output, or report;
- installed app and UMA repo remain unchanged except official Claude installation files.

## PASS

- required official setup completed;
- no credential exposed;
- M5-G1 may resume from installed/live capability stages.

## Final report

Verdict; missing condition before; exact official setup used; CLI identity after; login status only; privacy proof; no repo/runtime change; next task `Resume M5-G1`; Completion Lock.

## Completion Lock

Stop. Do not implement or configure the UMA relay.

---

# 4. M5-G2 — Reversible Claude status-line relay, connector, and Settings

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M5-G2 — Reversible Claude Code status-line relay, connector, and Settings
```

## Predecessor gate

Consume accepted M5-G1 GO or CONDITIONAL GO dossier.

If no admitted local source exists, return:

```text
QUEUE HELD — CLAUDE LOCAL SOURCE NOT ADMITTED
```

and stop.

## Result target

Implement a production-shaped offline Claude Code integration that sanitizes official status-line JSON at the boundary, publishes only current quota windows through a local socket, preserves the user’s existing status line, integrates one Claude connector into the existing registry/store, and provides bounded setup/repair/disable Settings.

No live user configuration is modified in this Goal unless explicitly required by a fixture-only test environment.

## Core path

```text
Claude Code statusLine JSON
→ ClaudeStatusLineRelay
├── prior user status-line command/output
└── strict quota allowlist
    → local Unix-domain socket
    → ClaudeCodeUsageConnector
    → AgentConnectorRegistry
    → UsageStore
    → shared presentation readiness
```

## Core contracts

1. No Anthropic API key or token.
2. No network request by relay or connector.
3. Raw JSON never reaches normal app storage or logs.
4. Transcript/session/workspace/account fields are rejected.
5. Existing status-line output is preserved.
6. Existing settings restore is exact.
7. One relay invocation per provider invocation.
8. One local listener and one connector.
9. No synthetic Claude request.
10. Missing windows remain unavailable.
11. Used percentages convert centrally to remaining.
12. Main/Assistant ownership remains shared and provider-neutral.
13. No disk quota snapshot by default.
14. Codex and WorkBuddy remain unchanged.

## Expected implementation areas

Bounded edits may include:

- Claude connector and relay protocol;
- helper executable target/source;
- connector registry;
- Claude models;
- source-state and presentation mapping;
- Settings coordinator/view/localization;
- installer/backup/restore helper;
- tests;
- package helper;
- M5 scope/QA records.

Do not branch UsageStore on provider name when the existing provider-neutral contract suffices.

## Preauthorized

- inspect/refactor bounded source modules;
- add the signed/auditable helper target;
- create fixture-only isolated Claude settings under task-owned temporary HOME;
- implement exact settings backup/restore logic;
- use local Unix sockets in task-owned paths;
- run focused/full tests and builds;
- automatic in-scope repair;
- create a commit-exact offline package;
- stage exact M5-G2 files;
- one local commit after PASS.

## Not authorized

- modify real `~/.claude/settings.json`;
- install the relay into the live user configuration;
- perform Claude login;
- read credentials;
- send Claude prompts;
- access transcript files;
- implement account-web fallback;
- install the candidate over Desktop UMA;
- push/release.

## Relay requirements

- deterministic strict JSON decoder;
- allowlist only the accepted version/rate-limit fields;
- bounded input and output size;
- no full payload logging;
- no network imports/calls;
- no broad filesystem access;
- owner-only socket/config permissions;
- app-not-running no-op;
- forward exact raw stdin to prior command through a pipe, not shell interpolation;
- capture/emit prior stdout unchanged;
- relay errors do not suppress prior output;
- recursion prevention;
- no helper daemon;
- clean termination.

## Sanitized packet requirements

- versioned schema;
- optional CLI version;
- optional five-hour window;
- optional seven-day window;
- precise used percentage;
- reset epoch;
- observation timestamp;
- no identity/private fields.

## Installer/restore requirements

- identify user-level settings target;
- exact owner-only backup;
- preserve prior `statusLine` object;
- preserve padding, interval, and options;
- record only nonsecret integration metadata in UMA Settings;
- install/repair/disable/restore deterministic;
- future schema fails closed;
- backup excluded from Git/package;
- no report output of prior command.

## Connector requirements

States:

```text
notInstalled
installedWaiting
fresh
stale
unsupported
failed
repairRequired
```

Behavior:

- one socket listener;
- one connector instance;
- bounded stale policy;
- no disk last-valid by default;
- source/config failure withdraws current admission;
- relay absence does not affect other providers;
- global Refresh performs health/eligibility only;
- Maximum Decrement input centralized.

## Settings requirements

Unconfigured:

```text
Claude Code
Official local status line
[ Check Claude Code ]
```

Ready to install:

```text
Claude Code detected
[ Enable Integration ]
```

Installed:

```text
Connected / Waiting for activity / Stale
Updated <time>
[ Repair Relay ] [ Disable Integration ]
```

Source Transparency:

```text
Credentials accessed by UMA: None
Network requests made by UMA: None
Transcript read: No
Raw payload stored: No
```

No API-key or token field exists.

## Required tests

### Decoder

- complete payload;
- five-hour only;
- seven-day only;
- both;
- missing `rate_limits`;
- nulls;
- 0/100/fractional;
- negative/overflow/out-of-range;
- wrong types;
- timestamp seconds/milliseconds/bounds;
- unknown fields;
- private fields rejected;
- malformed/oversized input.

### Relay

- prior command absent;
- simple prior command;
- complex quoting fixture;
- prior command failure;
- stdout preservation;
- stdin forwarding;
- recursion;
- socket unavailable/replaced;
- app absent;
- burst/cancellation;
- no network;
- no raw file/log;
- permissions;
- no orphan process.

### Configuration

- no settings file;
- empty settings;
- existing status line;
- padding/refresh interval/options;
- `disableAllHooks`;
- corrupt settings;
- managed/unsupported source;
- exact backup/restore;
- repair;
- uninstall;
- future schema.

### Connector

- unconfigured;
- waiting;
- fresh;
- stale;
- invalid packet;
- source failure;
- config removal;
- relaunch without disk quota;
- one listener/connector;
- no cross-provider overwrite;
- selected-window behavior.

### Privacy/package

- no credential strings;
- no API headers;
- no transcript reads;
- no raw payload persistence;
- no config backup in package;
- no socket/package artifact;
- helper provenance;
- system-only dependencies where required.

## Subagents

- Implementer: relay, connector, Settings.
- QA Runner: fixtures, builds, package.
- Configuration Steward: preservation/restore.
- Privacy Steward: boundary and package scan.
- Examiner: independent architecture and staged-index audit.

## Delivery

Commit:

```text
feat(connectors): add Claude Code status-line relay
```

Build one commit-exact offline package under `/private/tmp`.

## PASS

- production-shaped offline source exists;
- no real Claude config changed;
- helper/relay/connector/settings pass;
- no API/credential/private-data path exists;
- Codex and WorkBuddy regressions pass;
- commit-exact package passes;
- local commit exists;
- live status explicitly remains `NOT YET VALIDATED`;
- M5-G3 may begin.

## Final report

Verdict; model/authority; Git baseline; architecture; exact changed files; relay and prior-command behavior; socket protocol; connector states; Settings; tests/builds/package; privacy scan; QA repairs; commit/tree/package/hashes; explicit `LIVE CLAUDE QUOTA NOT YET VALIDATED`; M5-G3 admission; Completion Lock.

## Completion Lock

Stop. Do not modify live Claude settings, install the Desktop candidate, or begin M5-G3.

---

# 5. M5-G3 — Live Claude local-source and main-panel acceptance

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M5-G3 — Live Claude Code local-source, main-panel, and package acceptance
```

## Predecessor gate

Consume accepted M5-G2 commit-exact offline package.

Require:

- clean worktree;
- empty index;
- admitted local source;
- no external API-key route;
- exact restore contract;
- no unresolved privacy defect.

## Result target

Install the M5 relay into the real Claude Code user status-line configuration with exact backup, receive a real provider-generated sanitized quota event, show Claude Code as an independent main-panel provider beside Codex and WorkBuddy, validate failure/restore behavior, and produce one commit-exact package without installing it over the Founder’s Desktop app.

## Human configuration checkpoint

Before modifying real Claude settings:

1. build and validate the task-owned candidate;
2. report the exact settings file and nonsecret change class;
3. confirm an exact owner-only backup will be created;
4. ask the Human to approve `Enable Claude Integration` in the candidate or send the current Goal as authorization;
5. never request credentials.

When provider login is required, launch official Claude Code and pause for Human-controlled login.

## Live source authority

Allowed:

- modify only the exact active user-level Claude status-line setting;
- create one owner-only backup;
- install one M5 relay helper/config;
- receive local status-line events;
- wait for one normal Human Claude Code response when needed;
- no more than 45 minutes live validation;
- no synthetic task initiated by UMA/DEV;
- no provider API request by UMA;
- no credential access.

## Not authorized

- Anthropic API key or copied token;
- `claude setup-token`;
- transcript/session/workspace reads;
- project settings changes unless the accepted dossier explicitly requires and the Human separately approves them;
- account-web fallback;
- installed Desktop UMA replacement;
- push/release.

## Required live acceptance

1. exact backup created before config change;
2. relay enabled successfully;
3. existing status-line output remains equivalent;
4. first sanitized packet contains only approved fields;
5. at least one valid quota window is observed;
6. UMA converts used to remaining correctly;
7. reset epoch is correct;
8. selected window matches centralized Maximum Decrement;
9. raw payload is not stored;
10. no transcript path is opened;
11. no network request comes from UMA relay/connector;
12. no duplicate helper/listener appears.

## Required main-panel behavior

Stable order:

```text
Codex
Claude Code
WorkBuddy
```

Collapsed Claude card:

- Claude Code;
- selected remaining percentage;
- selected window;
- source/freshness mark.

Expanded:

- five-hour remaining/reset when present;
- seven-day remaining/reset when present;
- source `Official local status line`;
- updated time;
- repair/Settings actions.

No:

- session context;
- cost;
- transcript;
- repository;
- account identity;
- API key;
- manual value.

## Required state matrix

- waiting before first event;
- five-hour only;
- seven-day only;
- both windows;
- fresh;
- bounded stale;
- Claude CLI closed;
- logout/source unavailable;
- relay disabled;
- malformed local event;
- repair;
- exact disable/restore;
- re-enable;
- one provider failure while Codex/WorkBuddy remain healthy.

## Restore test

Perform one bounded disable/restore test:

- remove UMA wrapper;
- restore exact original status-line object;
- prove prior output/config equivalence;
- re-enable only if final accepted state requires it;
- never lose the backup before final proof.

## Verification

- focused M5-G3 live tests;
- all Claude suites;
- provider registry/store tests;
- Codex regressions;
- WorkBuddy regressions;
- main-panel/Settings/localization/accessibility tests;
- full suite;
- Debug build;
- Release build;
- strict-concurrency Release;
- commit-exact package;
- signature/dependency/manifest/privacy/provenance scans;
- no config backup or raw payload in package.

## Automatic repair

Repair all in-scope blocking, major, and acceptance-required minor defects.

Maintain the M5 QA Issue Ledger.

Do not replace failed live evidence with fixtures.

## Delivery

Commit:

```text
feat(m5): show Claude Code usage in main panel
```

Build final package:

```text
/private/tmp/uma-m5-g3-final-<commit>/UMA.app
```

Do not install over `/Users/juliushe/Desktop/UMA_0.11.app`.

## PASS

- live local Claude quota observed;
- at least one valid plan window;
- main-panel Claude card correct;
- existing status line preserved/restorable;
- no credential/private-data/API path;
- Codex and WorkBuddy remain functional;
- package/privacy/resources pass;
- local commit exists;
- M5DBG-G1 may begin.

## PASS WITH RISKS

Allowed only when one optional quota window is absent but the other current window and all privacy/config contracts pass.

## FAIL

- no usable quota window;
- credential/private-data leak;
- prior status line cannot be restored;
- synthetic provider task required;
- source/package/privacy failure;
- provider cross-contamination.

## Final report

Verdict; model/authority; predecessor; candidate identity; Human checkpoint; config backup/restore; observed field availability; sanitized event count; main-panel behavior/order; state matrix; no-network/no-private-data proof; tests/build/package; QA repairs; final commit/tree/package/hashes; installed app unchanged; M5DBG admission; Completion Lock.

## Completion Lock

Stop. Do not start M5DBG, Assistant integration, fallback login, push, or installation.

---

# 6. M5 Quick Patch rule

Confirmed narrow M5 defects use Quick Patch Mode.

Examples:

- one Claude field decode;
- one timestamp boundary;
- one status copy issue;
- one socket reconnect bug;
- one relay permission bug;
- one layout clipping defect;
- one localization correction.

Do not create a new milestone Goal for one narrow defect.

Quick Patch must not:

- change source class;
- weaken privacy;
- add API access;
- add account-web fallback;
- redesign the panel;
- alter Codex or WorkBuddy transport.

---

# 7. M5DBG-G1 — Three-provider main-app debugging

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M5DBG-G1 — Codex + Claude Code + WorkBuddy main-app debugging and commit-exact acceptance
```

## Predecessor gate

Consume accepted M5-G3 commit/package and live source evidence.

## Result target

Stress, repair, and qualify the three-provider main app before Claude enters the Desktop Assistant.

## Required matrix

### Provider combinations

- all three fresh;
- Claude waiting while Codex/WorkBuddy fresh;
- Claude stale while others fresh;
- Claude failed while others fresh;
- Codex failed while Claude/WorkBuddy remain;
- WorkBuddy failed while Codex/Claude remain;
- all unavailable;
- stable provider order under all states.

### Claude relay/configuration

- 50 sanitized events;
- burst/coalesced events;
- malformed events;
- socket replacement;
- app relaunch;
- relay repair;
- disable/restore/re-enable;
- prior command success/failure;
- `disableAllHooks` or config change during run;
- logout/login-required transition;
- no duplicate listener/helper;
- no raw payload or backup leak.

### Refresh

- 30 global Manual Refresh actions;
- zero synthetic Claude requests;
- at most one Codex refresh per action;
- at most one WorkBuddy read per action;
- Claude health check only;
- no cadence multiplication;
- no read storm.

### Lifecycle

- 20 app relaunches;
- 50 main-panel cycles;
- 30 Settings/Agent Settings cycles;
- clean shutdown;
- no orphan child/helper/socket.

### Presentation

- one/two windows;
- reset transitions;
- stale source mark;
- expansion persistence;
- Show All/Hide All;
- EN/zh-CN;
- Light/Dark/accessibility;
- no card reorder.

### Resource run

30–60 minutes:

- CPU;
- RSS;
- threads;
- descriptors;
- sockets;
- helper invocations;
- file writes;
- Codex children;
- WorkBuddy WebView/timer;
- Claude listeners/helpers.

## Live authority

- use normal local Claude events only;
- no automated prompt generation;
- no API/credential access;
- no account-web fallback;
- maximum 90 minutes total task duration.

## Preauthorized

- narrow source/test/config/package repairs;
- exact config backup/restore;
- automatic in-scope repair;
- exact staging and one local commit;
- commit-exact package.

## Not authorized

- new source method;
- API key/token;
- account-web login;
- Assistant integration;
- installed-app replacement;
- push/release.

## QA Issue Ledger

Required fields:

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

## Delivery

Runtime repair commit when required:

```text
fix(m5): close three-provider main-panel defects
```

Create:

```text
source/UMA M5A Claude Assistant Handoff.md
```

## PASS

- no blocking/major main-app defect;
- Claude local source stable and reversible;
- no credential/private-data path;
- Codex and WorkBuddy independent;
- resources/package/privacy pass;
- M5A-G1 may begin.

## Final report

Full Goal report per Goal Mode 2.0, including exact event/read counts, resource series, config state, QA ledger, commit/package, and M5A admission.

## Completion Lock

Stop. Do not begin Assistant integration automatically.

---

# 8. M5A-G1 — Claude Code in Desktop Assistant

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

TASK — UMA M5A-G1: Add Claude Code shared presentation to Desktop Assistant
```

## Predecessor gate

Consume accepted M5DBG handoff.

## Result target

Add Claude Code as the second-priority Assistant row using the accepted shared `AgentCardViewModel`, with no Claude relay, socket, configuration, observer, timer, or source logic inside Assistant code.

## Required behavior

- stable visible order `Codex → Claude Code → WorkBuddy`;
- one Claude row only;
- independent source/connection state;
- independent remaining percentage;
- selected-window parity with main panel;
- tooltip/VoiceOver includes window, reset, freshness, and source;
- Regular and Minimalist rules unchanged;
- no geometry redesign beyond bounded fitting;
- row action routes by stable connector ID;
- Assistant show/hide does not affect Claude relay/listener/config;
- one provider failure does not affect other rows.

## Scope

Bounded edits:

- Assistant shared presentation mapping;
- provider asset/mark;
- localization/accessibility;
- navigation/action delegation;
- focused tests;
- package/QA records.

Claude transport/configuration remains read-only.

## Preauthorized

- bounded UI/tests/docs edits;
- focused/full tests and builds;
- appearance/accessibility fixtures;
- automatic repair;
- exact staging and one local commit;
- commit-exact package.

## Not authorized

- relay/socket/config edits;
- provider login;
- source method change;
- account-web fallback;
- broad visual redesign;
- installed-app replacement;
- push/release.

## Required tests

- 0/1/2/3 admitted providers;
- Claude one/two-window states;
- fresh/stale/failed/waiting;
- stable order;
- main/Assistant parity;
- Regular/Minimalist;
- long localization;
- Light/Dark;
- Reduce Transparency/Increase Contrast/Reduce Motion;
- EN/zh-CN;
- VoiceOver;
- lifecycle/position/focus;
- no Assistant source ownership;
- no provider-read multiplication.

## Delivery

Commit:

```text
feat(assistant): add Claude Code shared presentation
```

## PASS

- Claude appears correctly through shared presentation;
- no source ownership added to Assistant;
- Codex/WorkBuddy unchanged;
- tests/build/package pass;
- M5ADBG-G1 may begin.

## Final report

Verdict; behavior; exact files; tests; ownership proof; commit/package; remaining risks; Completion Lock.

## Completion Lock

Stop. Do not begin combined closeout automatically.

---

# 9. M5ADBG-G1 — Three-provider combined closeout

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M5ADBG-G1 — Codex + Claude Code + WorkBuddy combined closeout
```

## Predecessor gate

Consume accepted M5A commit/package and M5DBG evidence.

## Result target

Close the Claude program with exact live main-panel/Desktop Assistant parity, independent provider lifecycle, reversible Claude configuration, bounded resources, accessibility, privacy, and one commit-exact package.

## Required combined matrix

### Surface parity

- exact visible provider IDs;
- exact Claude value/window/reset/state parity;
- fresh/stale/failed/waiting parity;
- stable `Codex → Claude → WorkBuddy` order;
- expansion and row navigation.

### Provider states

- all fresh;
- each provider failed independently;
- Claude one-window/two-window;
- Claude inactive/stale;
- Claude relay disabled/repaired;
- app relaunch before/after provider event;
- WorkBuddy auth expiry;
- Codex child recovery.

### Assistant lifecycle

- 100 show/hide cycles;
- position restore;
- Always on Top;
- focus behavior;
- density transitions;
- zero empty shell;
- no source ownership.

### Refresh ownership

- global Refresh;
- WorkBuddy timer;
- Claude provider events;
- no cross-provider duplication;
- no Assistant multiplication.

### Claude configuration lifecycle

- exact backup exists while needed;
- repair;
- disable/restore;
- re-enable;
- no command disclosure;
- no raw payload;
- no credential access;
- final accepted integration state documented.

### Appearance/accessibility

- Light/Dark;
- Reduce Transparency;
- Increase Contrast;
- Reduce Motion;
- EN/zh-CN;
- keyboard;
- VoiceOver;
- Settings scrolling;
- source transparency.

### Endurance

45–60 minutes with bounded samples:

- CPU/RSS;
- threads/descriptors/sockets;
- helper invocation count;
- file writes;
- Codex child count;
- WorkBuddy WebView/timer/read count;
- Claude listener/helper count;
- clean termination.

### Package

- exact commit provenance;
- helper provenance;
- signature/dependencies;
- no credentials/tokens;
- no raw payload;
- no transcript/session/workspace data;
- no config backup;
- no socket/log/screenshot/test/fixture.

## Live authority

- provider-generated Claude local events only;
- no API key/token;
- no synthetic automation prompt;
- no account-web fallback;
- maximum 120 minutes total execution.

## Preauthorized

- narrow runtime/test/config/package repair;
- exact config backup/restore;
- automatic repair;
- exact staging and local commits;
- commit-exact package;
- closeout docs.

## Not authorized

- another provider;
- account-web fallback;
- API route;
- installed-app replacement;
- push, PR, merge, release, notarization, deployment, or publication.

## Subagents

- Implementer;
- QA Runner;
- Configuration Steward;
- Privacy Steward;
- Performance Auditor;
- Accessibility/Localization Auditor;
- Examiner.

## Delivery

Runtime repair when required:

```text
fix(m5): close Claude combined defects
```

Docs closeout:

```text
docs(m5): close Claude Code program
```

Create:

```text
source/UMA M5 Claude Closeout.md
source/UMA M5 Claude QA Issue Ledger.md
source/UMA M6 Antigravity Handoff.md
```

## PASS

- Claude local source fully accepted;
- no external API-key route;
- exact main/Assistant parity;
- reversible config;
- no privacy leak;
- resources/package/Git pass;
- no blocking/major defect;
- M5-CLOSE-G1 may update current sources;
- M6 remains unstarted.

## PASS WITH RISKS

Allowed only for one absent optional quota window or a documented external old-OS/provider variability that does not break the accepted core.

## FAIL

- required live local source absent;
- credential/private-data leak;
- config restore failure;
- source ownership duplicated;
- package/privacy/resource failure;
- tests incomplete.

## Final report

Full milestone report with exact Git, live source, surface parity, config lifecycle, event/read/resource counts, QA ledger, package, risks, and M5-CLOSE admission.

## Completion Lock

Stop. Do not start M6, install the package, or push.

---

# 10. M5-WEB-G1 — Conditional Claude account-web fallback dossier

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: Extra High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

/goal UMA M5-WEB-G1 — Claude isolated account-web usage-source dossier
```

## Queue gate

Do not run unless:

1. M5-G1 returned local-source NO-GO or no usable quota windows;
2. the Founder explicitly authorizes this Goal;
3. no API-key route is proposed.

Otherwise return:

```text
QUEUE HELD — LOCAL CLAUDE SOURCE REMAINS PRIMARY OR FALLBACK NOT AUTHORIZED
```

and stop.

## Result target

Determine whether an official Claude account page can provide current plan usage through the Logic 1.5 isolated provider-controlled login model.

Return GO / CONDITIONAL GO / NO-GO.

Do not implement the production fallback in this Goal.

## Allowed investigation

- current official Claude account/help documentation;
- official login and usage-page routes;
- isolated task-owned WKWebView prototype with nonpersistent session;
- Human-controlled provider login;
- exact domain/route mapping;
- bounded usage-field inventory;
- read-only extraction feasibility;
- safe session clear/disconnect proof;
- fixture/schema tests;
- docs-only commit.

## Forbidden

- API key/token;
- browser cookie import;
- Safari/Chrome session reuse;
- Keychain inspection;
- raw cookie/storage export;
- private app databases;
- broad DOM/page capture;
- task/chat/history collection;
- billing/orders;
- account mutation;
- production connector implementation;
- manual value;
- push/release.

## Admission requirements

GO requires:

- official provider-controlled login;
- exact official usage route;
- current plan usage supplied directly;
- clear units/windows/reset semantics;
- no credential visible to UMA;
- narrow field allowlist;
- deterministic route-bound extraction;
- nonpersistent default session;
- Disconnect and Clear;
- no account mutation;
- fail-closed behavior.

NO-GO when:

- only API access exists;
- only UI/OCR/Accessibility scraping works;
- usage page cannot be bounded;
- identity/task/billing data cannot be avoided;
- current usage semantics are ambiguous.

## Required durable records

```text
source/UMA M5 Claude Account Web Dossier.md
source/UMA M5 Claude Account Web Admission Decision.md
source/UMA M5 Claude Account Web Privacy Contract.md
source/UMA M5 Web Scope Lock.md
source/UMA M5 Web QA Issue Ledger.md
```

## Delivery

Commit:

```text
docs(m5): evaluate Claude account-web fallback
```

## Completion Lock

Stop. Do not implement the fallback or restart the local source route automatically.

---

# 11. M5-CLOSE-G1 — Governing-source update and milestone closeout

```text
MODEL: GPT-5.6 Sol | THINKING EFFORT: High
AUTHORITY PROFILE: LOCAL_FULL_THROTTLE

TASK — UMA M5-CLOSE-G1: Update current sources and close the Claude Code milestone
```

## Predecessor gate

Run only after accepted M5ADBG closeout, or after an explicit Founder decision to close M5 as unsupported following completed local and optional fallback dossiers.

## Result target

Update current governing sources to exact M5 truth, record the accepted provider status, retire stale M5 planning clauses, and hand off the next selected program without starting it.

## Required updates

- current milestone/status block in Scroll;
- Claude provider contract/status in Logic;
- provider feasibility/status matrix if current;
- M5 closeout summary;
- latest accepted commit/tree/package;
- live versus unproven fields;
- config/restore ownership;
- remaining risks;
- next-provider recommendation.

## Current-truth rule

Do not claim:

- a missing Claude quota window exists;
- account-web fallback is shipped when it is not;
- installed Desktop app was replaced when it was not;
- remote push/release occurred when it did not.

## Next milestone decision

Default recommendation after M5 PASS:

```text
M6 — Google Antigravity local status-line source admission
```

Do not start M6.

## Preauthorized

- docs/source/tests required for source consistency;
- exact staging;
- one local docs commit;
- no runtime change unless a narrow closeout defect is explicitly found and repaired under Quick Patch.

## Not authorized

- M6 implementation;
- installed-app replacement;
- push/release.

## Delivery

Commit:

```text
docs(m5): record Claude Code closeout
```

## PASS

- current docs match live accepted state;
- stale directions retired;
- one next recommendation recorded;
- clean Git state;
- Completion Lock.

## Final report

Verdict; exact updates; provider state; commit/tree; one next recommendation; no M6 start; Completion Lock.

## Completion Lock

Stop.

---

## 12. Copy/run rule

```text
Send one task
→ receive the report
→ review claim-matched evidence
→ accept or return one correction
→ send the next task only after acceptance
```

Do not paste the complete file into one execution turn.
