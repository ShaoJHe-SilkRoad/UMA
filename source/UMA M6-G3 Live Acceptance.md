# UMA M6-G3 Live Acceptance

**Goal:** M6-G3 — Live Antigravity quota and main-panel acceptance
**Date:** 2026-08-09
**Starting revision:** `532c705c3753154a23900b84c540e5e0329c4ae5`
**Decision:** `PASS — GOOGLE ANTIGRAVITY LIVE FOURTH PROVIDER ACCEPTED`
**Credits:** `CREDITS DEFER`
**Only next task:** M6DBG-G1 — Four-provider main-app debugging

## Accepted production path

```text
official current-user $HOME/.local/bin/agy
→ --output-format json -p /usage
→ AntigravityReadOnlyCLIClient
→ AntigravityQuotaDecoder
→ GoogleAntigravityUsageConnector
→ AgentConnectorRegistry / UsageStore
→ SharedUsagePresentationPolicy
→ main panel only
```

The admitted executable remained CLI `1.1.11`, arm64, current-user owned,
executable and exact-checksum bound. The final live gate used no shell, a neutral
owner-only working directory, closed stdin, bounded stdout/stderr, a 15-second
soft timeout, a 20-second hard ceiling and direct-child termination/reaping.
No provider output or stderr content was logged or retained.

## Live accounting

| Operation | Cap | Result |
|---|---:|---:|
| Read-only `/usage` operations | 6 | 6 |
| Final successful normalized observations | — | 2 |
| `/credits` operations | 0 | 0 |
| Provider prompts/tasks/conversations | 0 | 0 |
| Intentional provider work/spend | 0 | 0 |

Four initial operations identified and narrowed a fail-closed live decoder
defect without retaining provider content. After the bounded repair, the fifth
operation established the current observation and the sixth was the normal
five-minute scheduled refresh. No retry remained and operation seven is outside
the authorization.

## Sanitized acceptance

- source and strict decoder: PASS;
- multiple independent quota buckets: PASS;
- global stable identity by `bucket.id`: PASS;
- `remaining_fraction × 100` exactly once: PASS;
- bucket-scoped reset valid or unavailable: PASS;
- provider-to-connector-to-card semantic parity: PASS;
- collapsed/expanded shared-card data contract: PASS;
- exact main-panel order `Codex → Claude Code → WorkBuddy → Google Antigravity`: PASS;
- Antigravity hidden from Desktop Assistant: PASS;
- current valid observation required before visibility: PASS;
- one scheduler and one process maximum: PASS;
- normal five-minute completion-relative refresh: PASS;
- three-minute production floor unchanged: PASS;
- manual request coalesced with the scheduled read: PASS;
- no catch-up burst, overlap or retry storm: PASS;
- disconnect/stop cancelled scheduler and cleared normalized state: PASS;
- no residual provider child: PASS.

Provider parity was established deterministically from the official structured
provider-owned `/usage` result through the same production normalization and
shared card model. No exact Founder value was recorded. The displayed integer
percentage uses the existing deterministic rounded presentation of the exact
normalized remaining percentage; source semantics remain unrounded internally.

## No-provider-work and authentication result

The current authenticated provider-owned session completed routine reads with
zero prompt, task or conversation input. The admitted operational envelope
continued to require zero turns, empty conversation identity and zero usage
counters before any quota is published. No attributable quota consumption was
observed within provider granularity, consistent with the admitted official
read-only CLI contract.

No login-required state or browser authentication appeared during the successful
routine refresh. Authentication, schema and identity uncertainty continue to
fail closed. Login-required, unsupported schema, timeout, unavailable process,
malformed output and no-valid-quota behavior remain covered by deterministic
connector/decoder tests; missing data is never converted to zero.

## Existing-provider and privacy result

The G3 implementation does not change the Codex, Claude or WorkBuddy source,
credential, scheduler, refresh or presentation mechanisms. The accepted M5
frozen set remains unchanged. Antigravity remains main-panel-only and uses no
Keychain, browser profile, cookie, token, private endpoint, API key, manual
quota, raw payload persistence or `/credits` route.

The protected Desktop application was not replaced or launched as G3 evidence.
The final package is local verification evidence only and is not a release,
deployment or installation artifact.

## Final verification before delivery

- focused decoder, client, connector and G3 acceptance suites: 32/32 PASS;
- complete fresh suite: 537 UI plus 18 bridge tests, 555/555 PASS;
- Debug, Release and strict-concurrency Release builds: PASS;
- rebuilt working-tree G3 preflight build `202608090102`: PASS;
- arm64, strict deep ad-hoc signature, system dependency and package-content
  audits: PASS;
- accepted 52-file M5 Git-blob manifest: unchanged;
- protected Desktop executable checksum: unchanged;
- privacy, secret and identity scans: PASS;
- `git diff --check`: PASS;
- residual provider/task-owned process count: zero.

## Delivery lock

Final commit/package identifiers and clean Git state are reported by the
commit-exact delivery audit. M6DBG-G1 must not start automatically.
