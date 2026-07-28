# Usage Monitor Altoget — M5 Plan

**Program:** M5 — Claude Code Local Structured Usage Support  
**Version:** 1.0  
**Date:** 2026-07-28  
**Language:** English  
**Product:** UMA — Usage Monitor Altoget  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Accepted predecessor workspace:** `/Users/juliushe/Developer/UMA-M4-Manus`  
**Accepted predecessor branch:** `codex/uma-m4-manus`  
**Accepted predecessor commit:** `178e6ca47e514dc257ddd5db82a223e5eeb42b85`  
**Accepted predecessor tree:** `1871b59ebe8ffdb59784292bf0a52cbde70e4925`  
**Expected M5 branch:** `codex/uma-m5-claude`  
**Expected M5 worktree:** `/Users/juliushe/Developer/UMA-M5-Claude`  
**Execution standard:** Goal Mode 2.0  
**Default model family:** GPT-5.6 Sol  
**Remote push/release:** Not authorized  
**Status:** Active M5 planning authority after installation; implementation starts only through one exact M5 Goal

---

## 0. Plan authority

This plan consumes:

- qualified UMA 0.11 behavior;
- accepted Codex and WorkBuddy production contracts;
- M4-N closeout and API-route retirement;
- UMA Logic 1.5;
- Scroll 2.1;
- Goal Mode 2.0;
- current official Claude Code documentation.

Current product state:

```text
Codex                                  LIVE-QUALIFIED
WorkBuddy                              LIVE-QUALIFIED / EXPERIMENTAL ACCOUNT WEB
Manus                                  CLOSED / UNSUPPORTED
External API-key provider routes       PROHIBITED
Manual balance routes                  PROHIBITED
Claude Code                            M5 NEXT
```

The phrase `offline API support` is interpreted as:

```text
official local structured interface
```

It does not authorize an Anthropic API key, an Anthropic API client, OAuth-token input, setup tokens, or a provider-account API call from UMA.

---

## 1. Why Claude Code is next

Claude Code is the strongest currently documented local-source candidate after Codex.

The official status-line contract:

- runs a configured local command;
- sends structured JSON through stdin;
- includes five-hour and seven-day rate-limit fields when available;
- supplies reset epochs;
- is event-driven;
- can optionally re-run on a local refresh interval;
- is managed by Claude Code’s own authenticated session;
- requires no external API key in UMA.

The official documented quota fields are:

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
```

Each window may be independently absent.

`rate_limits` may be absent before the first Claude response or for an unsupported account/authentication mode.

The payload also contains private or irrelevant fields. M5 must reject them before data reaches UMA.

---

## 2. Current source and authentication findings

### 2.1 Preferred source

```text
Claude Code official statusLine invocation
→ structured JSON on stdin
```

Source class:

```text
officialLocalStatusLine
```

### 2.2 Authentication

Claude Code manages authentication.

Accepted M5 route:

```text
Human installs/opens Claude Code
→ Human completes official provider-controlled browser login
→ Claude Code retains its own authenticated session
→ status-line payload includes supported quota fields
→ UMA receives only sanitized quota fields
```

UMA must not:

- receive an Anthropic API key;
- receive a Claude setup token;
- receive an OAuth token;
- inspect Claude credentials in macOS Keychain;
- read Claude credential files;
- import browser cookies;
- set cloud-provider environment credentials;
- add an `apiKeyHelper`.

### 2.3 Account capability

The official documentation states that `rate_limits` is present for supported Claude.ai subscription sessions after the first provider response. M5 must test the installed account rather than assuming capability.

Possible results:

```text
GO
→ five-hour and/or seven-day quota is present and source is safe

CONDITIONAL GO
→ one useful quota window is present; optional window/detail is absent

SETUP REQUIRED
→ CLI or provider-managed login is absent

NO-GO
→ installed source cannot supply plan quota safely
```

### 2.4 Account-web fallback

Login is now an accepted fallback source class, but it is not the primary M5 route.

A Claude account-web fallback may be investigated only when:

- the local status-line route returns NO-GO or supplies no usable quota window;
- the Founder explicitly activates `M5-WEB-G1`;
- the fallback uses an isolated provider-controlled login;
- no API key is used.

---

## 3. M5 result target

At M5ADBG closeout, the accepted product should provide:

1. real Codex usage;
2. real Claude Code supported plan limits;
3. real WorkBuddy Credits;
4. one host application and status item;
5. one shared connector per provider;
6. stable provider order `Codex → Claude Code → WorkBuddy`;
7. independent source, state, freshness, and failure;
8. one shared main-panel/Desktop Assistant presentation path;
9. no external API-key input;
10. no Claude transcript, session, repository, or identity data;
11. reversible Claude status-line configuration;
12. commit-exact package, privacy, resource, and recovery evidence.

M5 may close with one Claude quota window absent when the source honestly exposes at least one current supported plan window.

M5 may not fabricate missing windows.

---

## 4. This milestone is not

M5 does not include:

- Anthropic API access;
- `ANTHROPIC_API_KEY` configuration;
- `CLAUDE_CODE_OAUTH_TOKEN` configuration;
- `claude setup-token`;
- Claude Console API billing;
- Bedrock, Vertex, or Foundry credential integration;
- Claude transcript or conversation reading;
- current-session cost or context as a substitute for plan quota;
- source-code or workspace collection;
- account identity display;
- account-web fallback implementation unless `M5-WEB-G1` is separately activated;
- WorkBuddy redesign;
- broad UMA visual redesign;
- public release or notarization;
- another provider.

---

## 5. Architecture

### 5.1 Required path

```text
Claude Code
→ official statusLine command
→ UMA ClaudeStatusLineRelay
├── preserve the prior status-line command/output
└── strict quota allowlist
    → local Unix-domain socket
    → ClaudeCodeUsageConnector
    → AgentConnectorRegistry
    → serialized UsageStore
    → SharedUsagePresentationPolicy
    ├── main panel
    └── Desktop Assistant after M5A
```

### 5.2 Why a relay is required

The official payload includes both useful and private fields.

UMA must sanitize at the boundary, before the main application receives the payload.

The relay is responsible for:

- reading stdin once;
- decoding only the approved fields;
- rejecting malformed values;
- emitting one bounded sanitized packet;
- forwarding the exact original JSON to the prior status-line command when one exists;
- preserving prior stdout behavior;
- persisting no raw payload;
- making no network request.

### 5.3 Relay implementation preference

Preferred:

- a small auditable Swift helper;
- source-controlled and package-provenanced;
- installed under the app’s established Application Support compatibility domain;
- restrictive owner-only permissions;
- no network entitlement;
- no broad filesystem scanning;
- no logging of stdin;
- no shell interpolation for payload data.

A shell script is allowed only when the capability dossier proves it is equally safe and does not introduce a dependency such as `jq` that is absent on supported systems.

### 5.4 Local transport

Preferred:

```text
Unix-domain socket
```

Requirements:

- app-owned path;
- owner-only permissions;
- bounded packet size;
- versioned sanitized schema;
- one listener;
- no raw payload file;
- relay succeeds as a no-op when UMA is not running;
- socket replacement/reconnect is deterministic.

A normalized disk snapshot is not part of M5 by default.

### 5.5 Existing status-line preservation

Before modifying Claude settings:

1. identify the active user settings path;
2. inspect the `statusLine` object only;
3. create one exact owner-only backup outside Git;
4. preserve type, command, padding, refresh interval, and relevant options;
5. prevent recursive wrapper calls;
6. retain prior output;
7. restore exactly on failure, disable, or uninstall.

Do not print the prior command in reports.

If the existing status-line command contains an obvious literal credential or cannot be safely executed through the wrapper, stop and request Human resolution.

### 5.6 Connector

The Claude connector owns:

- sanitized socket event decoding;
- schema version negotiation;
- source health;
- current/stale/failed state;
- used-to-remaining conversion;
- reset epochs;
- Maximum Decrement input;
- last-success timestamp;
- relay install/repair/disable actions;
- no network request.

### 5.7 Shared presentation

The first accepted Claude presentation includes only:

- provider name;
- five-hour remaining when present;
- seven-day remaining when present;
- selected display window;
- reset time;
- source/freshness state;
- last provider event;
- safe setup/repair actions.

Do not include context-window usage, current-session tokens, session cost, workspace, branch, repository, transcript, or identity in M5.

---

## 6. Source-admission contract

### 6.1 GO

GO requires:

- official CLI installed and trusted;
- current version identified;
- provider-managed login usable;
- official status-line source confirmed;
- current structured payload observed;
- at least one valid plan-limit window;
- reset semantics proven;
- no API key or token required by UMA;
- strict privacy allowlist feasible;
- existing status-line configuration can be preserved and restored;
- no provider request initiated by UMA.

### 6.2 CONDITIONAL GO

Allowed when:

- one of five-hour or seven-day is valid;
- the other window or optional version detail is absent;
- the core current remaining-usage result remains honest;
- no privacy or authentication boundary is weakened.

### 6.3 SETUP REQUIRED

Return when:

- Claude Code CLI is not installed;
- CLI is installed but user is not logged in;
- no provider response has yet populated `rate_limits`;
- official installation/login action is required before capability can be decided.

SETUP REQUIRED is not a source NO-GO.

### 6.4 NO-GO

Return when:

- only API-key authentication is active and no accepted subscription source exists;
- no quota window is supplied;
- status-line configuration cannot be preserved;
- managed policy blocks the required configuration;
- only transcript, UI scraping, or private state could provide the value;
- payload semantics remain ambiguous;
- source would require a synthetic task initiated by UMA.

### 6.5 Fallback decision

After NO-GO, the Founder chooses one:

```text
A. activate M5-WEB-G1 account-login fallback dossier
B. keep Claude unsupported
C. pause provider expansion
```

No fallback begins automatically.

---

## 7. Data contract

### 7.1 Sanitized packet

Conceptual packet:

```swift
struct ClaudeQuotaRelayPacket: Equatable, Sendable, Codable {
    let schemaVersion: Int
    let claudeCodeVersion: String?
    let fiveHour: ClaudeQuotaWindow?
    let sevenDay: ClaudeQuotaWindow?
    let observedAt: Date
}

struct ClaudeQuotaWindow: Equatable, Sendable, Codable {
    let usedPercent: Decimal
    let resetsAt: Date
}
```

Actual names may differ.

### 7.2 Validation

- used percentage must be finite and within `0...100`;
- reset timestamp must be valid Unix seconds;
- millisecond or impossible timestamps fail closed;
- each window is independent;
- missing window is unavailable, not zero;
- unknown fields are ignored before publication;
- malformed top-level JSON produces no packet;
- packet size is bounded.

### 7.3 Remaining conversion

```text
remainingPercent = 100 - usedPercent
```

Preserve sufficient precision for selection and round only at presentation.

### 7.4 Forbidden payload handling

The relay must not publish or persist:

- `session_id`;
- `session_name`;
- `prompt_id`;
- `transcript_path`;
- workspace paths;
- Git repository or branch;
- worktree paths;
- model prompt/response;
- token categories;
- tool activity;
- account identity;
- raw JSON.

### 7.5 No AI parsing

Schema parsing is deterministic.

No LLM interprets status-line output.

---

## 8. Authentication and setup design

### 8.1 Supported authentication path

```text
Claude Code official CLI
→ provider-controlled browser login
→ Claude Code-managed subscription session
```

UMA receives no credential.

### 8.2 Unsupported authentication paths

M5 does not accept:

- environment API key;
- Console API key;
- long-lived setup token;
- copied OAuth token;
- `apiKeyHelper`;
- cloud-provider credentials installed for UMA.

If a secret-based method is active, report only the safe classification. Do not read or print the value.

### 8.3 Official installation

When installation is required:

- use the current official native installer only;
- require an exact Human-authorized setup Goal;
- verify installed executable path, version, architecture, and signature where supported;
- do not install unrelated Node/npm tooling;
- do not modify shell profiles beyond the official installer’s required behavior without explicit disclosure.

### 8.4 Human login checkpoint

The Human:

1. opens Claude Code;
2. completes the official provider-controlled browser flow;
3. reports only success/failure;
4. does not send credentials, login codes, tokens, or screenshots containing private data to DEV.

### 8.5 First quota event

`rate_limits` may require a completed Claude provider response.

Preferred evidence:

- wait for the Founder’s next normal Claude Code use;
- capture the resulting sanitized status-line event.

A synthetic prompt must not be initiated automatically by UMA or DEV.

A single Human-chosen minimal prompt may be used only under an exact live-validation instruction.

---

## 9. Refresh, freshness, and lifecycle

### 9.1 Primary cadence

```text
provider event-driven
```

Claude Code invokes the status line after supported session events.

### 9.2 Optional refresh interval

A status-line `refreshInterval` may re-run the local command without a model request.

M5 must not silently overwrite an existing interval.

Possible policy after admission:

```text
preserve existing interval
or
leave event-driven when absent
```

Do not add a one-second timer.

### 9.3 Manual Refresh

Application-wide Manual Refresh may:

- verify relay installation;
- verify socket health;
- consume the current in-memory sanitized state;
- re-run provider eligibility.

It must not send a Claude prompt or invoke an Anthropic API.

### 9.4 Stale state

When Claude Code is inactive after a valid in-memory event:

- retain the current value for a bounded provider-specific interval;
- mark it stale visibly;
- retain last-success time;
- do not call it current.

After UMA relaunch:

- no disk snapshot is loaded by default;
- Claude remains hidden/waiting until the next valid event.

### 9.5 Logout or configuration removal

- withdraw admission;
- stop listening only when integration is disabled;
- preserve other providers;
- show safe Settings state;
- do not inspect credentials.

### 9.6 Termination

App termination:

- closes the socket;
- stops task-owned listeners;
- leaves Claude configuration installed only when the integration remains enabled;
- persists no raw payload;
- leaves no helper process running.

---

## 10. Main-panel UX

### 10.1 Unconfigured

```text
Claude Code
Official local status line

Not configured

[ Check Claude Code ]
```

### 10.2 CLI missing

```text
Claude Code is not installed.

[ Installation Guide ]
[ Check Again ]
```

### 10.3 Login required

```text
Sign in through Claude Code.
UMA never receives your Claude credentials.

[ Open Claude Code ]
[ Check Again ]
```

### 10.4 Waiting for first event

```text
Waiting for Claude Code usage data.
Use Claude Code normally, then check again.
```

Do not ask the user to create activity repeatedly.

### 10.5 Collapsed provider card

Show:

- Claude Code;
- selected remaining percentage;
- selected window;
- source-state mark;
- last-update age when useful.

### 10.6 Expanded details

Show only supported values:

```text
5-hour remaining        <value>   Reset <time>
7-day remaining         <value>   Reset <time>
Source                   Official local status line
Updated                  <relative time>
```

Actions:

- Check Again;
- Repair Relay;
- Agent Settings;
- Disable Integration.

### 10.7 Failure

Use concise safe errors:

```text
Claude Code not installed
Sign in required
Waiting for first Claude response
Status-line integration disabled
Current quota data unavailable
Managed settings prevent configuration
```

No private paths, command text, session ID, or payload fragments appear in ordinary UI.

---

## 11. Desktop Assistant UX

### 11.1 Entry gate

Claude enters the Assistant only after M5DBG accepts the main-app connector.

### 11.2 Order

```text
Codex
Claude Code
WorkBuddy
```

### 11.3 Regular

Show:

- provider mark;
- Claude Code;
- selected remaining percentage;
- selected window;
- optional reset/update information.

### 11.4 Minimalist

Show:

```text
source/connection-state mark
→ remaining percentage
```

Window and reset remain in tooltip/VoiceOver.

### 11.5 Ownership

The Assistant owns no relay, socket, config backup, Claude process, timer, or source cache.

---

## 12. Account-web fallback design — conditional only

### 12.1 Trigger

`M5-WEB-G1` is considered only after local source NO-GO or proven metric insufficiency.

### 12.2 Dossier result

The dossier must determine whether an official Claude account page exposes current five-hour/seven-day or equivalent plan usage through a bounded read-only route.

### 12.3 Required security

- provider-controlled official login;
- isolated WKWebView;
- no browser cookie import;
- nonpersistent session by default;
- exact domains/routes;
- usage-only field allowlist;
- no identity, billing, tasks, chats, or model history;
- manual-only refresh by default;
- Disconnect and Clear;
- no API key.

### 12.4 No automatic implementation

The fallback dossier is documentation/source-admission only.

A separate implementation plan is required after GO.

---

## 13. Privacy and security

### 13.1 Allowed Claude data

Only:

- Claude Code version, optional;
- five-hour used percentage and reset;
- seven-day used percentage and reset;
- sanitized observation timestamp;
- relay/schema health.

### 13.2 Forbidden Claude data

- credentials;
- tokens;
- Keychain values;
- transcript path or content;
- prompt/response content;
- session or prompt IDs;
- account identity;
- workspace and repository paths;
- Git branch;
- task/tool content;
- raw JSON;
- provider logs.

### 13.3 Configuration backup

The exact affected Claude settings backup:

- remains outside Git;
- uses owner-only permissions;
- is retained only while required for deterministic restore;
- is deleted after successful uninstall/restore when no longer needed;
- is never packaged.

### 13.4 Diagnostics

Do not print:

- full Claude settings;
- full status-line command;
- environment variables;
- process arguments;
- raw payload;
- private paths when a normalized description is sufficient.

### 13.5 Source transparency

Settings must state:

```text
Credentials accessed by UMA        None
Network requests made by UMA       None
Transcript read                    No
Raw Claude payload stored          No
Data retained                      Quota windows, reset times, last event
Configuration changed              Claude user status line, reversible
```

---

## 14. Testing strategy

### 14.1 M5-G1 capability

- CLI presence and version;
- signature/path;
- authentication classification;
- settings hierarchy;
- status-line configuration;
- field inventory;
- privacy allowlist;
- exact restore feasibility.

### 14.2 M5-G2 offline implementation

- relay parser;
- private-field rejection;
- original command preservation;
- socket protocol;
- connector states;
- Maximum Decrement input;
- Settings and restore;
- no network;
- no payload persistence.

### 14.3 M5-G3 live main-panel acceptance

- real sanitized event;
- five-hour/seven-day handling;
- main-panel card;
- Codex and WorkBuddy independent operation;
- relaunch/waiting behavior;
- safe stale state;
- commit-exact package.

### 14.4 M5DBG

- event bursts;
- relay failure;
- socket replacement;
- status-line repair;
- settings restore;
- login/logout;
- provider failure combinations;
- resource run;
- package privacy.

### 14.5 M5A and M5ADBG

- shared presentation only;
- exact main/Assistant parity;
- lifecycle;
- density;
- accessibility;
- no source multiplication;
- combined endurance.

---

## 15. Deterministic test matrix

### 15.1 Installation and configuration

- CLI absent;
- multiple Claude installations;
- unsupported old version;
- no settings file;
- empty settings;
- existing user status line;
- inline command;
- script command;
- spaces and quoting;
- refreshInterval present/absent;
- managed settings override;
- `disableAllHooks` true;
- recursion;
- backup/restore;
- disable/reinstall.

### 15.2 Payload

- malformed JSON;
- missing `rate_limits`;
- `rate_limits: null`;
- five-hour only;
- seven-day only;
- both windows;
- used 0, 100, fractional;
- negative;
- above 100;
- wrong type;
- missing reset;
- seconds timestamp;
- milliseconds timestamp;
- impossible timestamp;
- unknown future fields;
- private fields present and rejected.

### 15.3 Relay

- stdin read once;
- packet size bound;
- socket unavailable;
- socket reconnect;
- app not running;
- burst updates;
- in-flight cancellation;
- prior command success/failure;
- stdout preserved;
- no raw file;
- no logs;
- no network;
- permissions;
- no orphan helper.

### 15.4 Connector

- not installed;
- installed waiting;
- fresh;
- stale;
- one window;
- two windows;
- invalid packet;
- unsupported schema;
- source disabled;
- logout;
- last-valid in memory;
- relaunch without disk snapshot;
- independent provider failure;
- selected-window parity.

### 15.5 UI

- Claude hidden;
- waiting/setup state;
- Claude only fixture;
- Codex + Claude;
- Claude + WorkBuddy;
- Codex + Claude + WorkBuddy;
- stable order;
- expansion persistence;
- Settings scrolling;
- Light/Dark;
- transparency/contrast/motion;
- English/Chinese;
- keyboard/VoiceOver;
- Regular/Minimalist.

---

## 16. Performance targets

- one relay helper maximum;
- one socket listener maximum;
- no helper process retained after a status-line invocation;
- relay target under 50 ms excluding prior user command;
- provider event to visible main-panel target under 500 ms;
- provider event to Assistant target under 500 ms after M5A;
- bounded packet below 16 KiB;
- zero network requests by relay and connector;
- zero raw payload writes;
- no duplicate observer;
- no provider-read multiplication from Assistant;
- stable CPU, RSS, threads, descriptors, sockets, and writes.

---

## 17. Goal sequence and model routing

```text
M5-B0
→ M5-G1
→ M5-SETUP-G1 when required
→ M5-G2 after GO / CONDITIONAL GO
→ M5-G3
→ M5DBG-G1
→ M5A-G1
→ M5ADBG-G1
→ M5-CLOSE-G1
```

Conditional alternate:

```text
M5-G1 local NO-GO
→ Founder activation
→ M5-WEB-G1
```

| Goal | Model | Task class | Result |
|---|---|---|---|
| M5-B0 | Sol / Medium | Standard Task | post-M4 worktree and governing source |
| M5-G1 | Sol / Extra High | Full Goal | local source/auth/config capability dossier |
| M5-SETUP-G1 | Sol / High | Live Setup Task | official CLI install/login checkpoint |
| M5-G2 | Sol / Extra High | Full Goal | relay, connector, Settings, offline package |
| M5-G3 | Sol / High | Full Goal | live main-panel and package acceptance |
| M5DBG-G1 | Sol / Extra High | Full Goal | three-provider main-app debugging |
| M5A-G1 | Sol / High | Standard Task | Claude shared presentation in Assistant |
| M5ADBG-G1 | Sol / Extra High | Full Goal | combined closeout |
| M5-WEB-G1 | Sol / Extra High | Conditional Full Goal | account-web fallback dossier only |
| M5-CLOSE-G1 | Sol / High | Standard/Full docs closeout | current-source update |

Every task ends under Completion Lock.

---

## 18. Git and worktree policy

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

M5-B0 must verify the exact M4-N predecessor.

Default after each accepted implementation Goal:

- exact-file/hunk staging;
- cached-diff audit;
- independent staged-index review;
- one local commit when authorized;
- clean index;
- no push.

Config backups, raw payloads, sockets, logs, screenshots, and packages remain outside Git.

---

## 19. Package and installation policy

Development packages remain under task-owned `/private/tmp` paths.

Every M5 package must prove:

- exact commit provenance;
- version/build;
- bundle identity;
- architecture;
- signature;
- system dependencies;
- helper provenance;
- no API keys or tokens;
- no Claude credentials;
- no raw payload;
- no transcript/session/workspace data;
- no status-line config backup;
- no socket artifact;
- no tests, logs, screenshots, or fixtures.

Do not replace `/Users/juliushe/Desktop/UMA_0.11.app` without a separate explicit installation task.

---

## 20. Risk register

| ID | Risk | Impact | Mitigation |
|---|---|---|---|
| M5-R1 | Claude CLI absent | Source cannot be tested | M5-SETUP official install/login gate |
| M5-R2 | Current account omits `rate_limits` | No local quota | Return NO-GO or conditional fallback dossier |
| M5-R3 | Existing status-line command is complex/private | Config loss or disclosure | Exact owner-only backup, no report output, stop on unsafe case |
| M5-R4 | Managed policy blocks user status line | Implementation blocked | Do not bypass; report admin requirement |
| M5-R5 | Raw payload contains transcript/workspace data | Privacy breach | Relay allowlist before app boundary; no raw persistence |
| M5-R6 | Status-line config update regresses user display | User-facing defect | Multiplexer preservation and exact restore tests |
| M5-R7 | Source is event-driven and idle | Stale quota | Explicit stale state; optional bounded refresh interval after proof |
| M5-R8 | API-based auth takes precedence | Violates Founder policy | Safe auth classification; do not admit secret-based source |
| M5-R9 | Helper becomes orphaned | Resource/privacy issue | One-shot invocation, ownership tests, clean termination |
| M5-R10 | Provider count goal pressures weak fallback | Product trust loss | Source quality outranks card count |

---

## 21. M5 PASS criteria

M5 through M5ADBG passes only when:

1. the official Claude Code local source is proven on the installed version;
2. provider-managed login is used;
3. no Anthropic API key or copied token enters UMA;
4. at least one current plan-limit window reaches UMA;
5. missing windows remain unavailable;
6. used-to-remaining conversion is correct;
7. Maximum Decrement remains centralized;
8. raw status-line payload is never persisted;
9. transcript/session/workspace/identity fields are rejected;
10. the relay has no network access;
11. existing status-line output is preserved and restorable;
12. main panel shows Claude independently beside Codex and WorkBuddy;
13. main-app debug passes;
14. Assistant consumes shared presentation only;
15. combined debug passes;
16. package/privacy/resource/Git evidence passes;
17. one commit-exact accepted package exists;
18. installed Desktop replacement remains separately authorized;
19. account-web fallback remains unstarted unless separately activated;
20. M6 remains unstarted.

---

## 22. Immediate next action

```text
Send M5-B0 only
→ verify the exact M4-N closeout commit
→ create codex/uma-m5-claude
→ create /Users/juliushe/Developer/UMA-M5-Claude
→ install Logic 1.5, Scroll 2.1, M5 Plan, and M5 Goals
→ make no runtime or Claude configuration change
→ then send M5-G1 local source admission
```

---

## Appendix A — Official Claude Code references

Retrieved 2026-07-28:

```text
https://code.claude.com/docs/en/statusline
https://code.claude.com/docs/en/authentication
https://code.claude.com/docs/en/installation
https://code.claude.com/docs/en/settings
https://code.claude.com/docs/en/commands
```

Current live documentation remains authoritative.
