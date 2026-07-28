# UMA M3W WorkBuddy QA Issue Ledger

Date: 2026-07-24

## Gate summary

Admission verdict:
**`NO-GO`**.

The dossier is a privacy-safe negative source-admission record. No provider
operation, login, browser/UI access, raw response, identity, credential, task
content, private path, or account data was captured.

## Issue ledger

| Issue ID | Found by | Severity | Evidence | Acceptance impact | In scope | Repair / disposition | Focused verification | Status |
|---|---|---:|---|---|---|---|---|---|
| M3W-001 | Source / Protocol Auditor | Blocker | Official WorkBuddy docs expose Credits usage only through the signed-in personal Plan & Usage page | No admissible machine-readable native WorkBuddy quota source | Yes, classification only | Record `NO-GO`; require an official structured source | Official-source candidate matrix and claim map | Open provider condition |
| M3W-002 | Privacy Steward | Blocker | Available exact-product path is authenticated UI | Browser/UI automation, OCR, screenshots, and visible-text scraping are prohibited | Yes | Reject the UI as a protocol; no login or capture | Zero-operation and privacy audit | Closed for this decision |
| M3W-003 | Source / Protocol Auditor | High | Official `codebuddy`/`cbc` and HTTP API describe CodeBuddy Code runtime/session data, not aggregate WorkBuddy Credits | Prevents product-scope substitution | Yes | Classify CodeBuddy mechanisms separately and reject for M3W | Ownership and field-scope cross-check | Closed |
| M3W-004 | Source / Protocol Auditor | Blocker | TokenHub is a separately authorized Token Plan package/key/model scope | TokenHub balance may diverge from native WorkBuddy Credits | Yes | Record `TOKENHUB SCOPE UNPROVEN — REJECT`; allow only a separate future provider goal | Eight-part TokenHub scope test | Closed for M3W |
| M3W-005 | Installed Product Auditor | High | `/Applications/WorkBuddy.app` strict deep signature verification reports an invalid signature | Installed bundle cannot provide trusted package provenance | Yes, evidence only | Record package risk; do not repair or reinstall in this goal | Static public package audit | Open owner/provider condition |
| M3W-006 | Privacy Steward | High | Private app metadata/cache, task content, account identity, and credentials would be exposed by unsupported discovery routes | Such routes cannot become evidence | Yes | Closed-by-default allowlist and explicit denylist; no private inspection | Tracked-diff privacy and raw-artifact scan | Closed |
| M3W-007 | Primary / QA Runner | Medium | No candidate passed source admission, so no official usage/status operation ran | Account values, field shapes, latency, freshness, logout, and recovery remain unobserved | Yes | Record zero of ten operations; do not manufacture a probe | Operation accounting and dossier consistency | Closed for this NO-GO |
| M3W-008 | Primary | High | WorkBuddy can have multiple base, bonus, and add-on Credit buckets with distinct expiry/reset behavior | Unsafe sums or percentages could misstate quota | Yes | Permit derivation only from one official same-scope pair; otherwise unavailable | Normalization-contract review | Closed |
| M3W-009 | Primary | High | No official source defines WorkBuddy stale, malformed, logout, version, or recovery behavior | Production failure handling cannot be validated | Yes | Record future independent-state and last-valid contract | Failure/recovery checklist review | Open provider condition |
| M3W-010 | Installed Product Auditor | High | No documented WorkBuddy helper exists; separate CodeBuddy CLI is absent | Commit-exact package cannot depend on a supported runtime source | Yes | Mark package feasibility not credible | Bundle/helper/command inventory | Open provider condition |
| M3W-011 | Privacy Steward / QA Runner | Medium | No executable connector or sanitizer was added | Compiled tests/builds have no implementation target | Yes | Keep goal documentation-only; specify future tests without placeholders | Exact tracked-scope audit | Closed |
| M3W-012 | Independent Examiner | Gate | Complete five-document evidence chain | Required independent acceptance gate | Yes | Examiner accepted `NO-GO`; staged reviewer remains a separate delivery gate | Independent evidence, scope, privacy, and consistency review | Closed — PASS |

## Independent Examiner result

**PASS — `NO-GO` accepted.**

The Examiner independently confirmed:

- the exact baseline and five-file scope;
- official WorkBuddy Credits semantics but no admitted structured protocol;
- CodeBuddy runtime/session mechanisms are not native WorkBuddy quota;
- `TOKENHUB SCOPE UNPROVEN — REJECT` is required;
- field, normalization, authentication, privacy, recovery, and package
  classifications are internally consistent;
- zero of ten live operations is correct;
- no identity, credential, raw payload, private path, generated evidence, or
  product implementation entered the packet.

The packet may advance to exact staging. Staged-index review remains an
independent delivery gate.

## TokenHub scope test

Every item is mandatory before TokenHub could represent a claimed WorkBuddy
quota:

1. Official documentation explicitly connects the TokenHub metric to the exact
   WorkBuddy product and native Credits contract.
2. The source is officially supported for WorkBuddy usage, not merely model
   provider consumption.
3. Authentication proves the same WorkBuddy account scope without retaining an
   identifier.
4. Metric name, unit, plan, window, and reset semantics match WorkBuddy.
5. Official documentation rules out divergent WorkBuddy and TokenHub balances.
6. Product quota remains separate from per-model/provider quota.
7. The read-only authentication boundary is documented and credential-safe.
8. Logout, account transition, expiry, stale behavior, and source versioning
   are defined.

Current evidence fails items 2 through 8. Result:

**`TOKENHUB SCOPE UNPROVEN — REJECT`**

## Deterministic quota-normalization contract

- Inputs must share provider, product/account scope, plan, quota identifier,
  unit, window, reset boundary, and source version.
- Accept only finite, nonnegative numeric values with a positive total/limit.
- Prefer a validated official remaining percentage.
- Otherwise calculate only `100 × remaining / total` or
  `100 × (1 − used / limit)`.
- Do not clamp inconsistent or out-of-range values.
- If official and derived percentages coexist, require agreement within the
  provider's documented rounding precision.
- Zero remaining is exhausted, not unavailable.
- Zero total is undefined unless the provider explicitly marks unlimited.
- Missing is unavailable, never zero.
- Unlimited requires an explicit official marker.
- Missing reset metadata is not synthesized.
- Stale values are not recomputed.
- Never mix different quota buckets, plans, accounts, products, windows,
  TokenHub scopes, or model-provider units.

No current WorkBuddy candidate supplies valid inputs, so normalization remains
unavailable.

## Future failure and recovery acceptance

A future connector and focused tests must prove:

- not installed, logged out, permission denied, source unavailable, app
  closed, supported helper stopped, and network loss fail independently from
  Codex;
- logout or account transition invalidates prior quota without keeping an
  account hash;
- last-valid data is retained only with explicit stale state and age;
- malformed responses and unknown versions do not overwrite last-valid data;
- missing optional fields affect only those fields;
- exhausted zero and explicit unlimited remain distinct;
- recovery occurs through the next bounded scheduled or manual official read;
- no aggressive retry, render-driven polling, or per-surface read
  multiplication occurs;
- any setup is reversible byte-for-byte and metadata-for-metadata without
  accessing credentials;
- no WorkBuddy task is started or modified to obtain quota.

These tests are deferred because no source or implementation is admitted.

## Verification applicability

- Focused compiled tests: **not applicable**; no connector, sanitizer, helper,
  or product code changed.
- Affected existing tests: **not applicable**; documentation-only scope.
- Debug/Release build: **not applicable**.
- Full suite: **not run**; no compiled module or shared test infrastructure
  changed.
- Required documentation gate:
  - exact five-file scope;
  - all material claims mapped to official evidence;
  - product-ownership and cross-product boundaries proven;
  - each candidate independently classified;
  - complete field, normalization, privacy, recovery, and package matrices;
  - explicit TokenHub decision;
  - consistent `NO-GO` language;
  - zero-operation accounting;
  - Markdown and `git diff --check`;
  - privacy and generated-artifact scans;
  - independent Examiner review;
  - independent staged-index review.

## Generated and raw evidence policy

Only sanitized task metadata may exist under
`/private/tmp/uma-m3w-g1-evidence`. No provider response exists because no
source operation ran.

Never stage:

- provider responses or snapshots;
- logs, screenshots, process captures, or configuration backups;
- account, authentication, identity, task, prompt, or response data;
- private database/cache material;
- temporary probes;
- `.build`, `.swiftpm`, generated binaries, caches, or installers.

## Closure conditions

M3W-G1 may close with the documentation commit after:

1. all five scoped records agree on `NO-GO`;
2. privacy and generated-artifact scans pass;
3. the Independent Examiner accepts the admission decision;
4. issue M3W-012 is closed in the final staged content;
5. the cached diff contains only the five exact records;
6. independent staged-index review passes;
7. the local commit is created and the worktree/index are clean.

Open provider or owner conditions do not authorize implementation, reinstall,
login, Claude Code, M3W-G2, or another provider. They define the exact
prerequisites for a separately authorized future rerun.
