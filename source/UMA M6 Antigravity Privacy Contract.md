# UMA M6 Antigravity Privacy Contract

**Goals:** M6-G1, M6-SETUP-G1, M6-G1R and M6-G1R2
**Date:** 2026-08-08
**Admission:** `GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`
**Credits:** `CREDITS DEFER`
**Only next task:** M6-G2

## 1. Source and command boundary

The admitted source is only the official local CLI at `$HOME/.local/bin/agy`,
version `1.1.11`, invoked without a shell as:

```text
$HOME/.local/bin/agy --output-format json -p /usage
```

Future runtime admission remains bound to the exact executable identity, CLI
version and `command.name == usage` container. API keys, copied tokens, UMA OAuth,
Keychain/keyring access, cookie/session import, private endpoints, browser
scraping, manual quota and inferred quota remain prohibited.

## 2. Execution boundary

Each read must use:

- exact argv with no interpolation;
- empty neutral task-owned cwd;
- closed stdin and no provider input;
- no injected credential environment;
- stdout cap 64 KiB and stderr cap 16 KiB;
- 15-second timeout;
- one owned child with complete termination and reap;
- no raw stdout, stderr or provider-payload persistence.

Do not enumerate broad process argv, environments or unrelated processes.
Routine browser/login activation fails closed rather than being adopted.

## 3. Strict quota allowlist

Only the following quota fields may be inspected and projected:

- `command.name`, required to equal `usage`;
- `command.data.groups[].buckets[]` container shape;
- bounded provider-owned `bucket.id` as the smallest stable pool identity;
- finite numeric `remaining_fraction` in `0...1`;
- optional ISO-8601 `reset_time`, scoped to the same bucket;
- bounded `window` and group fields only for schema validation, not identity;
- CLI version and local observation time.

`remainingPercent = remaining_fraction × 100` exactly once. Never clamp, infer
used-versus-remaining, convert unavailable to zero, aggregate pools, identify by
array position or use changing balance/reset values as identity. Duplicate
bucket identifiers across the entire response fail closed.

## 4. Sanitized operational evidence

M6-G1R2 corrects the prior over-sanitization by allowing only normalized facts:

| Inspected input | Durable projection |
|---|---|
| `num_turns` | `ZERO_TURN_CONFIRMED: YES/NO` only |
| `conversation_id` presence/emptiness | `CONVERSATION_CREATED: YES/NO` only |
| task/tool identifier keys | `TASK_IDENTIFIER_PRESENT: YES/NO` only |
| numeric provider usage counters | `PROVIDER_TOKEN_COUNTERS_ALL_ZERO: YES/NO` only |
| zero-turn plus zero-counter outcome | `MODEL_RESPONSE_GENERATED: YES/NO` only |

The accepted live classifications were zero turns, no conversation, no task
identifier, all counters zero and no model response for both successful reads.
Conversation identifiers, task identifiers and counter values must never be
retained. The `response` field must never be read, logged or projected.

## 5. Rejected data

Discard before UMA business logic:

- response, conversation, prompt, task, tool, message and project content;
- descriptions/free text, duration and raw provider status;
- exact token-counter values and all unknown fields;
- email, account, organization, plan, billing, purchase and payment identity;
- login URLs, browser state, cookies, tokens, credentials, Keychain/keyring and
  session material;
- cwd, workspace, source code, repository, branch and VCS state;
- raw stdout/stderr, complete JSON, raw hashes and screenshots.

If quota meaning or stable pool identity cannot be separated from these classes,
the read fails closed.

## 6. Durable evidence limits

Durable records may contain only:

- safe executable/version/provenance classifications;
- exact safe command form and execution bounds;
- schema field names/types and counts;
- `POOL_A_IDENTITY_STABLE`-style booleans, never live identifiers;
- semantic/range/reset classifications;
- normalized zero-turn/no-work booleans;
- byte counts, operation counts, outcome classes and final decision.

Never persist exact live quota values, reset timestamps, group names, bucket IDs,
bucket labels, window values, Credits, provider response text, account identity
or authentication material.

## 7. Temporary data and teardown

Task evidence must be owner-only and exact-path scoped. Provider temporary
regular files may be removed only after verifying exact path, ownership,
non-symlink identity and no open handle, without reading their contents. The
neutral cwd must remain empty. All task-owned evidence/probe/build paths must be
deleted after durable extraction and verification. No unrelated temp path may be
inspected or removed.

The M6-G1R2 run left no `agy` child, browser side effect, neutral-cwd file or
provider temporary file after teardown. The first-read local harness failure and
its exact repair are recorded in the QA ledger.

## 8. Consumption statement

The durable statement is limited to:

> No attributable quota consumption observed within provider granularity,
> consistent with the official read-only command contract.

Do not replace it with a mathematical zero-spend claim.

## 9. Admission boundary

The privacy contract and all three repaired evidence gates support:

`GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`

Credits remain **`CREDITS DEFER`**. No production runtime was implemented.
**M6-G2 is the only next task and requires its own execution scope.**
