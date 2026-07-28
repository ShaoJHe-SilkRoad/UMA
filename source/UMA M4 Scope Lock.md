# UMA M4 Scope Lock

Status: M4-G1 locked scope
Date: 2026-07-28
Workspace: `/Users/juliushe/Developer/UMA-M4-Manus`
Branch: `codex/uma-m4-manus`
Starting commit: `55104d1009f19a78b4b6f1b857afb1487068e413`
Starting tree: `9bf0c711a0cc60c8a056f4e1618e9c2ea4f27f2b`

## M4-G1 allowed work

M4-G1 may:

- inspect the Founder-approved governing documents and current source
  architecture;
- inspect current official Manus and Apple public documentation;
- classify the current `AvailableCredits` schema;
- define the narrow request, decoder, cadence, privacy, Keychain, and
  disconnect contract;
- add a test-only deterministic feasibility harness with synthetic data;
- run focused tests, the full suite, build verification, and Git audits;
- create exactly the five required M4-G1 records;
- stage only the exact M4-G1 files;
- create one local commit:
  `docs(m4): admit Manus Credit source`.

## M4-G1 prohibited work

M4-G1 must not:

- create, request, read, store, or validate a real Manus API key;
- read or modify Keychain;
- perform an authenticated Manus request;
- access Manus account identity, tasks, history, prompts, responses, files,
  cookies, tokens, browser data, or Manus.app private state;
- install or retry the official Manus skill after the accepted B0 toolchain
  failure;
- install Node, npm, npx, Homebrew, an SDK, or another package manager;
- implement the production Manus connector or UI;
- modify the installed Desktop application;
- begin M4-G2 or any later goal automatically;
- fetch, push, tag, amend, release, notarize, deploy, publish, or open a pull
  request.

## Exact admitted production boundary

Later implementation is limited to:

```text
one UMA-owned Keychain item
  → GET https://api.manus.ai/v2/usage.availableCredits
  → strict documented-field decoder
  → total_credits as current balance
  → provider-neutral Credit presentation
```

Everything else is outside the admission boundary.

## M4-G1 file lock

The exact M4-G1 change set is:

1. `source/UMA M4 Manus Source Dossier.md`
2. `source/UMA M4 Manus Admission Decision.md`
3. `source/UMA M4 Manus Secret Handling Contract.md`
4. `source/UMA M4 Manus QA Issue Ledger.md`
5. `source/UMA M4 Scope Lock.md`
6. `Tests/CodexUsageUITests/M4G1ManusSourceAdmissionTests.swift`

No production source or package configuration file is authorized for this
goal. If verification requires a production change, M4-G1 stops and reports a
blocker instead.

## Completion state

M4-G1 completes only after:

- official-source and schema evidence is recorded;
- the admission decision and secret contract are internally consistent;
- deterministic feasibility tests and required regressions pass;
- Debug/Release or equivalent package builds pass;
- the exact staged index passes an independent review;
- one authorized local commit exists;
- worktree and index are clean.

The completion lock then stops the task. M4-G2 does not begin automatically.
