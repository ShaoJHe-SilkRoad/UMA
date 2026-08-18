# UMA M5RMX Claude Source Decision

**Version:** 1.0

**Date:** 2026-08-17

**Goal:** M5RMX-G1

## Verdict

`PASS — CURRENT SAFARI BROWSER SYNC PRESERVED`

No official superior source candidate currently passes the replacement gates.
The accepted Safari Browser Sync path remains the sole Claude account-capacity
source. This is a preservation decision, not a production extension rewrite.

## Credential-boundary decision

Provider-owned credential use is permitted inside Claude and Safari. Credential
crossing into UMA is forbidden. UMA receives only the closed, versioned,
sanitized usage observation defined by the M5RMX privacy contract.

The current source requires no API key, copied token, cookie export, browser
profile, Keychain read, embedded login, private endpoint, account mutation, or
provider task.

## Source-promotion decision

| Candidate | Decision | Reason |
|---|---|---|
| Official local service / IPC | `NOT ADMITTED` | No current official bounded account-capacity contract is proven; strict verification of the current Claude.app fails |
| Official hook/event/status | `HISTORICAL / RETIRED` | Documented five-hour/seven-day quota fields appear only after the first API response, timer rerun freshness is unproven, and raw stdin carries broader sensitive context |
| Official read-only CLI/local metadata | `NOT ADMITTED` | No current documented quota command with stable account-window schema is proven; strict verification of installed CLI 2.1.220 fails |
| Safari Browser Sync | `ACCEPTED CURRENT` | Current account truth, explicit semantics, provider-owned auth, bounded sanitized output, automatic refresh, and accepted shared presentation are established |

Browser Sync must not be removed until another official route proves live
same-time parity, automatic no-work refresh, credential opacity, safe rollback,
and every other promotion gate.

## Account-window decision

- Five-hour: `ADMITTED`, provider-rendered used percent converted once to
  remaining.
- Weekly/all-model: `ADMITTED`, provider-rendered used percent converted once
  to remaining.
- Model-specific weekly: `OPTIONAL`, only with one explicit stable model-family
  scope.
- Missing reset: `UNAVAILABLE`, never fabricated.
- Missing or malformed window: `UNAVAILABLE`, never zero.
- Continuation, extra usage, usage credits, billing balance, or purchase state:
  `NOT ADMITTED`.

Official usage-credit continuation means `0%` included-plan remaining does not
prove all Claude work must stop. The included window can be exhausted while
overall work availability remains `UNKNOWN`; UMA does not infer continuation or
unavailability.

The documented status-line quota fields cover Pro and Max. Team, Enterprise,
and unknown account modes are `NOT LIVE OR CONTRACT QUALIFIED` and are not
inferred from Pro/Max evidence.

Current strict verification of both `$HOME/.local/bin/claude`
(installed 2.1.220) and `/Applications/Claude.app` returns `invalid signature
(code or signature have been modified)` for arm64. Local trust is therefore
unadmitted. This does not change the accepted Safari Browser Sync decision.

The Main Panel and Desktop Assistant continue to consume the same normalized
snapshot and freshness state. Local Claude activity and API-equivalent cost
remain a separate this-Mac estimate channel.

## Live and mutation record

This implementer pass performed:

```text
Sanitized authenticated Claude Usage observations: 0
Claude prompts/tasks: 0
Intentional provider spend: 0
Account or usage-credit mutations: 0
Production runtime/extension changes: 0
```

Any coordinated G1 live observation is classified separately by the task owner
and must remain within the eight-observation, 45-minute cap without retaining
exact private values.

## Delivery boundary

M5RMX-G1 delivers only current source/privacy/decision records, focused
deterministic tests, and the QA ledger. Production Safari completion,
entitlement/signing/package work, and live supportability belong to
`M5RMX-SAFARI-G1`.

After accepted G1 PASS, the sole next task is `M5RMX-SAFARI-G1`. It does not
start automatically.
