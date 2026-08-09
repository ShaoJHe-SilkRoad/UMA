# UMA M6 Antigravity Local Source Dossier

**Goals:** M6-G1, M6-SETUP-G1 and M6-G1R
**Date:** 2026-08-08
**G1R starting commit:** `6b4a90924705c94db37d4ab6858d56ab084cdbfe`
**G1R starting tree:** `e7123b7760f1bafeaaaeb6dc487ec53414c5b133`
**Current decision:** `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`

## 1. Executive finding

The official Google Antigravity CLI is installed and the source class remains
technically promising. One bounded ordinary-network execution returned a
current structured quota object with explicit remaining semantics, per-bucket
absolute resets, multiple independent groups, provider-owned authentication,
and no browser/login action.

The source is not admitted in M6-G1R. All three authorized executions are
consumed, but only one retained detailed schema classification. Exact safe
bucket identity was not retained across two successful samples, and exact live
`num_turns == 0` was not preserved. The mandatory repeatability, identity, and
live no-turn gates therefore remain unproven.

Final result:

```text
NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE
```

## 2. Repository and exclusion-zone baseline

| Property | Observation |
|---|---|
| Workspace | `/Users/juliushe/Developer/UMA-M6-Antigravity` |
| Branch | `codex/uma-m6-antigravity` |
| Starting HEAD | `6b4a90924705c94db37d4ab6858d56ab084cdbfe` |
| Starting tree | `e7123b7760f1bafeaaaeb6dc487ec53414c5b133` |
| Starting worktree | Clean |
| Starting index | Empty |
| Accepted setup commit | Present |
| M5/shared runtime | Unchanged from accepted setup baseline |

M6-G1R modifies admission tests and four existing M6 records only. It does not
modify product source, `Package.swift`, scripts, `BrowserExtension`, M5 records,
M5 tests, or existing provider mechanisms.

## 3. Installed executable

| Required fact | Current observation |
|---|---|
| Exact path | `$HOME/.local/bin/agy` |
| Resolved path | Same; regular file |
| Symlink chain | None |
| Version/build | `1.1.11`; no separate build reported |
| Type / architecture | Mach-O 64-bit executable, arm64 |
| Executable SHA-256 | `198ff7c3f6d173daa510b0814aa70c6ce14c94035bcd4707a3c0e79fa38a7bc3` |
| Embedded identifier / Team ID | `cli` / `EQHXZ8M8AV` |
| Quarantine / provenance | Quarantine absent; provenance present |
| Signature / Gatekeeper | Reliable local PASS unavailable under the previously accepted trust-service limitation |

The official installer, manifest version, archive checksum and installed hash
remain the admitted provenance evidence. M6-G1R neither reinstalls nor updates
the executable.

## 4. Exact command and execution boundary

Installed help reconfirmed noninteractive print mode, `-p`, JSON and stream-JSON
formats, and slash-command expansion. The exact source command was:

```text
$HOME/.local/bin/agy --output-format json -p /usage
```

Each execution used:

- exact argv without a shell-constructed provider command;
- closed stdin;
- an empty owner-only task directory outside any repository;
- inherited provider-owned authentication with no injected credential;
- stdout capped at 64 KiB and stderr capped at 16 KiB;
- a 15-second timeout;
- one owned process group with complete teardown.

No residual `agy` process or neutral-directory artifact remained.

## 5. Live execution results

| Execution | Context | Exit | Structured output |
|---|---|---:|---|
| 1 | Network-restricted tool sandbox | 1 | None; zero stdout, bounded generic stderr |
| 2 | Network-restricted tool sandbox | 1 | None; zero stdout, bounded generic stderr |
| 3 | Approved ordinary network context | 0 | One JSON object, 1141 stdout bytes, zero stderr bytes |

Executions two and three were deliberate ambiguity-resolution reads, not
automatic retries. The source-read budget is now `3/3`; `/credits` reads remain
`0`.

No raw stderr or JSON was persisted. The first two generic errors were not
classified as authentication or provider-schema failures. The third result
proves one ordinary current read but does not prove repeatability.

## 6. Sanitized structured contract

Top-level type: object. No schema/version marker was observed.

```text
command: object
  name: string
  data: object
    description: string
    groups: array
      group: object
        name: string
        description: string
        buckets: array
          bucket: object
            id: string
            name: string
            remaining_fraction: finite number in 0...1
            reset_time: ISO-8601 datetime string
            window: string
conversation_id: string, observed empty
duration_seconds: number
num_turns: number
response: string
status: string
usage: object containing token counters
```

Two groups with one bucket each were observed. Exact group names, bucket IDs,
bucket names, window values, quota fractions, reset timestamps, response text,
and counters were deliberately not retained.

## 7. Quota and remaining semantics

The quota container is:

```text
command.data.groups[].buckets[]
```

`remaining_fraction` is explicit provider output, not a semantic inference from
numeric range. The only permitted normalization is:

```text
remainingPercent = remaining_fraction × 100
```

Deterministic test rules are:

- accept finite numbers only in `0...1`;
- preserve exact zero and full boundaries;
- never clamp;
- missing or wrong-type remaining is unavailable;
- multiple groups and buckets remain independent;
- never sum, split, or infer pools from model names.

The observation was numeric and finite. No used-percentage conversion is needed.

## 8. Reset semantics

Each observed bucket had `reset_time` as an ISO-8601 absolute datetime string.
No relative reset duration was observed. Reset remains scoped to its own bucket
and can never migrate across bucket identities. A missing reset is optional;
malformed present reset data fails the bucket closed.

No disabled or unlimited representation was observed. No freshness/currentness
field was observed. The source therefore depends on local observation time if
it is ever admitted.

## 9. Multiple-bucket identity limitation

The JSON exposes group `name`, bucket `id`, bucket `name`, and `window`. Those
fields appear sufficient to form a bounded composite identity, but their exact
safe values were not retained and were not compared across two successful
ordinary reads.

This prevents proof that independent pools can be mapped stably without merging
or splitting them. It is a mandatory admission failure, not an optional display
label limitation.

## 10. Authentication classification

Current provider-owned authentication worked for the successful command. No
browser launched, no login action appeared, and no credential material crossed
into UMA or DEV.

No password, verification code, Keychain/keyring item, cookie, browser profile,
OAuth token, refresh token, session, auth database, account identity, or login
URL was accessed. Authentication was not intentionally invalidated.

A future source would need fixed fail-closed `loginRequired`, `sessionExpired`,
and `browserLoginSideEffect` classifications. M6-G1R does not implement them.

## 11. No-turn, no-task, no-conversation and no-spend evidence

The official 1.1.11 public contract describes read-only print-mode `/usage` as
creating no agent turn, quota spend, or conversation. Live evidence agrees in
all observable ways:

- no prompt or task was supplied;
- no browser/login action occurred;
- no workspace/project artifact appeared;
- no residual provider child remained;
- the observed `conversation_id` was empty.

However, the sanitized probe retained only a `0...1` range classification for
`num_turns`, not exact `num_turns == 0`. That mandatory live proof is therefore
unavailable.

Strongest honest spend conclusion:

```text
No attributable quota consumption was observed within available evidence,
consistent with the official read-only command contract.
```

Mathematical zero-spend cannot be independently measured at the provider's
display granularity and is not claimed.

## 12. Privacy allowlist

If later readmission is authorized, only these concepts may survive decoding:

- bounded validated group/bucket identity;
- bounded non-identifying label only when separately proven safe;
- explicit `remaining_fraction`;
- per-bucket `reset_time`;
- bounded validated `window` only when required for pool identity;
- installed CLI version and local observation time.

Discard before business logic:

- `conversation_id`;
- `response` and all description/free-text fields;
- `usage` token counters;
- `num_turns`, duration and unused status text;
- account, plan, identity, project, workspace, VCS, task, tool, prompt,
  response, login, session, credential and token fields;
- every unknown future field.

Raw stdout, stderr, JSON, live values, timestamps and raw-payload hashes are
never durable evidence.

## 13. Process and privacy evidence method

The probe observed only its owned child and bounded pipes. External process
checks used exact process names/PIDs only. No broad argv or environment dump was
performed. Safari and `agy` counts were zero before and after the successful
ordinary-network execution.

The previous transient CSRF-argument incident was not repeated. No sensitive
value entered Git, tests, task files, screenshots, logs or this record.

## 14. Credits

**`CREDITS DEFER`**

No `/credits` command ran. The observed quota container had no admitted Credit
field. Credits do not influence this quota decision.

## 15. Independent review and decision

The source/protocol examiner and privacy examiner independently selected
`NO-GO` because repeated successful detailed structure, stable bucket identity,
and exact live no-turn proof are core gates. The QA examiner recommended
`CONDITIONAL GO`, treating them as later acceptance conditions. Root review
rejected that relaxation because the governing Goal permits conditional status
only for optional metadata after primary stability and identity are proven.

The final M6-G1R decision is therefore:

```text
NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE
```

The only next task is **Founder source-direction decision**. M6-G2 remains
locked.
