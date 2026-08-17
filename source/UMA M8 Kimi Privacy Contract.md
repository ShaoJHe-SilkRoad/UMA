# UMA M8 Kimi Privacy Contract

Applies to: M8-G1R, M8-WEB-G1, and any later Founder-authorized Kimi source recheck
Current result: `NO-GO`

## Purpose and source boundary

Only the minimum provider-owned usage semantics needed for an honest admission
decision may be observed. Credentials, identity, private account state,
conversations, workspaces, raw terminal output, and exact Founder values are
outside the contract.

Allowed source priority remains:

1. exact trusted official Kimi Code CLI interactive `/usage` built-in;
2. official Kimi account surfaces under M8-WEB-G1's provider-controlled Safari contract.

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

## M8-WEB-G1 Safari fallback contract

The isolated Kimi web session failed provider-controlled Human authentication
twice and is classified `NOT SUITABLE FOR ADMISSION / HUMAN AUTH UX`. It must not
be retried without a new Founder direction.

The temporary Safari companion may operate only after Human enablement and one
Human current-site toolbar action. It must:

- use only the normal provider-owned Safari login/session;
- request exactly `activeTab`, `nativeMessaging`, and `scripting`;
- declare no host permissions, static content scripts, cookie, storage, history,
  web-request, profile, Keychain, or credential access;
- admit only exact HTTPS Kimi Membership quota and Kimi Code Console routes;
- reject an unknown route before DOM inspection;
- inspect only bounded semantic leaf nodes on admitted quota routes;
- sanitize inside the browser layer before native handoff;
- emit only fixed route/layout, pool identity, direction, validity, reset,
  Extra Usage state/native currency class, freshness, and safe failure fields;
- never export exact Founder values during source admission.

M8-WEB-G1 used 5 of 8 authenticated page observations. Four validated receipts
were retained as classification-only evidence; one earlier page extraction was
discarded by a strict timestamp validator and retained no payload. Provider
prompts, Agent turns, tasks, intentional spend, account changes, `/credits`, and
credential/private-state reads remained zero.

Repeated membership receipts returned `UNSUPPORTED_LAYOUT`. This is a safe
failure classification, not permission to broaden extraction or retain page
text. No further provider observation is needed after the mandatory Shared
Membership gate failed.

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

For M8-WEB-G1 closeout, the exact task-owned companion, app container, probe
root, and task-owned processes must be removed after unregistering/disabling the
extension. Safari `Allow unsigned extensions` must be restored to Off and
verified. Kimi's provider-owned Safari authentication must remain untouched.

The 2026-08-17 closeout verified Safari `Allow unsigned extensions` Off, no
task-owned extension registration or process, and no M8-WEB-G1 `/private/tmp`
root. Finder removed the empty metadata-only companion container from
`$HOME/Library/Containers`; after explicit Human confirmation, only its exact
task-owned Trash item was permanently deleted. No Safari data was cleared and
no Kimi provider operation was performed during cleanup.

## Privacy incident containment

One broad read-only Safari accessibility inspection during setup transiently
exposed unrelated non-Kimi accessibility metadata. It exposed no Kimi quota,
identity, credential, cookie, token, session, or account data. No output from
that inspection entered Git, screenshots, package content, task evidence, or
temporary retained artifacts. The repeatable cause was an ad-hoc broad Safari
accessibility command, not repository code. It is retired.

Future browser/process evidence is restricted to exact task-owned bundle paths,
bundle identifiers, PIDs, process counts, ownership, signature, enablement,
exact-route classification, and sanitized receipt state. Broad page trees,
process argv, environments, and unrelated application state are forbidden.

## Current channel result

```text
SHARED MEMBERSHIP: NO-GO
KIMI CODE LIMITS: MISSING
EXTRA USAGE: ABSENT
```

`M8-WEB-G1 result: NO-GO.`
`M8-G2 remains locked.`
