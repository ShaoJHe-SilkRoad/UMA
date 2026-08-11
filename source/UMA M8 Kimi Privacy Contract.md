# UMA M8 Kimi Privacy Contract

Applies to: M8-G1R and any later Founder-authorized Kimi source recheck
Current result: `NO-GO`

## Purpose and source boundary

Only the minimum provider-owned usage semantics needed for an honest admission
decision may be observed. Credentials, identity, private account state,
conversations, workspaces, raw terminal output, and exact Founder values are
outside the contract.

Allowed source priority remains:

1. exact trusted official Kimi Code CLI interactive `/usage` built-in;
2. official Kimi account surfaces only under a separately authorized Goal.

API keys, credential/config files, Keychain, cookies, browser profiles, private
endpoints, manual values, local estimates, conversation history, screenshots,
and OCR are prohibited.

## Control-path contract

The current official contract admits no standalone structured usage command.
`-p` / `--prompt` is an Agent route and must never carry `/usage`.

A bounded CLI observation must:

- execute only `$HOME/.kimi-code/bin/kimi` after exact trust verification;
- use an empty owner-only task directory and a safe environment allowlist;
- open no resumed session and provide no prompt/session argument;
- wait for an idle TUI marker;
- type only a partial `/usag` prefix;
- require the exact provider-owned built-in autocomplete description before
  appending the final character and sending Enter;
- abort without Enter if positive recognition is absent;
- capture only bounded in-memory PTY bytes and emit classifications only;
- terminate and reap the exact task-owned process group;
- inspect executable path/PID/count only, never broad argv or environment.

The positive autocomplete gate prevents unknown slash input from falling
through to an Agent message.

## M8-G1R operation bounds and result

```text
maximum /usage observations: 3
conservatively consumed: 3
successful sanitized observations retained: 0
automatic retries: 0
provider prompts / Agent turns / tasks: 0 / 0 / 0
intentional model/token spend: 0
/credits reads: 0
account/Extra Usage mutations: 0
credential/private-state reads: 0
```

No additional live read is authorized after this result.

## Durable retention allowlist

Only these classifications may enter Git or final reporting:

- CLI version/source/control class and trust classification;
- safe bounded field names/types or semantic labels from official contracts;
- USED / REMAINING / used-plus-total classification;
- cycle/reset type without an exact private timestamp;
- minimum account-mode class;
- presence/absence/readability and repeatability classifications;
- native-money type without an exact balance;
- no-work/no-spend booleans, counts, teardown, and output-size class;
- source decision and next-task routing.

## Durable retention denylist

Never retain, hash, reproduce, or traverse into:

- email, phone, name/avatar, account/organization ID, or billing identity;
- tokens, API keys, credentials, login/device codes, cookies, sessions,
  Keychain values, browser profiles, or authentication databases;
- payment methods, invoices, transaction history, or exact wallet balance;
- raw CLI/TUI output, raw account responses, DOM/HTML, screenshots, or OCR;
- prompts, responses, conversations, tasks, source code, or workspace content;
- exact Founder percentages, credits, resets, or plan values;
- full command lines, argv, process environment, or unrelated process data.

Sanitization occurs in memory before durable evidence. Unknown/private content
is rejected and discarded, not logged or projected.

## No-work/no-spend and process contract

The current built-in gate plus official public implementation evidence supports
zero Agent prompt, response, turn, conversation, and task creation for the
bounded control attempts. The neutral workspace remained empty. No residual
task-owned process remained.

An exact no-decrement claim is not admitted because no two successful
normalized observations were retained. Missing comparison evidence must not be
rewritten as zero spend beyond provider measurement precision.

Safe process evidence is limited to exact executable path, exact PID,
task-owned parent/child relationship, exact Kimi-process count, bounded resource
counters, and exit/absence classification. Broad process command-line or
environment inspection remains forbidden.

## Temporary state restoration

The first observation selected the provider's default workspace-trust choice
instead of dispatching `/usage`. That created one exact local trust marker for
the empty task-owned directory. It is not credential or account state. Closeout
must remove only that exact marker, the empty neutral directory, the sanitized
probe, its task-owned bytecode cache, and the read-only official-source clone.
No provider-owned authentication or unrelated Kimi state may be modified.

## Current channel result

```text
SHARED MEMBERSHIP: MISSING
KIMI CODE LIMITS: NO-GO
EXTRA USAGE: UNREADABLE
```

`M8-WEB-G1 remains locked.`
`M8-G2 remains locked.`
