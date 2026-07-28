# UMA M4 Manus QA Issue Ledger

Status: M4-G1 final ledger
Date: 2026-07-28

| ID | First evidence | Root cause / risk | Repair or decision | Verification | Final status |
|---|---|---|---|---|---|
| M4-G1-001 | Official v2 endpoint and OpenAPI schema expose `total_credits` plus optional component/reset fields | Components can diverge from the actual wallet under membership and team-overflow rules | Make `total_credits` the sole primary balance; classify every component as detail/quota/reset only | Synthetic payload with `total_credits = 42` and non-reconciling components decodes to 42 | CLOSED |
| M4-G1-002 | OpenAPI `AvailableCredits` schema has no `required` array | Generated/default decoding could accept a partial response without an authoritative balance | Require `ok == true`, `data`, and non-negative Int32 `total_credits`; fail missing/wrong type/negative/overflow closed | Focused missing-primary, negative, float, string, and overflow cases | CLOSED |
| M4-G1-003 | API key is documented as granting full account access and shown once | Plaintext preferences, logs, fixtures, or broad Keychain access would create a high-impact secret leak | Device-bound generic-password item, data-protection Keychain, no sync/access group, minimal transient lifetime, redacted diagnostics | Keychain query-contract and redaction tests; no real `SecItem` call | CLOSED FOR DESIGN; LIVE PROOF DEFERRED |
| M4-G1-004 | Endpoint requires `x-manus-api-key` and does not accept OAuth | Redirects or a broad client could forward the key or call unrelated endpoints | Exact HTTPS host/path/method allowlist, no query/body, ephemeral session, reject redirects | Focused exact-request and policy assertions | CLOSED |
| M4-G1-005 | Official rate-limit page omits `usage.availableCredits`; provider timeout/body-size/redirect policy is undocumented | Treating another endpoint's 600/min table row as authoritative would be unsafe | Local conservative policy: one in flight, 60 seconds after completion, 15/20 second timeouts, 16 KiB cap, no immediate retry | Deterministic transport/cadence policy tests | CLOSED WITH DOCUMENTED UNCERTAINTY |
| M4-G1-006 | Current UMA source admission enums model local structured and authenticated-account-web sources, not an official remote usage API | Reusing either category would misstate provenance and eligibility | Record required M4-G2 seams: `officialRemoteUsageAPI`, `currentOfficialRemoteRead`, and provider-neutral Credit details | Connector architecture review against current runtime | OPEN FOR M4-G2 |
| M4-G1-007 | Current account Credit runtime details are WorkBuddy-specific | Manus detail fields would either be lost or create more provider special-casing | Require provider-neutral component/reset detail snapshot in M4-G2; keep `CreditBalance` as exact primary model | Architecture review of `AgentAvailability` and usage runtime | OPEN FOR M4-G2 |
| M4-G1-008 | No real key or authenticated request is allowed in M4-G1 | Documentation and fixtures cannot prove the Founder's actual balance or live key lifecycle | Return CONDITIONAL GO and define the later Human-controlled one-read comparison | Admission decision and live-validation plan | DEFERRED TO HUMAN LIVE GATE |
| M4-G1-009 | Optional unauthenticated no-key probe could have added an HTTP error-shape observation | Local execution approval gate rejected the optional request | Do not retry or work around the gate; rely on official error envelope and synthetic fixtures | No network request occurred; no credential existed | CLOSED WITHOUT PROBE |
| M4-G1-010 | M4-B0 official skill install failed once because `npx` was unavailable | Retrying or installing a toolchain violates the accepted B0 boundary | Preserve the failure as nonblocking; use official docs directly | No Node/npm/npx/Homebrew installation or retry | CLOSED |
| M4-G1-011 | `next_refresh_time` is documented as Unix seconds and `0` when absent | Milliseconds/seconds confusion could produce a wildly incorrect reset date | Accept documented zero or a bounded plausible Unix-seconds range; reject negative, implausibly small, or millisecond-scale values | Focused zero, seconds, and milliseconds cases | CLOSED |

## Verification matrix

Required M4-G1 checks:

- official documentation inventory: covered by Source Dossier;
- exact current host/path/method/auth: focused test;
- schema fixture decode: focused test;
- missing primary, negative, wrong-type, overflow, and malformed data:
  focused test;
- optional fields and non-reconciling components: focused test;
- redacted request diagnostic: focused test;
- redirect, timeout, body-size, one-in-flight, and cadence contract:
  focused test;
- no-secret Keychain query design: focused test with no Keychain operation;
- affected Credit and Assistant regression suites: required before commit;
- full suite and package build: required before commit;
- `git diff --check`, staged-index review, clean final state: required before
  completion.

## Residual risks

1. A live Manus account may expose a permission or schema behavior not
   represented in the public docs.
2. The endpoint-specific rate limit remains unpublished.
3. Personal versus team balance semantics can only be confirmed with the
   Human's chosen key scope.
4. Swift strings cannot be guaranteed to be cryptographically zeroized;
   implementation must minimize lifetime and copies.
5. Locked-screen reads are intentionally unavailable under the stronger
   Keychain accessibility class.

None of these risks require broadening M4-G1. They are explicit gates for
M4-G2 implementation and later Human live validation.

## Final observed evidence

- focused M4-G1 feasibility suite: 10 tests PASS;
- affected Credit/Assistant regressions: 25 tests across 3 suites PASS;
- full suite: 318 tests across 39 suites PASS;
- Release `CodexUsageMonitor` feasibility build: PASS, arm64;
- `git diff --check`: PASS before staging.

The installed default macOS 27 SDK expected a `SwiftUIMacros` plugin that the
current Command Line Tools installation did not provide. Verification used the
installed macOS 26.5 SDK with task-owned SwiftPM/module caches under
`/private/tmp`; no project dependency, package manifest, toolchain, or source
configuration was changed. The Swift Testing runtime supplied by the Command
Line Tools also required task-owned framework/dylib links in the temporary
build output for execution. Those links exist only under `/private/tmp` and
are not delivery artifacts.
