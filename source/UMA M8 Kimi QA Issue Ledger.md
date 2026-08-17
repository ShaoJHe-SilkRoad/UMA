# UMA M8 Kimi QA Issue Ledger

Goal: M8-G1R and M8-WEB-G1 source admission
Decision: `NO-GO`

## Exact authorized file scope

```text
source/UMA M8 Kimi Local Source Dossier.md
source/UMA M8 Kimi Admission Decision.md
source/UMA M8 Kimi Privacy Contract.md
source/UMA M8 Kimi QA Issue Ledger.md
Tests/CodexUsageUITests/M8G1KimiSourceAdmissionTests.swift
```

Production source files changed: NO
Existing provider mechanisms changed: NO
M5 frozen files changed: NO
`source/reference/**` changed: NO
Package scripts changed: NO
Browser extension files changed: NO
Installed Desktop UMA changed: NO

## Issues

| Issue ID | Severity | Discovery | Exposure class | Root cause | Repair / disposition | Focused verification | Regression verification | Final state |
|---|---|---|---|---|---|---|---|---|
| M8G1R-001 | Major | Observation 1 did not reach `/usage` and created one task-owned workspace-trust marker | Local task-scoped provider preference; no credential/account content | The empty neutral directory was not yet trusted; the attempted Enter was consumed by the default workspace-trust control | Add idle-TUI readiness gate; classify the attempt; remove only the exact marker at closeout | Probe contract test and exact-path cleanup audit | Privacy and protected-state audits | CLOSED |
| M8G1R-002 | Blocking admission | Observation 2 reached an idle marker but yielded no recognized usage panel | No private exposure; sanitized booleans only | Automated keystroke/control lifecycle was not proven reliable | Add provider-owned autocomplete recognition before any submit; do not use prompt mode | Positive-recognition and no-fallback tests | Full deterministic suite | CLOSED AS DECISION — source remains unadmitted |
| M8G1R-003 | Blocking admission | Final capped run returned no retainable sanitized packet | No retained payload | Live evidence unavailable within the 3-observation cap | Count 3/3, do not retry, do not infer schema from public code, record CLI `NO-GO` | Accounting/decision-routing tests | Full deterministic suite | CLOSED AS DECISION |
| M8G1R-004 | Major | A restricted sandbox Code Signing call returned an invalid/subsystem result for unchanged bytes | Tooling classification only | macOS security subsystem was unavailable inside the restricted context | Re-run the identical read-only trust check through the approved macOS context; exact hash/version/Team remained stable and strict verification passed | Trust-state record assertions | Protected executable audit | CLOSED |
| M8G1R-005 | Major | Live evidence could have retained exact quota, reset, balance, or identity data | Privacy retention risk | Raw TUI rendering contains values not needed durably | In-memory classification-only probe; no raw transcript/file; explicit allowlist and denylist | Sanitizer and durable-record tests | Identity/secret/privacy scans | CLOSED |
| M8G1R-006 | Blocking product gate | Shared membership, current Code windows, Extra Usage state, stable live identity, and repeatability remain unproven | Product-truth gap | Zero successful sanitized observations were retained | `MISSING / NO-GO / UNREADABLE`; M8-G2 remains locked | Channel/account-mode/normalization tests | Durable-record agreement tests | OPEN — requires new Founder source direction |
| M8G1R-007 | Minor | Initial focused run found three prose assertions that did not match the revised durable records | Deterministic test-only mismatch | Assertions targeted superseded wording rather than the same semantic contract | Correct only the three exact record assertions; do not weaken admission gates | 17/17 focused tests PASS | Final 668/668 deterministic tests PASS | CLOSED |

## Verification ledger

| Check | Result |
|---|---|
| Starting lineage and clean state | PASS — accepted M8-SETUP-G1 HEAD/tree; clean worktree; empty index |
| Installed exact CLI trust | PASS — 0.34.0, arm64, exact SHA-256, current-user mode 0755, no symlink, Team ID, strict signature |
| Current official control contract | PASS — interactive built-in only; prompt mode and standalone structured claims rejected |
| Live observation accounting | PASS — 3/3 conservatively consumed; no retries; zero successful sanitized observations retained |
| Provider prompts / turns / tasks / intentional spend | PASS — 0 / 0 / 0 / 0 |
| `/credits` and credential/private reads | PASS — 0 / 0 |
| Focused M8-G1/G1R source-admission tests | PASS — 17/17 |
| Complete deterministic `script/test.sh --no-parallel` | PASS — final no-source-change run 668/668 (650 application tests plus 18 bridge tests); one preceding diagnostic run reported two transient issues that did not reproduce |
| Privacy / identity / secret scan | PASS — bounded changed-record scan retained no identity, secret, credential, raw payload, exact Founder value, or user-absolute path |
| M5 and existing-provider audit | PASS — no production source changed; Codex, Claude, WorkBuddy, Antigravity, Cursor, and the M5 frozen set remain untouched |
| `source/reference/**` audit | PASS — unchanged |
| Protected Desktop executable audit | PASS — exact executable SHA-256 remains `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` |
| Task-owned temporary-state cleanup | PASS — exact trust marker, neutral directory, probe, bytecode path, official-source clone, and task-owned test summary are absent; no Kimi process remains |
| `git diff --check` | PASS |
| Independent staged-index review | PASS — exact five-file cached scope; no blocking or actionable issue |
| Post-commit clean worktree and empty index | Pending final audit |

## Operation accounting

```text
Kimi /usage observations: 3 / 3
Successful sanitized observations retained: 0
Automatic retries: 0
Kimi prompts / Agent turns / tasks: 0 / 0 / 0
Intentional Kimi spend: 0
/credits reads: 0
Login/browser actions: 0
Credential/private-state reads: 0
Raw provider payloads retained: 0
Exact Founder values retained: 0
```

## Completion boundary

Overall result: `NO-GO`
Channel result: `MISSING / NO-GO / UNREADABLE`
Exactly one next task: `Founder source-direction decision`.

`M8-WEB-G1 remains locked.`
`M8-G2 remains locked.`

## M8-WEB-G1 exact authorized file scope

```text
source/UMA M8 Kimi Browser Source Dossier.md
source/UMA M8 Kimi Browser Admission Decision.md
source/UMA M8 Kimi Privacy Contract.md
source/UMA M8 Kimi QA Issue Ledger.md
Tests/CodexUsageUITests/M8WEBG1KimiBrowserAdmissionTests.swift
```

Production source files changed: NO
Existing provider mechanisms changed: NO
WorkBuddy mechanism changed: NO
M5 frozen files changed: NO
`source/reference/**` changed: NO
Package scripts changed: NO
Production browser extension files changed: NO
Installed Desktop UMA changed: NO
Claude-related changes: NONE

## M8-WEB-G1 issues

| Issue ID | Severity | Discovery | Exposure class | Root cause | Repair / disposition | Focused verification | Regression verification | Final state |
|---|---|---|---|---|---|---|---|---|
| M8WEB-001 | Blocking architecture | Provider-controlled login completed twice in the isolated Kimi web session, but the window closed and no authenticated quota state persisted | No credential or account payload retained | Kimi authentication was incompatible with the isolated session and the Human's normal Safari/Apple Passwords workflow | Classify isolated session as not suitable; do not request another isolated login; select bounded Safari fallback | Architecture-selection assertions | Durable-record agreement | CLOSED |
| M8WEB-002 | Major privacy | One broad read-only Safari accessibility command transiently exposed unrelated non-Kimi accessibility metadata | Transient unrelated application metadata; no Kimi/account/credential content | Ad-hoc DEV inspection was broader than the exact task-owned evidence contract | Retire broad accessibility inspection; use exact task paths/IDs/PIDs/counts and classification-only receipts; retain none of the transient output | Privacy-contract and incident-containment assertions | Identity/secret/privacy scans | CLOSED |
| M8WEB-003 | Major probe | One valid browser extraction was rejected by native validation | Sanitized in-memory receipt only; nothing retained | Native ISO-8601 parsing rejected valid fractional-second browser timestamps | Accept fractional and whole-second ISO-8601 timestamps; keep strict schema and output allowlist | Temporary native-validator contract retest | Four later classification-only receipts accepted | CLOSED |
| M8WEB-004 | Major probe | Short-lived containing-app dispatch acknowledged without reaching the extension background | No provider payload | The transient sender exited before reliable Safari extension delivery | Move dispatch ownership to the long-running task app; retain Human toolbar activation for the capped admission reads | Task-app lifecycle/signature/registration checks | No production runtime changed | CLOSED AS PROBE |
| M8WEB-005 | Blocking admission | Four retained authenticated receipts on the exact Membership route repeated `UNSUPPORTED_LAYOUT`; Shared Membership, direction, and cycle remained absent | Classification-only receipt; no exact value or raw DOM | Current provider-rendered layout does not match the bounded semantic contract | Fail closed; do not broaden to raw page text, OCR, private APIs, or account-specific values; stop after 5/8 page observations | M8-WEB-G1 admission tests | Full deterministic suite 683/683 PASS | CLOSED AS DECISION — NO-GO |
| M8WEB-006 | Cleanup | The empty metadata-only companion container was protected from direct deletion | No provider or account data | macOS container protection denied the exact command-line deletion path | Finder removed the exact container from `$HOME/Library/Containers`; after explicit Human confirmation, the isolated exact Trash item was permanently deleted | Exact path, owner, non-symlink, process, and registration checks | Safari Off and zero-provider-operation audit | CLOSED |

## M8-WEB-G1 verification ledger

| Check | Result |
|---|---|
| Starting lineage and clean state | PASS — accepted M8-G1R HEAD/tree; clean worktree; empty index |
| Isolated-session classification | PASS — not suitable for admission/Human auth UX; no repeat login requested |
| Safari companion architecture | PASS — real embedded extension, exact-site activeTab flow, browser-layer sanitizer, native classification-only receipts |
| Manifest/route/privacy contract | PASS — exact three permissions; no host permissions/static injection/cookie/storage/history/private route |
| Authenticated observation accounting | PASS — 5/8 page observations; 4 retained valid receipts; 0 raw/exact/private values |
| Provider prompts / turns / tasks / intentional spend | PASS — 0 / 0 / 0 / 0 |
| Shared Membership decision | PASS — `NO-GO`; mandatory semantic contract unavailable |
| Kimi Code / Extra Usage decisions | PASS — `MISSING` / `ABSENT` |
| WorkBuddy and existing-provider protection | PASS — no production provider mechanism changed |
| Focused M8-WEB-G1 and predecessor tests | PASS — 32/32 |
| Complete deterministic `script/test.sh --no-parallel` | PASS — 683/683 (665 application tests plus 18 bridge tests) |
| Privacy / identity / secret scans | PASS — no real identity, secret signature, raw provider payload, or exact Founder value retained |
| M5 frozen set and `source/reference/**` | PASS — no changed path |
| Safari unsigned-extension restoration | PASS — Developer setting visibly verified Off; Safari closed |
| Task extension/process/temporary-root cleanup | PASS — extension unregistered; task processes zero; exact M8-WEB-G1 `/private/tmp` roots absent |
| Exact companion container cleanup | PASS — exact container and isolated exact Trash item absent |
| `git diff --check` | PASS |
| Independent staged-index review | PASS — exact five-file cached scope; no blocking or actionable issue |
| Post-commit clean worktree and empty index | Required after commit; final report records the audit |

## M8-WEB-G1 operation accounting

```text
Authenticated page observations used: 5 / 8
Valid sanitized receipts retained: 4
Automatic retries: 0
Provider prompts / Agent turns / tasks: 0 / 0 / 0
Intentional spend / account changes: 0 / 0
/credits reads: 0
Credential/cookie/token/browser-profile reads: 0
Raw DOM/HTML/page-text receipts retained: 0
Exact Founder quota/balance values retained: 0
Kimi provider operations during cleanup: 0
```

## M8-WEB-G1 completion boundary

Overall result: `NO-GO`
Channel result: `NO-GO / MISSING / ABSENT`
Exactly one next task: `Founder Kimi source-direction / M8 closeout decision`.

`M8-G2 remains locked.`
