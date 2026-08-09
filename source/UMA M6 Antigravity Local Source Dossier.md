# UMA M6 Antigravity Local Source Dossier

**Goals:** M6-G1, M6-SETUP-G1, M6-G1R and M6-G1R2
**Date:** 2026-08-08
**Current decision:** `GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`
**Credits:** `CREDITS DEFER`
**Only next task:** M6-G2

## 1. Accepted lineage and unchanged baseline

M6-G1 established the official CLI source class and returned `SETUP REQUIRED`.
M6-SETUP-G1 installed and verified the official manifest-pinned CLI. M6-G1R
proved one current structured quota response but correctly returned
`NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`: repeated structure, stable quota
identity and exact no-turn evidence were still missing.

M6-G1R2 began from:

```text
branch: codex/uma-m6-antigravity
HEAD: d128018bf27896d34e8bea0c158a2b4a6f77e925
tree: 9b03062e1d8bed3f3b1c89f5c1f404bdfe231eee
worktree/index: clean/empty
```

The installed candidate remained the regular, non-symlink arm64 executable at
`$HOME/.local/bin/agy`, version `1.1.11`, SHA-256
`198ff7c3f6d173daa510b0814aa70c6ce14c94035bcd4707a3c0e79fa38a7bc3`.
Accepted setup trust limitations remain unchanged. M5 frozen records and the
Codex, Claude and WorkBuddy mechanisms were unchanged.

## 2. Exact read boundary

Every M6-G1R2 provider invocation used the already proven argument vector:

```text
$HOME/.local/bin/agy --output-format json -p /usage
```

Execution used the ordinary local class that had previously produced structured
output, an empty owner-only task directory, closed stdin, no shell, no injected
credentials, a 64 KiB stdout cap, a 16 KiB stderr cap, a 15-second timeout, one
owned child and complete reap. Raw stdout, stderr and provider JSON existed only
in memory long enough to produce the allowlisted classifications below.

## 3. M6-G1R2 read accounting

| Execution | Outcome | Durable classification |
|---|---|---|
| 1 | Provider process completed; the local evidence harness then hit a process-group permission error during teardown | Conservatively counted as an unclassified live execution; no raw output or exact value persisted |
| 2 | Exit 0; one JSON object; 1,141 stdout bytes; empty stderr | Successful ordinary structured read |
| 3 | Exit 0; one JSON object; 1,141 stdout bytes; empty stderr | Successful ordinary structured read |

Total M6-G1R2 `/usage` executions were **3/3**. Automatic retries were **0**.
`/credits` reads, provider prompts, provider tasks and intentional provider work
were all **0**.

The first execution exposed a local evidence-harness teardown defect, not a
provider failure. The harness was repaired to reap the completed child first and
to use bounded direct-child termination only when process-group signaling is
unavailable. The two remaining authorized reads were deliberate required
observations, not retries.

## 4. Repeated structured-output stability

Both successful ordinary reads had the same required schema:

```text
root: object
command: object
command.name: string equal to usage
command.data: object
command.data.groups: array
groups[]: { name: string, description: string, buckets: array }
buckets[]: {
  id: string,
  name: string,
  remaining_fraction: number,
  reset_time: string,
  window: string
}
```

Both observations exposed two groups with one bucket each. Field names, field
types, group count, bucket counts, remaining semantics, reset semantics and
private-envelope field classes were structurally reproducible. No schema/version
marker or freshness field was observed; the decoder boundary is therefore pinned
to CLI `1.1.11` plus the exact command/container/type contract and must fail
closed on mismatch.

## 5. Provider-owned bucket identity

The smallest stable provider-owned quota-pool identity is `bucket.id`.

- Every publishable pool had a nonempty bounded provider bucket identifier.
- `POOL_A_IDENTITY_STABLE: YES`.
- `POOL_B_IDENTITY_STABLE: YES`.
- Matching was independent of group/array position.
- No remaining value, reset time, display label, model assumption or local
  sequence number participated in identity.
- One reset observation changed while both bucket identities remained stable,
  demonstrating that reset/value fields are not identity inputs.
- Duplicate bucket identifiers across the complete response must fail closed;
  they must never be merged or disambiguated locally.

Exact live bucket identifiers, labels, window values, balances and reset times
were discarded and are not recorded here.

## 6. Quota semantics

`remaining_fraction` is an explicit provider remaining fraction. Admission is:

```text
finite number in 0...1
→ remainingPercent = remaining_fraction × 100 exactly once
```

There is no clamp, used/remaining inference, unavailable-to-zero conversion or
cross-pool aggregation. `reset_time` is an optional bucket-scoped absolute
ISO-8601 time. A malformed present reset fails that bucket closed; absence remains
unavailable. Each independent bucket remains independent.

## 7. Zero-turn and no-provider-work proof

Each successful result was reduced to these booleans before durable retention:

```text
ZERO_TURN_CONFIRMED: YES
CONVERSATION_CREATED: NO
TASK_IDENTIFIER_PRESENT: NO
PROVIDER_TOKEN_COUNTERS_ALL_ZERO: YES
MODEL_RESPONSE_GENERATED: NO
```

The zero-turn classification came from `num_turns == 0`; conversation creation
from an empty/absent normalized conversation identifier; task creation from the
absence of task/tool identifiers; and token activity from all provider token
counters being zero. Response content was never retained or interpreted.

No attributable quota decrement was observed across the successful reads. The
admitted conclusion is deliberately bounded:

> No attributable quota consumption observed within provider granularity,
> consistent with the official read-only command contract.

This does not claim mathematical zero spend beyond provider granularity.

## 8. Authentication, browser and lifecycle

Provider-owned authentication was already active. The read succeeded without
DEV accessing credentials, Keychain/keyring data, tokens, cookies, sessions,
browser profiles or account identity. Safari process count was one before and
after the successful-read sequence; no login/browser side effect was observed.

The exact owned CLI child count was one per read. No `agy` child remained after
completion. The neutral cwd stayed empty. Two task-owned provider temporary
regular files were removed by exact path without inspecting contents; the
provider temporary directory was empty after teardown. No unrelated process argv
or environment was enumerated.

## 9. Privacy projection

Only these concepts may cross a future decoder boundary:

- validated provider `bucket.id`;
- finite `remaining_fraction`, normalized once;
- optional bucket-scoped `reset_time`;
- a separately validated safe display label if later required;
- CLI version and local observation time;
- normalized zero-turn/no-provider-work booleans.

Conversation/response text, descriptions, token-counter values, duration,
status, raw JSON, account identity, credentials, workspace data and all unknown
fields are discarded. No exact live balance, reset or identity value was made
durable.

## 10. Decision

M6-G1R2 closes all three mandatory M6-G1R gaps:

1. repeated ordinary structured-output stability — PASS;
2. deterministic provider-owned pool identity — PASS;
3. durable sanitized zero-turn/no-provider-work evidence — PASS.

The official Antigravity CLI quota source is admitted:

`GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`

Credits remain **`CREDITS DEFER`**. No Credits source was inspected. No
production connector, scheduler, UI, package or installed application was
changed. **M6-G2 is the only next task and was not begun.**
