# Usage Monitor Altoget — M7 Goals

**Milestone:** M7 — Cursor Support
**Version:** 1.0
**Current Goal:** M7-B0
**Only next Goal after B0:** M7-G1

## Governing sequence

```text
M7-B0
→ M7-G1
→ M7-SETUP-G1 only if required
→ M7-G2
→ M7-G3
→ M7DBG-G1
→ M7A-G1
→ M7ADBG-G1
→ M7-CLOSE-G1
```

Every Goal starts only after direct authorization and ends under Completion
Lock. Source admission precedes implementation. A green test or build does not
authorize a later Goal, live provider action, installation or remote delivery.

## M7-B0 — Baseline, plan and scope lock

Create `codex/uma-m7-cursor` and
`/Users/juliushe/Developer/UMA-M7-Cursor` from exact M6 closeout commit
`a6b846ea2785448c4d4e51ec0e775ff9220d33f5`, tree
`d7f789c3d2fd4e98a43256737b733c37fe5b0c81`. Add only the M7 governing
records and focused planning test, reproduce the accepted baseline, preserve
all protected mechanisms, commit `docs(m7): establish Cursor source-admission
plan`, finish clean and stop.

No Cursor process, login, install, update, account access, provider read,
connector, UI or package work is permitted in B0.

## M7-G1 — Cursor Official Source, Authentication, and Schema Admission

Determine whether a current official Cursor source can provide current quota
with stable identity and freshness, structured machine-readable fields,
provider-controlled authentication and no credential exposure, prompt/task or
intentional spend. Inspect sources only in the order defined by `M7_Plan.md`.

Return exactly one decision:

- `GO` — all mandatory source, schema, identity, freshness, authentication,
  privacy and no-provider-work evidence is proven;
- `CONDITIONAL GO` — the primary quota is reliable and only accepted optional
  metadata is absent;
- `SETUP REQUIRED` — an official admissible source exists but the current
  device lacks a bounded provider-owned prerequisite;
- `NO-GO` — no source satisfies the contract.

Do not implement production runtime in M7-G1. M7-G2 remains locked until a
`GO` or accepted `CONDITIONAL GO`.

## M7-SETUP-G1 — Optional official setup

Run only after `SETUP REQUIRED` and separate Founder authorization. Permit only
the exact official provider-controlled prerequisite identified by M7-G1.
Never introduce API-key, copied-token, manual-quota or private-source fallback.
After setup, resume M7-G1; do not skip admission.

## M7-G2 — Admitted source and main-panel implementation

Implement only the source contract admitted by M7-G1. Add a bounded connector,
strict decoder, one refresh owner, fail-closed lifecycle, Settings and main
panel presentation. Preserve Codex, Claude Code, WorkBuddy and Antigravity.
Cursor must not appear without a current successful admitted read.

## M7-G3 — Live source and five-provider acceptance

Validate bounded real Cursor reads, parity with the official source, freshness,
coalescing, recovery, teardown and provider isolation. Prove the first real
four-to-five density transition: four visible providers may remain Regular;
five visible providers force Minimalist.

## M7DBG-G1 — Five-provider main-app defect closure

Exercise deterministic and bounded live main-app matrices, source collisions,
failure isolation, lifecycle, resource behavior, localization, accessibility
and package integrity. Repair only direct M7/shared additive defects.

## M7A-G1 — Cursor Desktop Assistant presentation

Begin only after main-app acceptance and explicit authorization. Use the shared
immutable presentation; do not duplicate source ownership, schedulers, reads,
selection or quota normalization in the Assistant.

## M7ADBG-G1 — Combined five-provider closeout

Validate main-panel/Assistant parity, density, accessibility, lifecycle,
resources, privacy and exact package provenance across all five providers.

## M7-CLOSE-G1 — Current-truth closeout

Record the final provider/source matrix, limitations, package evidence and next
program without rewriting historical records. No push, release or installation
is implied.

## Completion Lock

After M7-B0, stop. `M7-G1 — Cursor Official Source, Authentication, and Schema
Admission` is the only permitted next task.
