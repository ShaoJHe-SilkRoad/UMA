# UMA M6 Antigravity Privacy Contract

**Goals:** M6-G1, M6-SETUP-G1 and M6-G1R
**Date:** 2026-08-08
**Current state:** `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`

## 1. Boundary

UMA may consume only normalized current quota facts from one exact trusted
official Antigravity CLI executable after admission. The CLI owns
authentication. UMA must never receive or inspect provider authentication
material.

M6-G1R performed three bounded `/usage` executions. Two network-restricted
tool-sandbox executions returned no JSON. One approved ordinary-network
execution returned a JSON object and was reduced entirely in memory to field,
type, range and privacy classifications. No raw output or exact Founder value
was retained.

## 2. Process boundary

Every admission probe used:

- exact resolved `$HOME/.local/bin/agy` and a fixed argv array;
- no provider-command shell interpolation;
- closed stdin and no injected credential environment value;
- an empty owner-only task directory outside repositories;
- one owned child process group and one read in flight;
- stdout capped at 64 KiB and stderr capped at 16 KiB;
- a 15-second timeout with owned-child termination and reap;
- no raw stdout, stderr or provider payload persistence.

External process evidence used exact process identity/PID only. Broad argv,
environment, authentication, browser and process dumps are prohibited.

## 3. Observed quota ingress

The observed exact container is:

```text
command.data.groups[].buckets[]
```

An observed bucket contained:

```text
id: string
name: string
remaining_fraction: finite number in 0...1
reset_time: ISO-8601 datetime string
window: string
```

There was no explicit schema/version marker, relative reset duration,
disabled/unlimited state or freshness field.

Ingress order for any renewed admission remains:

```text
byte caps
→ UTF-8
→ one JSON object
→ exact CLI-version and container check
→ strict key/type/range validation
→ private-field discard
→ sanitized quota projection
```

## 4. Smallest candidate allowlist

Only these concepts may survive decoding:

- bounded validated group/bucket identity;
- bounded non-identifying label only after separate safety proof;
- `remaining_fraction`;
- per-bucket `reset_time`;
- bounded validated `window` only when required for independent pool identity;
- safe CLI version and local observation time.

`window`, group identity and bucket identity must use a bounded validated
grammar. Arbitrary provider text is never accepted merely because it occupies
an identity or label field.

Numeric rules:

- finite `remaining_fraction` must be within `0...1`;
- normalize exactly once with `remainingPercent = remaining_fraction × 100`;
- never infer used-versus-remaining from numeric range;
- never clamp;
- missing or wrong type is unavailable, not zero;
- independent buckets are never summed, split or deduplicated by display label.

Reset rules:

- parse a present `reset_time` only as ISO-8601;
- scope it to its own stable bucket identity;
- missing reset remains optional and unavailable;
- malformed present reset fails the affected bucket closed.

## 5. Rejected observed envelope fields

The successful JSON envelope also exposed fields that are unnecessary for quota
presentation. Discard before any UMA business logic:

- `conversation_id`, even when empty;
- `response` and every description/free-text field;
- `usage` token counters;
- `num_turns` and duration fields;
- status or command text not needed for strict quota decoding;
- all unknown future fields.

Always reject:

- email, account, organization, plan, billing, purchase and payment identity;
- login URL, browser state, cookies, tokens, credentials, Keychain/keyring and
  session material;
- conversation, message, prompt, response, task, tool and project content;
- cwd, workspace, source code, repository, branch and VCS state;
- raw stdout/stderr, complete JSON and raw-payload hashes.

If quota meaning cannot be separated from those classes, the source remains
`NO-GO`.

## 6. Authentication lifecycle

The successful read proved current provider-owned authentication without a
browser/login action. UMA and DEV accessed no authentication material.

No logout or expiry was induced. A future runtime must classify bounded
noninteractive outcomes such as:

```text
loginRequired
sessionExpired
browserLoginSideEffect
providerUnavailable
timeout
malformedOutput
unsupportedSchema
noValidQuota
```

A routine command that opens login fails closed. API keys, copied tokens, UMA
OAuth, Keychain/keyring reads, browser-cookie imports, private endpoints and
identity-dependent interpretation remain prohibited.

## 7. Evidence retention

Durable evidence may retain only:

- executable/provenance and safe version facts;
- exact safe command form and lifecycle bounds;
- JSON field names, types and range classifications;
- container, semantic and reset classifications;
- byte counts, execution counts and fixed outcomes;
- privacy-field categories and the final decision.

Never retain exact live quota values, reset timestamps, group names, bucket IDs,
bucket labels, window values, Credit balances, response text, counters, account
identity, authentication state material, screenshots or raw provider output.

The shared G1R packet was owner-only (`0700` directory, `0600` regular files),
contained sanitized classifications only, and was shared with the three named
examiners. It must be deleted after durable-record extraction and verification.

## 8. Admission limitation

Privacy reduction itself passed independent review. The final source decision
is still `NO-GO` because privacy safety cannot replace the mandatory proof of:

- detailed structural stability across successful ordinary reads;
- deterministic identity stability for multiple independent quota pools;
- exact live no-turn behavior.

Credits remain **`CREDITS DEFER`**. The only next task is **Founder source-direction decision**.
M6-G2 and production runtime work remain locked.
