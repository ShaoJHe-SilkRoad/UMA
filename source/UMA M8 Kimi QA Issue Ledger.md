# UMA M8 Kimi QA Issue Ledger

Goal: M8-G1 — Kimi unified source admission
Decision: `SETUP REQUIRED`

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

| Issue ID | Finder | Severity | Evidence | Acceptance impact | Repair / owner | Focused retest | Regression retest | Final status |
|---|---|---|---|---|---|---|---|---|
| M8G1-001 | DEV + source examiner | Blocking external setup gate | No Kimi executable or app resolved from exact paths, PATH, Spotlight, or LaunchServices | Live `/usage` behavior and installed trust cannot be admitted | Record `SETUP REQUIRED`; M8-SETUP-G1 owns official install/setup after direct authorization | Source-admission setup-routing tests | Current deterministic serial suite | CLOSED AS DECISION — setup gate explicit |
| M8G1-002 | DEV + privacy examiner | Major | Official docs expose interactive TUI `/usage`, while `-p` is Agent prompt mode and no standalone structured usage command is documented | Unsafe substitution could create provider work or spend | Prohibit `kimi -p "/usage"`; require installed-help-derived control and bounded re-admission | Prompt-mode rejection and no-work gate tests | Current deterministic serial suite | CLOSED — fail-closed contract added |
| M8G1-003 | Unit/account-mode examiner | Blocking external evidence gate | Shared monthly membership, Kimi Code five-hour/weekly limits, plan transition, and Extra Usage continuation are documented but no current account observation exists | Unified truth and `0%` continuation cannot be admitted | Separate all three channels; record `CONDITIONAL / CONDITIONAL / UNREADABLE`; setup and later source recheck own live evidence | Channel and continuation tests | Current deterministic serial suite | OPEN — blocks M8-G2 by design |
| M8G1-004 | QA runner | Major | Durable source decisions could accidentally retain identity, raw output, quota values, or private routes | Privacy/scope violation | Add explicit allowlist/denylist plus synthetic sanitizer tests | Privacy/source-admission tests | Secret, identity, protected-set, and diff audits | CLOSED |

Open external evidence gates do not weaken this Goal's PASS: M8-G1's product is
the evidence-backed source decision. They keep runtime implementation locked.

## Verification ledger

| Check | Result |
|---|---|
| Starting lineage and clean state | PASS — HEAD `801fd521298fd6f2483cc9eab037562c0bc5a4f9`, tree `0ec25ebaf84e2970e05f29f533ddadc67e46c981` |
| Installed-source inventory | PASS — official CLI/app absent; unavailable artifact fields distinguished from arm64 host |
| Current official public research | PASS — first-party Kimi docs/repository only |
| Qualified provider observations | PASS — 0/3; no unqualified read attempted |
| Provider prompts/tasks/spend | PASS — 0/0/0 |
| Focused M8-G1 source-admission tests | PASS — 14/14 |
| Current deterministic serial `script/test.sh --no-parallel` | PASS — 639 UI + 18 bridge = 657/657 |
| Privacy / identity / secret scan | PASS — bounded exact-file scan; synthetic private markers remain test-only and no durable record retained them |
| M5 and established-provider audit | PASS — production `Sources/**`, package configuration, and package helpers unchanged; installed Desktop executable hash unchanged |
| `source/reference/**` audit | PASS — byte state unchanged from HEAD |
| `git diff --check` | PASS |
| Independent staged-index review | PASS — exact five-file cached scope; no blocking or actionable issue |
| Post-commit clean worktree and empty index | Pending final audit |

## Operation accounting

```text
Kimi quota/source observations: 0 / 3
Kimi prompts: 0
Kimi tasks/conversations: 0
Intentional Kimi spend: 0
Automatic retries: 0
Kimi login/browser actions: 0
Credential/private-state reads: 0
```

## Completion boundary

Overall result: `SETUP REQUIRED`
Channel result: `CONDITIONAL / CONDITIONAL / UNREADABLE`
Only next task: `M8-SETUP-G1` after direct Founder authorization.
`M8-WEB-G1 remains locked.`
`M8-G2 remains locked.`
