# UMA M8 Kimi QA Issue Ledger

Goal: M8-G1R — live installed Kimi CLI source re-admission
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
