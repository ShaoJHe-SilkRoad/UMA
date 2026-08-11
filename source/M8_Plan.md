# Usage Monitor Altoget — M8 Plan

**Milestone:** M8 — Kimi Unified Usage Support
**Version:** 2026-08-11
**Status:** Active planning; implementation gated by live source admission
**Strategic decision:** Kimi is the next provider candidate after Cursor NO-GO
**Research verdict:** **CONDITIONAL GO TO SOURCE ADMISSION**
**Production support:** Not yet admitted
**Primary source direction:** Official Kimi Code provider-owned `/usage` surface
**Conditional source direction:** Official Kimi Subscription / Kimi Code Console browser surface
**Next provider after M8:** TRAE / TraeWork
**Current supported providers:** Codex, Claude Code, WorkBuddy, Google Antigravity
**Current unsupported provider:** Cursor

---

## 0. Plan authority

Use this authority order:

```text
1. Current Founder instruction
2. Current live repository evidence
3. Latest accepted DEV report and independent audit
4. Scroll 3.0
5. This M8 Plan
6. M8 Goal
7. Current M8 Scope Lock
8. UMA Logic 1.5 product principles
9. Goal Mode 2.0
10. Dev Default 2.1
11. Accepted M7/M6/M5 closeout and source-admission records
12. Historical plans, screenshots, packages, and reference records
```

Current Founder decisions:

- Accept Kimi as the next UMA provider candidate.
- Re-rank Chinese platforms by current market relevance, not connector convenience alone.
- Treat Kimi as one ecosystem/provider, not separate Kimi Work and Kimi Code cards.
- Preserve all four accepted provider mechanisms.
- Do not revive Cursor without a new source-direction decision.
- Prefer official provider-owned structured/local sources.
- Allow provider-controlled login when credentials remain opaque to UMA.
- Prohibit user-entered API keys, copied tokens, Keychain credential reads, cookie/profile import, manual quota, and estimated account remaining.
- Do not implement Kimi until source admission proves current account behavior.
- Keep TRAE / TraeWork next after Kimi; Qoder / QoderWork follows TRAE.

### 0.1 Superseded provider ordering

Scroll 2.1 and older provider matrices placed Kiro, Kimi, Junie, Cursor, and other candidates in historical orders. Those orders are retired.

Current priority:

```text
M8  Kimi ecosystem
M9  TRAE / TraeWork
M10 Qoder / QoderWork
```

CodeBuddy is not a separate target unless future source evidence proves a distinct account and distinct balance from the already-supported WorkBuddy ecosystem.

### 0.2 Research versus live truth

Official current material proves that Kimi has:

- a first-party K3 ecosystem across Kimi.com, Kimi Work, Kimi Code, and API;
- one provider account spanning general knowledge work and coding;
- a documented shared membership-credit system;
- Kimi Code-specific rate limits;
- an official `/usage` command;
- provider-controlled OAuth login;
- Extra Usage that may continue work after subscription credits are exhausted.

It does **not** yet prove that the Founder's installed/current Kimi source exposes a stable, machine-readable, non-agent-turn quota payload suitable for UMA.

Therefore:

```text
Strategic viability:      GO
Source-admission program: GO
Production connector:     LOCKED
Provider visibility:      LOCKED
```

---

## 1. Feasibility decision

### 1.1 Product and market viability — GO

Kimi is a strong UMA target because:

- Kimi K3 is a current first-party flagship across coding and knowledge-work products;
- Kimi Work is a desktop knowledge-work Agent, directly overlapping the WorkBuddy use case;
- Kimi Code is a terminal and IDE coding Agent, overlapping Codex, Claude Code, and Antigravity use cases;
- Moonshot's launch demand was strong enough to strain capacity and temporarily pause new subscriptions;
- current public Douyin indexing shows active Kimi K3 / Kimi Code installation, plan, quota, API, and tutorial search intent;
- the provider has a current official documentation and release cadence.

Popularity is only a prioritization signal. It does not weaken source-admission requirements.

Exact Douyin and Xiaohongshu keyword search counts are not publicly exposed in a stable, comparable form. M8 must not invent search-volume numbers.

### 1.2 Account-model viability — CONDITIONAL GO

Current official Kimi documentation supports a one-provider model:

```text
Kimi.com
Kimi Agent / Deep Research / Slides / Docs / Sheets
Kimi Work
Kimi Code
Kimi Claw and other membership features
→ one Kimi membership ecosystem
```

Current documentation also describes:

```text
shared membership credit pool
+ Kimi Code 5-hour limit
+ Kimi Code weekly limit
+ optional Extra Usage wallet
```

However, official pages currently show plan-transition complexity:

- current membership pages describe a shared pool with a monthly subscription-cycle refresh;
- Kimi Code benefit pages also describe weekly credit periods for some current/legacy Code benefits;
- Moonshot states that Kimi membership and Kimi Code benefits are moving toward a split plan structure;
- existing subscribers may retain merged benefits while new plan presentation changes.

M8 must classify the live account mode and use provider-supplied scope/reset identity. It must not hard-code one universal cycle.

### 1.3 Source viability — CONDITIONAL GO

Strong source candidates exist:

1. Official Kimi Code CLI `/usage`.
2. Official Kimi Code Console quota view.
3. Official Kimi Subscription / My Quota page.

But the current official CLI docs describe `/usage` as an interactive TUI information command. They do not yet establish a documented Antigravity-style machine-readable read-only print contract.

M8-G1 must prove:

- installed executable identity and capability;
- provider-controlled OAuth state;
- whether `/usage` can run without an Agent turn, prompt, conversation, workspace read, or quota spend;
- whether its output is bounded and deterministically decodable;
- which Kimi account limits it actually contains;
- whether shared membership, Code limits, and Extra Usage can be represented honestly.

### 1.4 Production viability — NOT YET PROVEN

Production is blocked until M8 source admission establishes an honest answer to all of these:

- What stops Kimi Work and general Kimi membership features?
- What stops Kimi Code?
- Are the shared membership and Code limits visible in one source or two?
- What happens at 0% when Extra Usage is enabled?
- Which plan/account modes are supported?
- Can routine reads occur automatically without provider work or credentials entering UMA?

The milestone proceeds because viable official source candidates exist. It does not assume they will pass.

---

## 2. Canonical repository and branch plan

### 2.1 Accepted M7 closeout parent

```text
Workspace:
/Users/juliushe/Developer/UMA-M7-Cursor

Branch:
codex/uma-m7-cursor

Accepted HEAD:
e47f7de3e71f80d45a5561dad40e37f37ff11fd1

Accepted tree:
d836312beb29005e7b5abe882f9919d05a9b49f4

Accepted result:
M7 CLOSED — CURSOR UNSUPPORTED — SOURCE NOT ADMITTED
```

The historical M7-G1C source-decision commit
`fcb51ab48bb076704431742b7b0300c235975f8e` with tree
`43dac9a01be51c3f19b3e510d3ff6923ca4bae57` remains retained evidence. It is
the direct parent of the accepted M7 closeout and is not the M8 branch point.

M7 changed source-admission docs/tests only. The accepted production runtime remains the M6 combined-closeout runtime.

### 2.2 Required M8 branch and worktree

```text
Branch:
codex/uma-m8-kimi

Worktree:
/Users/juliushe/Developer/UMA-M8-Kimi

Parent:
e47f7de3e71f80d45a5561dad40e37f37ff11fd1
```

M8 must branch from this exact accepted local commit, not remote `main` and not the older M6 branch.

### 2.3 Accepted runtime and package baseline

```text
Accepted runtime commit:
e72bd92c476e05152b95ccb9ba95c22be78efef1

Accepted runtime tree:
c1358c5b4176383021e87605afc45ca3e347ab89

Accepted M6 closeout commit:
a6b846ea2785448c4d4e51ec0e775ff9220d33f5

Accepted package:
/Users/juliushe/Developer/UMA-Packages/
uma-m6adbg-final-e72bd92c476e05152b95ccb9ba95c22be78efef1/UMA.app
```

### 2.4 Protected installed app

```text
/Users/juliushe/Desktop/UMA_0.11.app

Protected executable SHA-256:
88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

M8 may not replace it without a separate current Founder authorization.

### 2.5 Remotes and delivery boundary

M8 is local-only unless a future current instruction authorizes remote delivery.

No Plan provision authorizes:

- push;
- PR;
- merge;
- tag;
- release;
- notarization;
- App Store submission;
- production deployment.

---

## 3. Protected zones and anti-conflict boundary

### 3.1 M5 Claude frozen/protected zone

The accepted M5 frozen manifest remains protected, including:

- Claude Browser protocol/native-host/cache/connector/settings/localization;
- `BrowserExtension/**` owned by accepted Claude Browser Sync;
- Claude local activity reader;
- M5 tests and governance;
- M5 package helper;
- `script/test.sh`.

M8-B0 must load the exact accepted path manifest from current repo records rather than recreate it from this summary.

### 3.2 Existing provider mechanism protection

Do not change the accepted source mechanisms for:

```text
Codex
→ local app-server + accepted local session-log details

Claude Code
→ Browser Sync quota + separate local activity/cost estimate

WorkBuddy
→ provider-owned account-web exact Credits

Google Antigravity
→ official read-only CLI /usage
```

Every later shared edit must report:

```text
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Antigravity mechanism changed: NO
```

### 3.3 Shared additive-only zone

Expected shared surfaces may include:

```text
Package.swift
AgentUsageConnector.swift
AgentConnectorRegistry.swift
AgentConnectorSnapshotStore.swift
AgentUsageRuntime.swift
UsageStore.swift
UsageSnapshot.swift
SharedUsagePresentation.swift
UsagePanelView.swift
DesktopAssistantView.swift
Settings surfaces and provider registry views
```

M8 edits must be minimal and additive. The exact current paths must be confirmed in M8-B0.

### 3.4 M8 free zone

M8 may create Kimi-owned components such as:

```text
Kimi usage source client(s)
Kimi quota/credit models
Kimi connector
Kimi source coordinator
Kimi settings/localization
M8 tests
M8 governance/source records
M8 package helper
M8-owned browser companion/native bridge only if separately admitted
```

### 3.5 Browser-source isolation

Do not modify the frozen Claude Safari extension to test Kimi.

If an official browser source becomes necessary:

- use M8-owned temporary/admission components first;
- select one final architecture after source admission;
- sanitize before native business logic;
- do not import cookies or browser profiles;
- restore any temporary Safari developer/security setting after the Goal;
- require signed distribution in a later Release Mode, not a permanent unsigned-extension user requirement.

---

## 4. Why Kimi is M8

Kimi is the next provider because it combines:

1. **Current relevance** — Kimi K3 has strong present market momentum.
2. **Product fit** — Kimi Work covers desktop knowledge work; Kimi Code covers development.
3. **First-party ownership** — Kimi owns the account, product, model, and usage contract.
4. **Official source candidates** — `/usage`, Kimi Code Console, and My Quota exist.
5. **Unified provider value** — one provider can represent shared ecosystem limits instead of duplicating Kimi product cards.
6. **Fifth-provider product value** — Kimi is the first real candidate to prove the `>4 visible providers → forced Minimalist` rule.

Kimi is preferred over TRAE and Qoder for M8 because first-party Kimi support captures both Kimi Work and Kimi Code usage at the account owner, while host-platform support would monitor only one downstream access path.

---

## 5. M8 result target

M8 succeeds when UMA can display one Kimi provider using admitted current provider-owned source(s) without accessing credentials or misrepresenting continuation capacity.

Required user path:

```text
Kimi official client/source present
→ provider-controlled authentication
→ UMA performs bounded read-only usage observation
→ strict source decoder/extractor accepts current account limits
→ one Kimi provider publishes truthful native metrics
→ Main Panel and Desktop Assistant share one presentation
→ fifth visible provider forces Minimalist
→ removing Kimi restores valid <=4-provider density behavior
```

Required provider order:

```text
1. Codex
2. Claude Code
3. WorkBuddy
4. Google Antigravity
5. Kimi
```

Required source transparency, adapted to the admitted source:

```text
Source:
Official Kimi provider-owned usage source

Authentication:
Managed by Kimi

Credentials accessed by UMA:
None

Provider tasks/prompts created by refresh:
None

Usage/quota consumed by refresh:
None, after live verification

Data retained:
Sanitized quota windows, optional native Extra Usage state/balance, and freshness only
```

---

## 6. This milestone is not

M8 does not:

- implement TRAE, Qoder, Cursor, CodeBuddy, or another provider;
- create separate cards for Kimi Work, Kimi Code, Kimi.com, Kimi Agent, or Kimi API;
- use the Kimi Open Platform balance/API as membership quota;
- request or store a Kimi Open Platform API key;
- copy a Kimi Code API key into UMA;
- read Kimi OAuth tokens from `~/.kimi-code`;
- read Keychain credentials;
- import browser cookies/profiles;
- call undocumented/private Kimi account endpoints directly;
- infer account remaining from local token/activity/cost logs;
- infer a cycle or denominator from plan marketing;
- use OCR/screenshot extraction as a production source;
- allow manual balance entry or manual deduction;
- purchase membership, credits, or Extra Usage;
- modify existing provider mechanisms;
- resume M5 signing/notarization work;
- replace the protected Desktop UMA;
- push or release.

---

## 7. Kimi provider and channel model

### 7.1 One provider identity

Use one provider:

```text
providerID: kimi
providerName: Kimi
```

Do not create product-specific provider IDs such as:

```text
kimi-work
kimi-code
kimi-agent
kimi-k3
kimi-api
```

### 7.2 Maximum two channels

M8 remains within the current maximum two-channel provider contract.

Recommended channel model:

#### Channel A — percentage quota windows

May contain independently scoped percentage windows such as:

```text
shared membership credits
Kimi Code rolling 5-hour limit
Kimi Code weekly / provider-supplied cycle limit
```

Each window requires:

```text
stable provider-owned identity
explicit remaining or used semantic
same-scope numerator/denominator when conversion is required
provider-supplied reset/cycle scope
observation time
source/freshness
```

Do not sum or split windows.

#### Channel B — Extra Usage

Optional native continuation channel/detail:

```text
Extra Usage unavailable
Extra Usage disabled
Extra Usage enabled + exact native balance
Extra Usage enabled + balance unavailable
```

When exact balance is admitted, keep the provider-native currency/balance.

Do not convert Extra Usage to percentage without a complete same-scope denominator.

### 7.3 Unified-support minimum

M8 must admit the ecosystem-wide shared membership quantity before calling Kimi unified support complete.

If the only available source is Kimi Code's 5-hour/weekly limits:

```text
Kimi Code-only monitoring may be technically possible
but Kimi unified provider support = NO-GO
```

A narrower Kimi Code-only product would require a new explicit Founder scope decision.

### 7.4 Optional Code-window rule

If the shared membership source is fully admitted but the current account does not expose one optional Kimi Code window:

- hide the absent window;
- do not create a zero value;
- implementation-ready `CONDITIONAL GO` may be allowed if the shared ecosystem metric remains truthful and the omitted Code detail cannot misstate whether general Kimi work continues.

### 7.5 Extra Usage continuation rule

Extra Usage is not cosmetic. Official Kimi material states that it can continue work after subscription credits are exhausted.

Therefore:

- `0% membership remaining` must not be presented as equivalent to `Kimi cannot continue` when Extra Usage is enabled and funded;
- source admission must classify Extra Usage state;
- enabled-but-unreadable Extra Usage may block production support if UMA cannot avoid a misleading stop signal;
- expanded UI must separate subscription quota from Extra Usage;
- compact selection must not convert a native money balance into a fake percentage.

---

## 8. Official source decision

### 8.1 Primary candidate — official Kimi Code `/usage`

```text
Official Kimi Code CLI
→ provider-controlled OAuth
→ interactive /usage information command
→ token/context/quota information
→ Extra Usage balance in current releases
```

Classification before live admission:

```text
Official provider CLI candidate
Authority: strong
Machine-readable contract: unproven
No-turn/no-spend contract: unproven
Unified membership coverage: unproven
```

M8 must not assume that `kimi -p "/usage"` behaves like Antigravity print mode. Current docs identify `/usage` as a TUI control command, while prompt mode is designed primarily for Agent instructions.

M8-G1/G1R must construct the command from installed help and observed behavior, not this Plan's examples.

### 8.2 Provider-controlled authentication

Preferred account mode:

```text
Kimi Code OAuth device-code login
→ provider browser authorization
→ provider CLI stores credentials
→ UMA never reads credential files
```

Kimi Code may also support API-key providers. Those are not the M8 production source.

UMA must never inspect:

```text
~/.kimi-code credential files
Kimi Code config secrets
OAuth token values
Kimi Code API keys
Kimi Open Platform keys
```

### 8.3 Conditional official browser source

If CLI `/usage` cannot provide the complete unified contract:

```text
Official Kimi Subscription / My Quota page
or
Official Kimi Code Console quota/rate-limit view
→ provider-controlled login
→ bounded semantic extraction
→ sanitized observation
```

M8-WEB-G1 must select exactly one production browser architecture:

1. app-owned isolated provider-controlled session, if compatible and safe; or
2. Safari Browser Companion, if isolated authentication is incompatible.

No production source may depend on a user permanently enabling unsigned Safari extensions.

### 8.4 Source composition

Possible implementation-ready source combinations:

```text
A. CLI supplies all required windows and Extra Usage state
   → one CLI source coordinator

B. CLI supplies Kimi Code limits; official browser supplies shared membership/Extra Usage
   → one Kimi connector with two source transports

C. Official browser supplies the complete unified contract
   → one browser source coordinator
```

Do not publish duplicate observations for the same pool.

### 8.5 Prohibited sources

Reject:

- Kimi Open Platform API balance;
- Kimi Open Platform balance API;
- copied Kimi Code API key;
- direct use of OAuth access/refresh tokens;
- token/config/auth-file parsing;
- internal/private account endpoints;
- DevTools network replay;
- browser-cookie/profile import;
- local conversations/session history as account quota;
- manual values;
- screenshot/OCR source.

---

## 9. Source-admission contract

M8 source admission returns one overall decision and separate channel decisions.

Overall decisions:

```text
GO
CONDITIONAL GO — IMPLEMENTATION READY
SETUP REQUIRED
SOURCE EXPANSION REQUIRED — M8-WEB-G1
NO-GO
```

Channel decisions:

```text
SHARED MEMBERSHIP: GO / CONDITIONAL / MISSING / NO-GO
KIMI CODE LIMITS: GO / CONDITIONAL / MISSING / NO-GO
EXTRA USAGE: GO / CONDITIONAL / DISABLED / ABSENT / UNREADABLE / NO-GO
```

### 9.1 GO

Require:

- official provider-owned source(s);
- provider-controlled authentication;
- shared ecosystem membership quantity admitted;
- explicit unit and remaining/used semantic;
- stable pool/window identities;
- account/cycle/reset scope explicit enough for honest display;
- Extra Usage continuation state handled honestly;
- no credentials enter UMA;
- bounded sanitization before business logic;
- routine read creates no Agent turn, prompt, task, conversation, or quota spend;
- repeated observations are stable;
- automatic refresh is feasible;
- at most two channels.

### 9.2 CONDITIONAL GO — IMPLEMENTATION READY

Allowed only when the shared ecosystem quantity is production-usable and the remaining gap is genuinely optional, for example:

- one optional reset absent;
- one optional label absent;
- a Kimi Code-specific limit absent for the current account but shared membership remains exact;
- Extra Usage is explicitly absent or disabled.

Do not use this decision for:

- missing shared membership quota;
- ambiguous remaining/used semantics;
- enabled but unreadable continuation balance when that would misstate stoppage;
- credential dependence;
- private endpoint dependence;
- unstable identity.

### 9.3 SETUP REQUIRED

Use when:

- official Kimi Code CLI is absent;
- installed CLI is outdated or lacks the needed command;
- provider-controlled OAuth login is incomplete;
- an official setup/update can resolve the issue without changing source class.

### 9.4 SOURCE EXPANSION REQUIRED — M8-WEB-G1

Use when:

- the CLI source is admitted for one part of the contract;
- the shared membership or continuation state is missing;
- an official provider-rendered Kimi account surface remains viable;
- browser source admission is required before implementation.

This does not unlock M8-G2.

### 9.5 NO-GO

Use when:

- only API-key/token/private sources work;
- shared membership remaining cannot be obtained honestly;
- quota semantics are ambiguous;
- account mode/cycle cannot be scoped safely;
- read creates provider work or consumes usage;
- enabled Extra Usage makes the displayed pause condition misleading and cannot be observed;
- output/page cannot be sanitized;
- source is unstable after bounded repair;
- only local estimates exist.

---

## 10. Authentication and setup

### 10.1 Supported

```text
Official Kimi Code OAuth device-code flow
Official Kimi provider-controlled web login
```

Credentials remain owned by Kimi.

### 10.2 Unsupported

- Kimi Open Platform API-key input;
- copied Kimi Code API key;
- copied OAuth URL/code/token in DEV reports;
- Keychain credential reads;
- browser cookie/profile import;
- custom UMA OAuth broker;
- direct auth database access.

### 10.3 Setup states

CLI absent:

```text
Kimi
Official Kimi Code CLI not found
[Open Official Setup]
[Check Again]
```

Login required:

```text
Sign in through Kimi Code
[Open Kimi Login]
[Check Again]
```

Browser setup required, only after browser-source GO:

```text
Connect through official Kimi account page
[Open Kimi]
[Check Again]
```

Configured:

```text
Connected through Kimi
Updated <relative time>
[Sync Now]
[Disable]
```

### 10.4 Human checkpoint

When provider-controlled OAuth requires Human action, DEV returns only a bounded instruction such as:

```text
HUMAN ACTION REQUIRED — COMPLETE KIMI LOGIN

Use only the official Kimi page opened by Kimi Code.
Do not send password, email, code, URL, token, screenshot, or account identity.
Return only:
KIMI LOGIN COMPLETED
```

Routine refresh must never repeatedly open login.

---

## 11. Data contract

### 11.1 Percentage quota window

```text
windowID
scope
safeLabel?
remainingPercent
resetEpoch?
resetLabel/cycle?
observationTime
sourceVersion
freshness
```

### 11.2 Explicit semantic mapping

If source supplies explicit remaining percentage/fraction:

```text
retain remaining directly
or
remainingPercent = remaining_fraction × 100
```

If source supplies explicit used percentage with a complete same-scope denominator:

```text
remainingPercent = 100 - usedPercent
```

If source supplies used and total values:

```text
remaining = total - used
remainingPercent = remaining / total × 100
```

Only when all values share:

- the same pool;
- the same cycle;
- the same account mode;
- the same observation.

Do not infer semantics from numeric range or progress-bar direction.

### 11.3 Window identity

Use stable provider-owned identity.

Do not identify windows by:

- array order;
- current remaining value;
- reset timestamp alone;
- translated display text alone when a stable key exists;
- model assumptions.

If only semantic labels exist, source admission must prove they are stable and bounded across repeated observations and localization.

### 11.4 Validation

- finite numeric values only;
- percentage in `0...100`;
- fraction in `0...1`;
- no silent clamp;
- no negative balance;
- no missing-to-zero conversion;
- reset/cycle bounded and scope-specific;
- unknown/future schema fails closed;
- private fields discarded before normalized models;
- `sourceVersion` must remain within the existing character/length contract.

### 11.5 Multiple windows

Preserve independently:

- shared membership pool;
- Code 5-hour limit;
- Code weekly/provider-supplied cycle limit.

Do not:

- sum them;
- split a shared pool;
- copy one reset to another window;
- assume the most restrictive marketing limit is current;
- use one plan's windows for another account mode.

### 11.6 Extra Usage contract

Potential normalized fields:

```text
state: absent / disabled / enabled / unavailable
currency?
balance?
spendingCapState?
observationTime
freshness
```

Do not retain billing history, payment method, invoices, or identity.

If exact balance is unavailable but an explicit enabled/disabled continuation state is available, M8 may represent that state only if the UI can remain honest.

### 11.7 Account-mode contract

Classify current source as applicable:

```text
merged legacy/current membership
new split Kimi membership
new split Kimi Code membership
free account
individual subscribed account
business/enterprise
unsupported/unclassified
```

Do not persist plan identity unless required for source decoding and separately minimized.

Unknown account modes fail closed.

---

## 12. Runtime architecture

### 12.1 Preferred CLI-only path

```text
KimiSourceController
→ exact trusted official `kimi` executable
→ neutral UMA-owned working directory
→ bounded provider-owned `/usage` interaction
→ sanitized output
→ strict decoder
→ Kimi connector
→ registry / UsageStore
→ shared presentation
```

### 12.2 Conditional hybrid path

```text
KimiSourceController
├── KimiCodeUsageClient
│   → Kimi Code rate-limit windows
└── KimiAccountBrowserSource
    → shared membership + Extra Usage state/balance

→ atomic Kimi observation
→ Kimi connector
→ one provider presentation
```

Do not publish a mixed observation unless source timestamps and account scope are compatible or each window retains explicit independent freshness.

### 12.3 Process ownership

Expected normal maximum:

```text
0 or 1 Kimi CLI child process
0 overlapping Kimi source reads per transport
1 Kimi source controller
0 Assistant-owned source processes
0 UMA-owned Kimi credentials
0 provider tasks/prompts created by refresh
```

### 12.4 Executable discovery

M8-G1 must establish:

- official install path;
- exact resolved executable;
- file type/architecture;
- symlink chain;
- ownership;
- version/capability;
- installer/release/signature provenance where available.

Do not accept arbitrary `kimi` from the working directory.

### 12.5 Neutral execution directory

Quota observation must not run from a user repository or Kimi Work project.

Use an empty UMA-owned/task-owned directory to minimize workspace discovery and session creation.

### 12.6 Initial process limits

Final limits are set by source admission. Initial target:

```text
one process/read in flight
15-second request timeout
20-second hard timeout
bounded stdout/stderr or PTY transcript
closed stdin except exact control input
no shell interpolation
no environment credential injection
```

Do not persist raw TUI output.

### 12.7 Browser ownership

If browser source is admitted:

- one source-owned scheduler;
- one authorized route set;
- one in-flight extraction;
- sanitized extraction before native handoff;
- no rendering-owned read;
- no Assistant ownership;
- no raw DOM/HTML persistence.

---

## 13. Refresh and freshness

### 13.1 Initial cadence

Final cadence must be live-qualified.

Conservative initial candidate:

```text
current read on launch/setup completion
→ wait 5 minutes after completion
→ next normal read
```

Do not refresh faster than 3 minutes without evidence.

A browser source may use a different conservative cadence if current provider behavior requires it.

### 13.2 Coalescing

- one source-owned timer/coordinator;
- one read per transport in flight;
- manual and scheduled triggers coalesce;
- successful manual read resets next interval;
- no overlap;
- no catch-up burst;
- no rapid retry;
- no rendering-owned reads;
- source-specific failure does not trigger all-provider retry.

### 13.3 Admission

```text
supported official source
+ provider-owned authenticated state
+ current successful observation
+ shared membership quantity
+ honest continuation classification
= visible Kimi provider
```

Installation/login alone does not admit.

### 13.4 Cached and stale

Persisted Kimi state, if used, remains hidden on cold launch until current account validity is established according to the accepted source contract.

Cached/Stale:

- does not create Maximum Decrement sample;
- does not trigger false low-quota alert;
- cannot overwrite newer Fresh;
- is cleared on account/auth uncertainty;
- remains window/source-specific.

### 13.5 Account switch

An account switch must invalidate prior Kimi observations without retaining identity.

Do not compare decrements across uncertain account epochs.

### 13.6 Disconnect

Disconnect:

- cancels Kimi timers/owned processes;
- clears UMA-owned normalized snapshots;
- removes Kimi presentation;
- does not log out Kimi;
- does not delete provider-owned credentials/config;
- does not alter Kimi membership or Extra Usage settings.

---

## 14. Main-panel UX

### 14.1 Provider order

```text
Codex
Claude Code
WorkBuddy
Google Antigravity
Kimi
```

### 14.2 Collapsed card

- Kimi;
- selected truthful percentage window when available;
- selected scope label;
- source/freshness mark;
- no Extra Usage money converted into percentage.

### 14.3 Expanded card

- shared membership remaining and cycle/reset;
- Kimi Code 5-hour remaining/reset when admitted;
- Kimi Code weekly/provider-cycle remaining/reset when admitted;
- Extra Usage state and exact native balance only when admitted;
- source/version;
- last successful observation;
- source transparency;
- Sync / Open / Disable actions.

### 14.4 Continuation presentation

When subscription remaining is 0 but Extra Usage is enabled with usable balance:

- expanded UI must show the distinction;
- the provider must not appear as definitively unable to continue;
- the compact percentage remains subscription quota, not a total continuation percentage;
- any status mark/text must remain bounded and not violate the Founder's remaining-percentage display rule.

The exact UI contract is finalized after source admission.

### 14.5 Failure states

- CLI/app not installed;
- update required;
- login required;
- source unsupported;
- unknown plan mode;
- current read failed;
- malformed/unsupported output;
- shared membership missing;
- Extra Usage continuation ambiguous;
- provider unavailable;
- timeout.

One Kimi failure cannot blank existing providers.

---

## 15. Desktop Assistant and fifth-provider density

### 15.1 Entry gate

Assistant displays Kimi only after M8 main-app/live acceptance and shared-presentation admission.

### 15.2 First real forced-Minimalist transition

Kimi is provider five.

Required product behavior:

```text
visible provider count <= 4
→ Regular or user-selected Minimalist allowed

visible provider count > 4
→ automatic forced Minimalist
```

M8A-G1 must be the first live proof of this transition.

### 15.3 Restore behavior

When visible provider count returns to four or fewer:

- forced mode ends;
- restore the user's valid prior choice according to the existing shared density contract;
- do not remain permanently forced;
- do not create mode oscillation during transient refresh/failure states.

### 15.4 Minimalist Kimi

Display only:

```text
provider/source-state mark
selected remaining percentage
```

Extra Usage native balance belongs in detailed/main-panel presentation unless the accepted shared compact contract explicitly supports it without clutter or unit confusion.

### 15.5 Ownership

Assistant owns no:

- Kimi process;
- browser source;
- decoder;
- source coordinator;
- timer;
- cache;
- observation;
- quota selection;
- Extra Usage computation.

---

## 16. Privacy and security

### 16.1 Allowed normalized data

- bounded Kimi window ID/scope;
- bounded safe label;
- remaining/used values required for normalization;
- same-scope denominator when required;
- reset/cycle metadata;
- Extra Usage state;
- exact native Extra Usage balance/currency only when admitted;
- safe CLI/source version;
- observation/freshness.

### 16.2 Forbidden

- email;
- phone number;
- account ID;
- avatar/name;
- plan/billing identity unless separately required and minimized;
- payment method;
- invoice/history;
- OAuth/access/refresh token;
- Kimi Code API key;
- Kimi Open Platform key;
- Keychain data;
- cookies/browser profile;
- conversations/prompts/responses;
- code/project/workspace;
- session/task IDs;
- raw CLI/TUI transcript;
- raw DOM/HTML;
- raw account response;
- full process argv/environment.

### 16.3 Safe process inspection

Allowed:

- exact executable path/name;
- exact PID;
- owned parent/child relation;
- process count;
- bounded CPU/RSS/thread/descriptor metrics;
- exit/absence state.

Broad process command-line/environment inspection is prohibited.

### 16.4 Diagnostics

Use bounded categories such as:

```text
notInstalled
unsupportedVersion
loginRequired
unsupportedAccountMode
timeout
malformedOutput
unsupportedSchema
missingSharedMembership
ambiguousContinuation
providerUnavailable
```

Do not expose raw stderr/TUI/DOM in ordinary UI or durable records.

### 16.5 Source transparency

Settings must disclose:

- source type(s);
- authentication owner;
- credentials visible to UMA;
- data retained;
- provider/network behavior;
- refresh cadence;
- Extra Usage handling;
- unsupported account modes;
- disconnect behavior.

---

## 17. Testing strategy

### 17.1 M8-B0

- exact parent/branch/worktree;
- source document installation;
- M8 Scope Lock;
- accepted baseline tests/builds;
- existing provider freeze/protection;
- docs-only commit.

### 17.2 M8-G1 / G1R source admission

- installed Kimi/Kimi Work/Kimi Code inventory;
- official CLI executable provenance;
- version/help/capability;
- OAuth state without credential read;
- `/usage` control behavior;
- no-turn/no-session/no-work evidence;
- output schema/semantic classification;
- shared membership coverage;
- Code-window coverage;
- Extra Usage coverage;
- account-mode/cycle classification;
- repeatability;
- process teardown.

### 17.3 M8-WEB-G1 conditional admission

- isolated-session versus Safari decision;
- official route allowlist;
- provider-controlled login;
- no cookie/token import;
- stable semantic pool identity;
- used/remaining contract;
- cycle/reset;
- Extra Usage state/balance;
- repeated observations;
- automatic-refresh feasibility;
- cleanup/security restoration.

### 17.4 M8-G2 implementation

- exact source transport contracts;
- strict decoders/extractors;
- atomic multi-source observation;
- at most two channels;
- scheduler/coalescing;
- account switch/invalidation;
- Settings/localization;
- current-read admission;
- source transparency;
- package/privacy.

### 17.5 M8-G3 live main-panel acceptance

- current live shared membership;
- Code windows when admitted;
- Extra Usage continuation handling;
- provider-owned source parity;
- scheduled refresh;
- failure isolation;
- five-provider main-panel order/geometry;
- commit-exact package.

### 17.6 M8DBG

- all 0–5 provider subsets;
- failure combinations;
- source collisions;
- account-mode failures;
- refresh races;
- lifecycle;
- CPU/RSS/threads/descriptors;
- no timer/process/browser multiplication.

### 17.7 M8A and M8ADBG

- Main/Assistant shared truth;
- provider order;
- fifth-provider forced-Minimalist;
- restore at four or fewer;
- no Assistant source ownership;
- Light/Dark;
- EN/zh-CN;
- lifecycle/resource/privacy/package closeout.

---

## 18. Deterministic test matrix

### 18.1 CLI and executable

- CLI absent;
- wrong/untrusted executable;
- symlink escape;
- unsupported version/help;
- `/usage` unavailable;
- login required;
- success;
- timeout;
- cancellation;
- nonzero exit;
- oversized output;
- malformed output;
- noisy stderr;
- process teardown;
- one child maximum.

### 18.2 Authentication

- OAuth-authenticated;
- login required;
- expired session;
- provider unavailable;
- account switch;
- unknown account mode;
- no credential access;
- routine read does not launch repeated login.

### 18.3 Shared membership

- explicit remaining percentage;
- explicit used percentage;
- used + total;
- one shared pool;
- missing pool;
- zero remaining;
- full remaining;
- invalid value;
- cycle/reset present;
- cycle/reset absent;
- legacy/current plan label;
- future split plan;
- unknown plan fails closed.

### 18.4 Kimi Code windows

- 5-hour only;
- weekly/cycle only;
- both;
- missing one;
- independent IDs;
- independent resets;
- reordered windows;
- duplicate/ambiguous identity;
- valid/invalid ranges.

### 18.5 Extra Usage

- absent;
- disabled;
- enabled exact zero;
- enabled exact positive balance;
- enabled balance unavailable;
- native currency;
- spending cap present/absent;
- subscription 0 + Extra Usage positive;
- invalid/negative balance;
- billing/private fields rejected.

### 18.6 Multi-source atomicity

- CLI-only complete;
- browser-only complete;
- hybrid matching account epoch;
- one source stale;
- one source failure;
- source timestamps incompatible;
- account uncertainty;
- no duplicate pool publication;
- newer Fresh not overwritten.

### 18.7 Lifecycle

- launch read;
- conservative cadence;
- manual coalescing;
- no overlap;
- no catch-up;
- no retry storm;
- sleep/wake;
- disconnect during read;
- cached/stale;
- auth invalidation;
- provider independence.

### 18.8 UI and density

- 0/1/2/3/4/5 visible providers;
- every provider subset;
- stable order;
- five-provider Main Panel;
- five-provider forced Minimalist;
- return to four restores mode;
- main/Assistant parity;
- Missing != 0;
- Unlimited != 100%;
- WorkBuddy remains Credits;
- Extra Usage remains native;
- English/zh-CN;
- Light/Dark;
- deterministic accessibility;
- failure isolation.

---

## 19. Performance targets

Initial targets, finalized by live source evidence:

- normal source observation under 5 seconds when feasible;
- hard timeout no more than 20 seconds per transport unless browser source evidence requires a different bounded limit;
- one Kimi child process maximum;
- one browser extraction maximum;
- no idle child process;
- no monotonic RSS/thread/descriptor growth;
- no periodic writes when observation is unchanged;
- shared presentation update under 500 ms after accepted normalized observation;
- no refresh faster than 3 minutes without evidence;
- no Assistant/rendering source activity.

---

## 20. Goal sequence and model routing

```text
M8-B0
→ M8-G1
→ M8-SETUP-G1 only when required
→ M8-G1R after setup when required
→ M8-WEB-G1 only when the official web source is required
→ M8-G2 after overall GO / implementation-ready CONDITIONAL GO
→ M8-G3
→ M8DBG-G1
→ M8A-G1
→ M8ADBG-G1
→ M8-CLOSE-G1
→ M9 TRAE / TraeWork source admission next
```

| Goal | Model | Effort | Result |
|---|---|---|---|
| M8-B0 | GPT-5.6 Sol | High | Isolated M8 worktree, documents, baseline, Scope Lock |
| M8-G1 | GPT-5.6 Sol | Extra High | Official source/auth/account/schema admission |
| M8-SETUP-G1 | GPT-5.6 Sol | High | Official CLI installation/update/OAuth setup |
| M8-G1R | GPT-5.6 Sol | Extra High | Live installed CLI source re-admission |
| M8-WEB-G1 | GPT-5.6 Sol | Extra High | Conditional official account-web source admission |
| M8-G2 | GPT-5.6 Sol | Extra High | Unified Kimi connector/source coordinator/Settings |
| M8-G3 | GPT-5.6 Sol | High | Live fifth-provider Main Panel and package acceptance |
| M8DBG-G1 | GPT-5.6 Sol | Extra High | Five-provider main-app defect closure |
| M8A-G1 | GPT-5.6 Sol | High | Kimi Assistant + forced-Minimalist acceptance |
| M8ADBG-G1 | GPT-5.6 Sol | Extra High | Five-provider combined closeout |
| M8-CLOSE-G1 | GPT-5.6 Sol | High | Current truth and TRAE handoff |

Every Goal ends under Completion Lock.

M8 Quick Patch may be used only for a narrow post-acceptance defect that does not change source/auth architecture and normally affects no more than three files.

---

## 21. Git and worktree policy

Hard rules:

```text
Do not use git add .
Do not use git add -A.
Do not use git add -u.
Do not reset --hard.
Do not clean for convenience.
Do not discard unrelated WIP.
Do not force-push.
```

- Branch from exact local `e47f7de...`.
- Stage exact paths/hunks.
- Preserve unrelated work.
- Keep generated/private evidence out of Git.
- Announce every shared-file edit.
- No remote action without current authorization.

---

## 22. Build, package, and installation policy

- Use `script/test.sh` for canonical full verification.
- Do not modify `script/test.sh` unless a later explicit plan amendment changes the M5 protection boundary.
- Do not modify M5 package helpers.
- Create a new M8 package helper, for example:

```text
script/package_uma_m8.sh
```

- Final packages go under:

```text
$HOME/Developer/UMA-Packages/uma-m8-<phase>-<commit>/UMA.app
```

- Scratch may use task-owned repository `.build/*` or `/private/tmp/uma-m8-*` paths.
- Final evidence must not live only in `/private/tmp`.
- Do not bundle the Kimi executable, OAuth credentials, browser profile, test fixtures, or raw source evidence.
- Do not replace the protected Desktop UMA.
- Signing/notarization/public release remain separate Release Mode work.

---

## 23. Risk register

| ID | Risk | Type | Mitigation |
|---|---|---|---|
| M8-R01 | Kimi CLI is absent | Setup | Feature probe; M8-SETUP-G1 official install path |
| M8-R02 | `/usage` is interactive only | Source | PTY/control-command admission; no prompt-mode assumption |
| M8-R03 | `/usage` creates a session/turn or reads workspace | Correctness/privacy | Neutral cwd; before/after evidence; NO-GO if unavoidable |
| M8-R04 | CLI output is not machine-readable/stable | Source | Strict observed contract or official browser source expansion |
| M8-R05 | CLI omits shared ecosystem membership | Product | M8-WEB-G1; no unified implementation without shared metric |
| M8-R06 | Official plan pages conflict on cycle/split | Correctness | Live account-mode/cycle classification; no hard-coded universal cycle |
| M8-R07 | Future Kimi membership/Code plan split | Product drift | Provider-supplied identities, versioned source contract, fail closed |
| M8-R08 | Extra Usage permits continuation after 0% | High correctness | Admit continuation state/balance; do not equate 0% with stop |
| M8-R09 | Extra Usage enabled but unreadable | Blocking candidate | Fail closed or explicit Founder-approved narrower support |
| M8-R10 | OAuth token is stored under provider data root | Privacy | Invoke provider CLI only; never read credential files |
| M8-R11 | Kimi Open Platform confused with membership | High | Explicit product/source isolation; API keys prohibited |
| M8-R12 | Browser fallback expands privacy surface | Privacy | Provider-controlled login, field/route allowlist, sanitize before handoff |
| M8-R13 | New browser companion repeats M6/M7 incidents | Privacy | M8-owned bounded tools, no broad page/process data, cleanup gate |
| M8-R14 | Fifth-provider forced Minimalist regresses UX | UI | Dedicated M8A live acceptance and restore matrix |
| M8-R15 | Existing provider mechanisms regress | Architecture | Protected manifests, additive edits, fresh full regressions |
| M8-R16 | Kimi capacity/provider outage resembles quota exhaustion | Reliability | Separate provider source health from quota state |
| M8-R17 | Social popularity pressures premature implementation | Product | Source admission remains mandatory |
| M8-R18 | No Developer ID/notarized release | Distribution | Separate Release Mode; not M8 source blocker |

---

## 24. M8 PASS criteria

M8 passes only when:

1. an official Kimi source architecture is admitted;
2. the shared ecosystem membership quantity is live-qualified;
3. Kimi Code limits are shown only when explicitly admitted;
4. plan/account mode and cycle scope are honest;
5. Extra Usage continuation cannot make the UI falsely predict stoppage;
6. no Kimi/Open Platform API key enters UMA;
7. no OAuth/token/cookie/Keychain credential enters UMA;
8. no provider prompt, turn, task, conversation, or usage spend is created by refresh;
9. at most two provider channels are used;
10. multiple percentage windows remain independent;
11. native Extra Usage balance remains native;
12. one source coordinator and one in-flight read per transport are proven;
13. auth expiry and schema drift fail closed;
14. current-read admission is enforced;
15. Kimi is provider five in stable order;
16. Main Panel and Assistant share one immutable presentation;
17. five visible providers force Minimalist;
18. returning to four or fewer restores valid prior mode behavior;
19. Codex, Claude, WorkBuddy, and Antigravity mechanisms are unchanged;
20. privacy, tests, builds, resources, and package evidence pass;
21. one commit-exact package exists under the persistent root;
22. protected Desktop UMA remains unchanged;
23. worktree is clean and index empty;
24. M8 current truth is documented;
25. TRAE is recorded as next but not started.

---

## 25. Immediate next action

```text
M8-B0
→ verify M7 terminal closeout e47f7de... and clean state
→ create codex/uma-m8-kimi worktree
→ install Scroll 3.0, M8 Plan, M8 Goal, and M8 Scope Lock
→ record protected M5/M6/M7/provider boundaries
→ run baseline through script/test.sh
→ run required Debug/Release baseline builds
→ create one docs-only local commit
→ stop
```

Do not install Kimi or run authenticated `/usage` during M8-B0.

After accepted M8-B0:

```text
M8-G1
→ official source/auth/account/schema admission
→ GO / CONDITIONAL GO / SETUP REQUIRED / SOURCE EXPANSION REQUIRED / NO-GO
→ stop
```

---

## Appendix A — Current official Kimi references

Retrieved 2026-08-11:

```text
https://www.kimi.com/
https://www.kimi.com/blog/kimi-k3
https://www.kimi.com/ai-models/kimi-k3
https://www.kimi.com/help/kimi-work/overview
https://www.kimi.com/help/others/product-comparison
https://www.kimi.com/help/membership/membership-overview
https://www.kimi.com/help/membership/membership-pricing
https://www.kimi.com/help/membership/update-rules
https://www.kimi.com/help/membership/membership-extra-usage
https://www.kimi.com/help/agent/quota-and-billing
https://www.kimi.com/help/kimi-code/benefits
https://www.kimi.com/help/kimi-code/membership-guide
https://www.kimi.com/help/kimi-api/api-troubleshooting
https://www.kimi.com/code
https://www.kimi.com/code/docs/en/
https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html
https://www.kimi.com/code/docs/en/kimi-code-cli/reference/slash-commands.html
https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html
https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/data-locations.html
https://www.kimi.com/code/docs/en/kimi-code-cli/release-notes/changelog.html
https://github.com/MoonshotAI/kimi-code
```

Current official documentation and installed live behavior outrank this snapshot.

---

## Appendix B — Viability conclusion

```text
Market relevance:                 PASS
Product fit:                      PASS
First-party ecosystem fit:       PASS
Official account model:          PASS WITH PLAN-DRIFT RISK
Official source candidates:      PASS
Machine-readable source:         UNPROVEN
No-turn/no-spend read:            UNPROVEN
Shared membership live metric:   UNPROVEN
Kimi Code windows live metric:   UNPROVEN
Extra Usage continuation:        REQUIRES ADMISSION
Production connector:            LOCKED

Final M8 planning verdict:
CONDITIONAL GO TO SOURCE ADMISSION
```
