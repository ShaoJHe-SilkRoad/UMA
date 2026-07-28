# UMA M3W WorkBuddy Admission Decision

Date: 2026-07-24

## Decision

**`NO-GO`**

Core accepted source:
**none**.

The WorkBuddy product, Credits unit, subscription/resource-package semantics,
and signed-in Plan & Usage display are officially documented. No reviewed
official source exposes the native WorkBuddy account quota through a supported
machine-readable CLI, local service, IPC, hook, export, webhook, or read-only
API.

The exact-product usage page is UI-only and cannot be used under the governing
privacy and source rules. CodeBuddy runtime telemetry belongs to a distinct
CLI/session surface. TokenHub belongs to a separately scoped custom model
provider and cannot be relabeled as WorkBuddy Credits.

Required TokenHub result:

**`TOKENHUB SCOPE UNPROVEN — REJECT`**

## Admission-gate results

| Gate | Result | Basis |
|---|---|---|
| Official ownership | PASS | Tencent and official WorkBuddy sources establish product ownership |
| Exact product identity | PASS | Installed bundle `com.workbuddy.workbuddy` and official product documentation agree |
| Installed state | PASS WITH RISK | WorkBuddy `5.2.6` is installed; strict deep signature verification fails |
| Official account quota semantics | PASS | Official docs define WorkBuddy Credits, plans, packages, and visible available/used values |
| Machine-readable source | FAIL | No documented WorkBuddy quota CLI, IPC, API, hook, export, or webhook |
| Product/account scope | FAIL | No structured source is tied to the current WorkBuddy account and native Credits pool |
| Field/schema/version contract | FAIL | No structured quota payload is documented |
| Authentication boundary | FAIL | No read-only structured WorkBuddy usage authentication contract is documented |
| Privacy | FAIL FOR AVAILABLE PATHS | UI scraping, private storage, and undocumented mechanisms are prohibited |
| Deterministic normalization | FAIL | No official scope-matched remaining/total or used/limit pair is available |
| Freshness and recovery | FAIL | No source event, polling, stale, logout, or version behavior is documented |
| Package feasibility | FAIL | No supported source/helper exists; installed WorkBuddy signature is invalid |
| Live read | NOT JUSTIFIED | Zero of ten authorized operations used; no source was admitted |

## Rejected candidates

- WorkBuddy personal Plan & Usage page: exact-product but UI-only.
- WorkBuddy CLI/status command: not documented.
- WorkBuddy local IPC/service: not documented.
- WorkBuddy hook, connector, plugin, webhook, or notification: no quota
  contract.
- WorkBuddy export or local metadata: no documented quota export; private data
  access is prohibited.
- CodeBuddy Code CLI, status line, ACP, HTTP API, daemon, hooks, and telemetry:
  distinct runtime/session scope and no aggregate WorkBuddy Credits balance.
- TokenHub/Token Plan: separate package/key/model/Tencent Cloud scope.
- Any inferred quota from tasks, tokens, model prices, cost, duration, or
  historical activity.

Rejected sources:
**WorkBuddy UI, undocumented WorkBuddy CLI/IPC/hooks/exports/APIs, CodeBuddy
runtime telemetry, TokenHub, and private application data.**

## Blocking conditions

M3W-G2 remains blocked until an official structured WorkBuddy usage source:

1. explicitly names native WorkBuddy Credits and the exact account/subscription
   scope;
2. exposes a direct remaining percentage or a same-scope
   remaining/total or used/limit pair;
3. defines metric units, quota/window identity, reset behavior, freshness,
   versioning, and failure states;
4. provides a read-only authentication boundary without credential extraction
   or retention;
5. works without browser/UI automation, OCR, screenshots, private storage,
   binary inspection, or undocumented IPC;
6. passes allowlist sanitation, bounded live evidence, recovery, package, and
   independent review.

Trusted installed-package provenance must also be restored before that bundle
is used as evidence or as a runtime dependency.

## Allowed next action

Documentation and owner coordination for an official Tencent-supported source
are allowed under a separately scoped task. A distinct TokenHub-provider
admission goal may be proposed separately if the Founder wants TokenHub
reported under its own name and account scope.

M3W-G2, production connector work, runtime provider ordering, Claude Code,
Manus, and later providers must not begin automatically.

## Operation and privacy result

- Provider usage/status operations: 0.
- Login or account interaction: none.
- WorkBuddy launch: none.
- Private storage, credentials, identity, tasks, prompts, or responses read:
  none.
- Raw or sanitized provider payload created or staged: none.
- Product source/configuration changed: none.

## Completion Lock

Close M3W-G1 after the exact five-document staged audit and local documentation
commit. Do not implement WorkBuddy, begin M3W-G2, resume Claude Code, push,
tag, release, notarize, deploy, or publish.
