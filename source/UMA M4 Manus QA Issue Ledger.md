# UMA M4 Manus QA Issue Ledger

Status: M4-G2 implementation ledger
Date: 2026-07-28

| ID | First evidence | Root cause / risk | Repair or decision | Verification | Final status |
|---|---|---|---|---|---|
| M4-G1-001 | Official v2 endpoint and OpenAPI schema expose `total_credits` plus optional component/reset fields | Components can diverge from the actual wallet under membership and team-overflow rules | Make `total_credits` the sole primary balance; classify every component as detail/quota/reset only | Synthetic payload with `total_credits = 42` and non-reconciling components decodes to 42 | CLOSED |
| M4-G1-002 | OpenAPI `AvailableCredits` schema has no `required` array | Generated/default decoding could accept a partial response without an authoritative balance | Require `ok == true`, `data`, and non-negative Int32 `total_credits`; fail missing/wrong type/negative/overflow closed | Focused missing-primary, negative, float, string, and overflow cases | CLOSED |
| M4-G1-003 | API key is documented as granting full account access and shown once | Plaintext preferences, logs, fixtures, or broad Keychain access would create a high-impact secret leak | Device-bound generic-password item, data-protection Keychain, no sync/access group, minimal transient lifetime, redacted diagnostics | Keychain query-contract and redaction tests; no real `SecItem` call | CLOSED FOR DESIGN; LIVE PROOF DEFERRED |
| M4-G1-004 | Endpoint requires `x-manus-api-key` and does not accept OAuth | Redirects or a broad client could forward the key or call unrelated endpoints | Exact HTTPS host/path/method allowlist, no query/body, ephemeral session, reject redirects | Focused exact-request and policy assertions | CLOSED |
| M4-G1-005 | Official rate-limit page omits `usage.availableCredits`; provider timeout/body-size/redirect policy is undocumented | Treating another endpoint's 600/min table row as authoritative would be unsafe | Local conservative policy: one in flight, 60 seconds after completion, 15/20 second timeouts, 16 KiB cap, no immediate retry | Deterministic transport/cadence policy tests | CLOSED WITH DOCUMENTED UNCERTAINTY |
| M4-G1-006 | Current UMA source admission enums model local structured and authenticated-account-web sources, not an official remote usage API | Reusing either category would misstate provenance and eligibility | Added `officialRemoteUsageAPI`, `currentOfficialRemoteRead`, and explicit Keychain-credential authentication classification | Focused admission and shared-presentation tests | CLOSED IN M4-G2 |
| M4-G1-007 | Current account Credit runtime details are WorkBuddy-specific | Manus detail fields would either be lost or create more provider special-casing | Added provider-neutral Credit component/reset details while keeping `CreditBalance` as the authoritative exact balance | Non-reconciling component fixture and presentation tests | CLOSED IN M4-G2 |
| M4-G1-008 | No real key or authenticated request is allowed in M4-G1 | Documentation and fixtures cannot prove the Founder's actual balance or live key lifecycle | Return CONDITIONAL GO and define the later Human-controlled one-read comparison | Admission decision and live-validation plan | DEFERRED TO HUMAN LIVE GATE |
| M4-G1-009 | Optional unauthenticated no-key probe could have added an HTTP error-shape observation | Local execution approval gate rejected the optional request | Do not retry or work around the gate; rely on official error envelope and synthetic fixtures | No network request occurred; no credential existed | CLOSED WITHOUT PROBE |
| M4-G1-010 | M4-B0 official skill install failed once because `npx` was unavailable | Retrying or installing a toolchain violates the accepted B0 boundary | Preserve the failure as nonblocking; use official docs directly | No Node/npm/npx/Homebrew installation or retry | CLOSED |
| M4-G1-011 | `next_refresh_time` is documented as Unix seconds and `0` when absent | Milliseconds/seconds confusion could produce a wildly incorrect reset date | Accept documented zero or a bounded plausible Unix-seconds range; reject negative, implausibly small, or millisecond-scale values | Focused zero, seconds, and milliseconds cases | CLOSED |
| M4-G2-001 | The first production implementation had no official-remote source seam | A Manus snapshot could be misclassified as local or authenticated web data | Added official remote source, authentication, read-contract, provenance, eligibility, and presentation states | Current-read admission accepts Manus only after a fresh successful read and hides it immediately on failure | CLOSED |
| M4-G2-002 | The first focused test run could not load Swift Testing macros/runtime with the installed default toolchain path | Test infrastructure, not product behavior, prevented the focused suite from executing | Used the installed macOS 26.5 SDK, loaded the Command Line Tools Testing macro plugin, and linked only task-owned Testing runtime artifacts under `/private/tmp` | M4-G2 focused suite executes using the isolated build tree | CLOSED — TOOLCHAIN WORKAROUND ONLY |
| M4-G2-003 | The isolated test HOME could not exercise a real Security-framework Keychain item | Treating the sandbox failure as a product failure would not prove the requested lifecycle | Kept unit tests on the injected fake as required, then ran one task-owned synthetic generic-password add/read/replace/delete lifecycle in the normal user Keychain context; production queries remain data-protection, device-only, non-synchronizing, and access-group-free | Synthetic lifecycle PASS; unique service/account deleted and deletion verified | CLOSED |
| M4-G2-004 | Concurrent refresh triggers could multiply provider reads | A timer and manual action could exceed the conservative endpoint budget | Connector owns one in-flight read and coalesces overlap into at most one follow-up; scheduler owns one timer and clamps cadence to at least 60 seconds after completion | Deterministic overlapping-refresh and scheduler diagnostics tests | CLOSED |
| M4-G2-005 | A failed refresh could accidentally retain a prior remote value | A stale Manus balance would violate current-read admission | Every Keychain, transport, HTTP, schema, and authentication failure replaces the snapshot with unavailable data and withdraws surface admission | Success-then-network-failure regression test | CLOSED |
| M4-G2-006 | Redirects, cookies, caches, retries, or broad endpoints could leak the full-account API key | The credential has broader account authority than the admitted balance read | Ephemeral no-cookie/no-cache/no-credential-storage session; exact HTTPS route; redirect rejection; 15/20-second timeouts; 16 KiB cap; no retries; redacted diagnostics | Request, redirect, error, cancellation, response-size, and source allowlist tests | CLOSED |
| M4-G2-007 | A saved credential draft or response could enter preferences, logs, fixtures, Git, or the package | This would cross the locked secret boundary | SecureField draft clears immediately after submission; only Auto Refresh boolean is persisted; no raw body or provider message is retained; package audit excludes source/tests/fixtures/logs and synthetic values | Settings persistence assertion, source privacy scan, binary strings audit, and package-content audit | CLOSED |
| M4-G2-008 | Manus Settings initially used direct refresh for Sync Now | A connector with no current surface-admission set could read successfully without establishing the canonical provider set | Sync Now now performs the shared bounded eligibility scan, so the registry and both consumers share one current admission | Settings connect and admission tests | CLOSED |
| M4-G2-009 | Independent review found disconnect and replacement paths could misreport Keychain failure or leave a rejected replacement installed | Credential mutation was treated as an irreversible happy path | Surface deletion failure, retain configured state, and restore the previous credential after failed verification | Focused deletion-failure and replacement-rollback tests | CLOSED |
| M4-G2-010 | Independent review found the initial item-match query omitted the accepted accessibility attribute | A colliding service/account item could broaden the match beyond the locked contract | Use the full generic-password, service, account, accessibility, non-sync, data-protection query for every operation | Typed production query-contract assertions plus task-owned lifecycle | CLOSED |
| M4-G2-011 | Toggling Auto Refresh after authentication failure could clear suspension without a credential change | Scheduler enablement and credential recovery shared one state transition | Keep authentication suspension across OFF/ON and clear it only after an explicit credential change | Deterministic suspension/toggle/resume test | CLOSED |
| M4-G2-012 | A monitoring-disabled official-remote provider could keep its timer active while hidden | Remote failure recovery and explicit exclusion used the same stop policy | Preserve the timer only for non-excluded transient failure; explicitly excluded providers stop connector and timer | Monitoring-exclusion scheduler test | CLOSED |
| M4-G2-013 | The first exact package allowlist omitted the ad-hoc signature resource | A valid signed bundle would fail its own exact-manifest audit | Include only `_CodeSignature/CodeResources` in addition to the four product files | Package helper contract and final commit-exact package audit | CLOSED |
| M4-G2-014 | A full-suite run hit one pre-existing timing wait under concurrent load | A transient regression-harness timeout could be mistaken for a Manus defect | Reran the exact failed test alone, then reran the complete suite serially after all repairs | Isolated test PASS; final full suite 351/351 PASS | CLOSED — NONPRODUCT FLAKE |
| M4-G2-015 | Final independent review found a failed remote read used the local-provider withdrawal path | Stopping the remote connector would also stop scheduled recovery and clear authentication suspension | Withdraw failed remote data immediately without stopping its scheduler; explicit monitoring exclusion still stops the connector and timer | Network-failure recovery-timer and authentication-suspension regressions | CLOSED |
| M4-G2-016 | Final independent review found an unsaved SecureField draft could survive Settings navigation and the presented source label was English-only | A retained draft broadens credential lifetime, and an untranslated source label breaks the required Chinese surface | Clear the draft on back, close, and Manus-section disappearance; localize API provenance through `AppLanguage` | Draft-discard/no-mutation test and English/Chinese presentation assertions | CLOSED |
| M4-G2-017 | The first commit-exact package build reached signing but the helper required the short header literal to appear in optimizer-visible binary strings | Swift can encode a short constant without a printable C string, so the check produced a false negative after a correct Release build | Verify the exact header declaration in the archived commit source while retaining binary checks for the endpoint, Keychain service, forbidden routes, dependencies, and package manifest | Focused package-helper test plus final commit-exact package audit | CLOSED |

## Verification matrix

Required M4-G2 checks:

- official documentation inventory: covered by Source Dossier;
- exact current host/path/method/auth: focused test;
- schema fixture decode: focused test;
- missing primary, negative, wrong-type, overflow, and malformed data:
  focused test;
- optional fields and non-reconciling components: focused test;
- redacted request diagnostic: focused test;
- redirect, timeout, body-size, one-in-flight, and cadence contract:
  focused test;
- no-secret Keychain query design: typed contract test plus one unique
  synthetic Security-framework lifecycle;
- affected Credit and Assistant regressions: 67 tests across 5 suites PASS;
- full suite: 351 tests across 43 suites PASS;
- Debug, Release, and strict-concurrency Release builds: PASS;
- final package, staged-index review, and clean final state are recorded by
  the completion report.

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

None of these risks require broadening M4-G2. They remain explicit gates for
later Human live validation.

## Final observed evidence

- focused M4-G2 suite: 33 tests across 4 suites PASS;
- affected Codex/WorkBuddy/Credit/Assistant regressions:
  67 tests across 5 suites PASS;
- full suite: 351 tests across 43 suites PASS;
- Debug, Release, and strict-concurrency Release builds: PASS;
- `git diff --check`: PASS before staging.

The installed default macOS 27 SDK expected a `SwiftUIMacros` plugin that the
current Command Line Tools installation did not provide. Verification used the
installed macOS 26.5 SDK with task-owned SwiftPM/module caches under
`/private/tmp`; no project dependency, package manifest, toolchain, or source
configuration was changed. The Swift Testing runtime supplied by the Command
Line Tools also required task-owned framework/dylib links in the temporary
build output for execution. Those links exist only under `/private/tmp` and
are not delivery artifacts.
