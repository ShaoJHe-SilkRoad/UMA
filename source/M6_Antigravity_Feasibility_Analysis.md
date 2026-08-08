# UMA M6 — Google Antigravity Complete Feasibility Analysis

**Version:** 2026-08-08
**Status:** Current research basis for M6
**Decision:** **CONDITIONAL GO TO SOURCE ADMISSION**
**Next provider after M6:** Cursor
**Claude M5 status:** Frozen pending Apple Developer Program activation

---

## 0. Executive verdict

Google Antigravity is currently the strongest next UMA provider candidate.

The latest official Antigravity CLI capability materially changes the older UMA assumption that M6 should depend on an interactive status line. Current official documentation and the official CLI changelog describe a better source:

```text
agy print mode
→ read-only /usage or /quota command
→ structured JSON output
→ no agent turn
→ no quota consumption
→ no conversation left behind
```

This is a strong match for UMA's source order:

```text
official local structured source
→ official local hook/status event
→ official read-only CLI
→ provider-controlled account login
→ unsupported
```

The preferred M6 source is therefore **the official Antigravity CLI read-only print command**, not an unofficial local server, copied OAuth token, private endpoint, or UI scraping.

M6 is not yet a production GO because UMA must still prove on the Founder's installed device:

- the installed `agy` version actually supports read-only structured print mode;
- the exact JSON schema and quota-bucket semantics;
- no login browser is opened during routine authenticated reads;
- the command creates no conversation, prompt, task, or quota consumption;
- the output can be strictly reduced to quota data without identity or workspace data;
- current output matches Antigravity's own Models & Quota view;
- the source remains stable through refresh, logout, account change, and version update.

Research-level verdict:

```text
Official feasibility: high
Production admission: pending M6-G1 live source dossier
Recommended next action: M6-B0, then M6-G1
```

---

## 1. Current authoritative project constraints

### 1.1 Current repository baseline

```text
Workspace : /Users/juliushe/Developer/UMA-M5-Claude
Branch    : codex/uma-m5-claude
HEAD      : c6245f9cc745b3d45f53e115843b3152e84e8c46
Tree      : e3ac2df1d135dad4c85af06611dc05943e8089dd
Worktree  : clean
Index     : empty
```

The branch is local-only. M6 must branch from this exact local commit, not from `origin/main`.

Required M6 destination:

```text
Branch   : codex/uma-m6-antigravity
Worktree : /Users/juliushe/Developer/UMA-M6-Antigravity
Parent   : c6245f9cc745b3d45f53e115843b3152e84e8c46
```

### 1.2 Claude freeze

Claude M5 is frozen until Apple Developer Program activation.

Codex must not modify:

- Claude Browser runtime and BrowserExtension tree;
- M5-prefixed tests;
- `script/package_uma_m5_g2.sh`;
- `script/test.sh`;
- `source/UMA M5 *.md`;
- Claude signing/notarization work.

Shared provider-neutral surfaces may be extended only additively and only when required for Antigravity.

### 1.3 Binding project rules

- Bundle identifier: `com.silkrd.uma`.
- Run tests through `script/test.sh`; bare `swift test` is not a valid evidence path on this machine.
- Deliver packages under `$HOME/Developer/UMA-Packages`, never `/private/tmp`.
- One provider may publish at most two channels.
- Persisted local-activity payload remains exactly six aggregate scalars.
- `sourceVersion` must match `^[A-Za-z0-9 ._-]+$` and be no longer than 32 characters.
- Provider order is Codex → Claude Code → WorkBuddy → Google Antigravity.
- More than four visible providers forces Desktop Assistant Minimalist mode. M6 is provider four, so it does not itself trigger the forced transition.
- Source admission is mandatory before visibility.
- User-entered API keys, copied tokens, Keychain credential reads, cookie/profile import, manual quota, and quota-consuming refresh tasks remain prohibited.
- No push, PR, merge, tag, release, notarization, or deployment without fresh Founder authorization.
- `~/Desktop/UMA_0.11.app` remains protected.

---

## 2. Latest official Antigravity findings

### 2.1 Product and CLI relationship

The official Antigravity CLI repository and documentation state that Antigravity CLI and Antigravity 2.0 use the same core agent engine and share settings. This supports treating the CLI as an official provider-owned account surface rather than a third-party wrapper.

Implication for UMA:

```text
Antigravity 2.0 / CLI own authentication and provider access
→ UMA invokes a documented read-only CLI surface
→ UMA receives structured quota only
→ UMA never reads Google credentials
```

### 2.2 Authentication

The official CLI authenticates through its own system-keyring integration and falls back to Google Sign-In through the default browser when no active session exists.

UMA must not inspect the keyring. It may only:

- detect `agy` availability;
- invoke an admitted read-only command;
- let the provider CLI report login required;
- offer a Human-controlled `Open Antigravity / Sign In` setup action;
- retry only after the Human completes provider-controlled login.

Routine background refresh must not repeatedly open a browser.

### 2.3 Official model-quota command

Official documentation defines `/usage` with alias `/quota` as the Model Quotas command. Opening it refreshes model configuration and quota status from disk and the backend, then displays model quota remaining information.

This means it is a current provider read, not a local estimate.

### 2.4 Machine-readable read-only print mode

The current official CLI changelog documents non-interactive answers for read-only slash commands in print mode, including:

```text
/usage
/quota
/credits
/model
/effort
/skills
```

It states that these can emit a structured payload under JSON or stream-JSON output without:

- starting an agent turn;
- spending quota;
- leaving a conversation behind.

This is the highest-value M6 finding.

Candidate invocation, subject to installed-help verification:

```text
agy --output-format json -p "/usage"
```

M6 must not hard-code argument order until `agy --help` confirms the installed syntax.

### 2.5 Official status-line schema

The official status-line schema contains a `quota` object keyed by model or bucket ID. Documented fields include:

```text
remaining_fraction
reset_time
reset_in_seconds
```

The same payload may also include private or unrelated fields such as email, workspace, conversation ID, VCS state, task count, and agent state.

Therefore:

- status line is useful as schema corroboration;
- it is not the preferred M6 source;
- M6 v1 should not install or mutate an Antigravity status line when the read-only CLI can produce a current structured result;
- any future status-line adapter must strictly allowlist quota fields before publication.

### 2.6 AI Credits

The official `/credits` command displays AI Premium credit balance and consumption information. Official plan material describes AI credits as an overage mechanism rather than the base model-quota percentage.

UMA must keep these units separate:

```text
Model quota remaining → percentage/fraction semantics
AI Credits balance    → exact Credits semantics
```

Do not combine the two into one denominator or convert Credits into a percentage without a complete same-observation total.

### 2.7 Current plan model

Official plan material indicates that Gemini quota grouping can change over time. A recent plan update combined Gemini Flash and Pro consumption into a shared pool while non-Gemini models retained separate fixed quota treatment.

M6 must not hard-code a permanent list such as “Flash / Pro / Claude.” It must preserve provider-supplied quota bucket identity and validate current scope dynamically.

---

## 3. Candidate source classes

| Source candidate | Authority | Feasibility | Privacy | M6 decision |
|---|---|---:|---:|---|
| `agy` read-only print `/usage` JSON | Official | High | Strong | **Primary** |
| `agy` read-only print `/credits` JSON | Official | High, schema pending | Strong | Optional detail/second channel |
| Antigravity custom status line JSON | Official | Medium | Payload contains private fields | Dossier-only fallback/corroboration |
| Antigravity 2.0 local language server | Undocumented as public quota interface | Unproven | Unknown | Research evidence only; no production use |
| Third-party quota CLI or local proxy | Unofficial | Demonstrates possibility only | Often touches tokens/private endpoints | Reject as production source |
| Direct Google/Cloud Code internal endpoint | Undocumented/private | Technically possible | Credential and policy risk | Prohibited |
| Keyring/token read | Provider credential access | Technically possible | Unacceptable under current policy | Prohibited |
| Account-web scraping | Fallback source class | Unnecessary while CLI source works | Larger privacy surface | Not part of M6 primary path |
| Local activity/token estimate | Local estimate only | Does not provide account quota | Misleading for remaining | Prohibited as quota substitute |

---

## 4. Recommended M6 source architecture

```text
UMA Antigravity source controller
→ exact signed/verified `agy` executable
→ short-lived provider-owned CLI process
→ read-only `/usage` print command
→ bounded JSON stdout
→ strict Antigravity quota decoder
→ normalized percentage windows
→ Agent connector
→ registry / serialized UsageStore
→ shared presentation
→ main panel + Desktop Assistant
```

### 4.1 Why short-lived CLI invocation is preferred

- No permanent daemon.
- No provider credential enters UMA.
- No CLI settings mutation.
- No status-line installation.
- No user prompt or model task.
- Current read can occur even when the Antigravity GUI is closed, subject to authenticated CLI capability.
- Process ownership and timeout are simple to audit.

### 4.2 Neutral working directory

The connector should run `agy` from an empty UMA-owned directory, not from the user's repository or home project.

Purpose:

- prevent project discovery;
- avoid reading workspace configuration;
- minimize accidental conversation context;
- make “read-only quota command” evidence clearer.

### 4.3 Process boundary

Candidate limits, finalized by M6-G1:

```text
one process in flight
15-second request timeout
20-second hard resource timeout
bounded stdout/stderr
no shell interpolation
exact executable path
exact argument array
no provider prompt
no stdin payload
```

Stderr may be reduced to fixed safe error categories. Do not retain raw identity or login URLs.

---

## 5. Quota data contract

### 5.1 Required normalized fields

For each accepted quota bucket:

```text
window/bucket ID
safe display label when provider-supplied and bounded
remaining fraction or remaining percentage
reset time when supplied
reset duration when supplied
observation timestamp
source version
```

### 5.2 Remaining semantics

Official status-line documentation uses `remaining_fraction`.

When this explicit field is present:

```text
remainingPercent = remaining_fraction × 100
```

Do not apply `100 - value` to a remaining fraction.

If the print-mode schema instead supplies an explicit used percentage, the decoder may apply:

```text
remainingPercent = 100 - usedPercent
```

Only explicit field semantics are allowed. Do not infer semantics from the numeric range alone.

### 5.3 Validation

- finite numeric values only;
- fraction must be `0...1`;
- percentage must be `0...100`;
- no silent clamp;
- missing is unavailable, not zero;
- reset must be valid ISO-8601 or a bounded nonnegative duration;
- future schema version fails closed unless explicitly supported;
- unknown fields are discarded;
- private fields are never passed to UMA business logic.

### 5.4 Multiple quota groups

Preserve quota buckets independently.

Do not:

- sum unrelated quotas;
- assume two model names share one pool;
- split one shared pool into model-specific quotas;
- label a non-Gemini pool as a Gemini pool;
- hard-code model names as permanent contract.

The provider-neutral Maximum Decrement policy selects the compact display window after normalization. On cold start, existing UMA logic uses the lowest finite remaining value when no decrement history exists.

### 5.5 AI Credits

`/credits` is optional in M6.

It may be admitted only when:

- the JSON schema is structured and stable;
- an exact current spendable balance is supplied;
- balance and consumption/grant values are distinguishable;
- no billing, purchase, identity, or history field must be retained;
- the shared channel model can represent it without changing WorkBuddy semantics;
- total channels remain at most two.

If these conditions fail, M6 quota support proceeds without Credits.

---

## 6. Authentication and setup feasibility

### 6.1 Existing authenticated CLI

Best path:

```text
UMA checks `agy`
→ read-only quota command succeeds
→ source admitted after current valid observation
```

### 6.2 CLI missing or feature absent

Return:

```text
SETUP REQUIRED
```

A separate M6-SETUP-G1 may:

- install or update through the current official Google installer;
- let the Human complete provider-controlled Google Sign-In;
- receive no credential or login code;
- rerun the feature probe.

### 6.3 Logged out or expired session

Routine refresh must not repeatedly open login.

Expected behavior:

- classify `loginRequired`;
- suspend automatic refresh;
- withdraw Fresh admission;
- show `Open Antigravity / Sign In` action;
- resume only after Human action and current successful read.

### 6.4 Enterprise modes

Google Cloud / enterprise authentication may produce different usage semantics.

M6-G1 must classify:

- individual Google AI plan;
- enterprise/GCP consumption mode;
- unsupported or ambiguous account mode.

M6 v1 may support individual plan quota first and return conditional/unsupported for enterprise if percentage semantics are absent.

---

## 7. Refresh feasibility

### 7.1 Recommended cadence

Because `/usage` explicitly refreshes backend quota, initial cadence should be conservative:

```text
launch read
→ 5-minute interval after completion
→ Manual Refresh shares the same gate
```

Minimum interval:

```text
not faster than 3 minutes
```

### 7.2 Required scheduling properties

- one source-owned timer;
- one process/read in flight;
- no overlap;
- no catch-up burst;
- no immediate retry storm;
- manual read coalesces;
- sleep/wake schedules one normal next read;
- auth failure suspends;
- provider unavailable does not affect Codex, Claude, or WorkBuddy;
- Desktop Assistant owns no timer.

### 7.3 Quota consumption

Official current changelog states the read-only print commands do not spend quota or create an agent turn. M6-G1 must verify this on the installed version and record only sanitized evidence.

---

## 8. UI feasibility

### 8.1 Provider order

```text
1. Codex
2. Claude Code
3. WorkBuddy
4. Google Antigravity
```

M6 remains within the four-provider Regular-mode allowance. Cursor, as provider five, will own the forced-Minimalist transition later.

### 8.2 Main panel

Collapsed:

- Google Antigravity;
- selected remaining percentage;
- selected quota-group label;
- source-state mark.

Expanded:

- all accepted quota groups;
- remaining percentage per group;
- reset information when supplied;
- current source and CLI version;
- last successful read;
- optional exact AI Credits detail if admitted;
- source transparency;
- Check / Refresh / Open Antigravity actions.

### 8.3 Desktop Assistant

The Assistant consumes only the shared immutable presentation.

Regular:

- provider mark;
- Google Antigravity;
- selected remaining percentage;
- selected group/reset detail already permitted by shared presentation.

Minimalist:

- provider/source-state mark;
- selected remaining percentage.

No Assistant-owned CLI process, timer, decoder, cache, or window selection.

---

## 9. Privacy feasibility

### 9.1 Allowed

- quota bucket identifier;
- remaining fraction/percentage;
- reset metadata;
- safe CLI version;
- exact current AI Credits only if separately admitted;
- observation and freshness metadata.

### 9.2 Rejected

- email;
- account ID;
- plan identity unless separately required and approved;
- conversation ID;
- cwd/workspace;
- repository/VCS data;
- prompts or responses;
- task history;
- tool data;
- keyring contents;
- tokens;
- login URL;
- raw stdout payload persistence;
- raw stderr persistence.

### 9.3 Source transparency

Proposed disclosure:

```text
Source
Official Antigravity CLI read-only quota command

Authentication
Managed by Antigravity

Credentials accessed by UMA
None

Network
Antigravity CLI performs a current quota read

Provider tasks or prompts created
None

Data retained
Sanitized quota windows and freshness only
```

---

## 10. Risk register

| Risk | Severity | Mitigation |
|---|---:|---|
| Installed CLI lacks structured print support | Blocking | Feature probe; M6-SETUP-G1 update path |
| Main changelog capability not yet in installed release | High | Gate by behavior, never version assumption alone |
| Routine command opens browser when logged out | High | Setup gate; suspend after login-required classification |
| Output contains identity/workspace fields | High | Strict allowlist before connector publication |
| Remaining-vs-used semantic confusion | High | Explicit field-name contract; no range-based guess |
| Shared/duplicate quota groups | High | Preserve bucket IDs; no hard-coded model pooling |
| `/usage` backend refresh has rate limits | Medium | 5-minute cadence, one in flight, no retry storm |
| CLI startup loads project state | Medium | Empty UMA-owned working directory |
| Process hangs or emits excessive output | Medium | Hard timeout and output cap |
| AI Credits confused with model quota | High | Separate unit and optional admission |
| Account changes with stale persisted value | High | Current-read admission; hide disk cache before new success |
| Enterprise output differs | Medium | Account-mode classification; fail closed |
| Shared-surface edit breaks M5 | High | Additive-only changes; protected-file hash audit |
| Provider count changes Assistant density | Medium | Four-provider matrix; no forced Minimalist yet |

---

## 11. Feasibility decision matrix

| Requirement | Research result |
|---|---|
| Official source | Yes: Antigravity CLI |
| Machine-readable output | Officially documented in current changelog |
| Current quota read | `/usage` refreshes disk/backend quota state |
| No API key in UMA | Yes |
| No copied token | Yes |
| No Keychain read by UMA | Yes |
| No provider task/prompt | Officially documented for read-only print mode |
| No quota consumption | Officially documented; live verification still required |
| Exact remaining semantics | Strong candidate; live schema required |
| Reset metadata | Official status-line schema supports it; print schema must be proven |
| Automatic refresh | Feasible through short-lived CLI polling |
| GUI/CLI same product scope | Shared engine/settings officially documented; live account parity required |
| Privacy allowlist | Feasible |
| Provider independence | Compatible with current connector architecture |
| Public distribution dependency | None beyond normal UMA signing; no browser extension needed |

Final research verdict:

```text
CONDITIONAL GO

Primary source:
Official Antigravity CLI read-only structured `/usage` output

Admission blocker:
Installed-version live schema and behavior have not yet been proven
```

---

## 12. Official research references

Retrieved 2026-08-08:

- Antigravity CLI official repository: https://github.com/google-antigravity/antigravity-cli
- Official CLI changelog: https://github.com/google-antigravity/antigravity-cli/blob/main/CHANGELOG.md
- CLI overview: https://antigravity.google/docs/cli-overview
- Model Quotas `/usage` / `/quota`: https://antigravity.google/docs/cli/commands/usage
- Status-line schema: https://antigravity.google/docs/cli/statusline
- AI Credits: https://antigravity.google/docs/cli/credits
- AI Credits command: https://antigravity.google/docs/cli/commands/credits
- Plans: https://antigravity.google/docs/plans
- Plan changes: https://antigravity.google/blog/changes-to-antigravity-plans
- Product page: https://antigravity.google/product/antigravity-cli

Third-party Antigravity quota tools are research corroboration only and are not admitted sources.
