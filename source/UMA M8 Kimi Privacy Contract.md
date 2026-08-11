# UMA M8 Kimi Privacy Contract

Applies to: M8-G1 and any later Kimi source-admission recheck
Current result: `SETUP REQUIRED`

## Purpose

This contract permits only the minimum provider-owned usage evidence needed to
decide whether Kimi can be monitored honestly. It does not admit credentials,
identity, private account state, conversations, workspaces, or raw payloads.

## Source priority

1. official Kimi Code CLI `/usage` after exact installed capability proof;
2. official Kimi Code Console only under a separately admitted browser Goal;
3. official Subscription / My Quota only under a separately admitted browser
   Goal.

Kimi Open Platform/API-key routes, credential/config files, private endpoints,
manual values, local estimates, and screenshot/OCR sources are prohibited.

## Pre-qualification boundary

Permitted before a quota observation:

- exact executable/app presence;
- resolved executable path and symlink chain;
- file type, architecture, owner, mode, version, signature, Gatekeeper, and
  installer/release provenance;
- bounded `--version` and `--help` capability output;
- authentication state classification only when exposed by an approved public
  command without revealing authentication material.

Forbidden:

- reading provider credential, token, config, Keychain, cookie, browser-profile,
  local/session-storage, or authentication-database contents;
- broad filesystem, process argument, or environment inspection;
- invoking Agent prompt mode as a substitute for a quota control command.

## Qualified observation limits

```text
maximum qualified quota/source observations: 3
maximum live-source window: 15 minutes
automatic retries: 0
provider prompts/tasks/conversations: 0
intentional model/token spend: 0
Extra Usage purchase/settings mutations: 0
```

If no candidate qualifies, use zero reads. M8-G1 used zero.

## CLI execution contract

A later qualified CLI read must use:

- one exact trusted executable, never PATH-only authority;
- installed-help-derived control input;
- one empty owner-only UMA task directory;
- no shell interpolation;
- no environment credential injection;
- closed stdin except the exact proven control sequence;
- bounded in-memory stdout/stderr or PTY capture;
- 15-second request timeout and 20-second hard timeout unless later evidence
  justifies a narrower bound;
- one owned process/read, complete cancellation, termination, and reap;
- no raw transcript persistence.

Safe process evidence is limited to exact executable path/name, exact PID,
owned parent/child relationship, process count, bounded resource counters, and
exit/absence classification. Full process `argv` and environment are forbidden.

## Durable retention allowlist

Only these classifications may enter Git, QA evidence, or final reports:

- source/version classification;
- safe bounded window labels or stable IDs;
- field names/types;
- explicit used/remaining/used-plus-total semantic classifications;
- cycle/reset type, without exact Founder reset date;
- minimum account-mode class;
- source freshness and repeatability classifications;
- booleans such as `ZERO_TURN_CONFIRMED`;
- operation counts and teardown result.

## Durable retention denylist

Never retain or reproduce:

- email, phone, account ID, organization identity, or account name;
- plan/billing identity beyond the minimum account-mode class;
- OAuth/access/refresh tokens, API keys, login URLs/codes, cookies, sessions,
  Keychain values, browser profiles, local/session storage, or auth databases;
- payment method, payment history, invoices, or transaction history;
- raw CLI/TUI output, raw account responses, raw DOM/HTML, screenshots, or OCR;
- prompts, responses, conversations, tasks, transcripts, workspace paths, or
  source code;
- exact Founder quota values or reset dates in durable evidence;
- full process command lines, `argv`, or environment dumps.

Sanitization must occur before business logic, test evidence, logging, or native
handoff. Unknown/private fields fail closed and are discarded, not traversed or
projected.

## No-work/no-spend acceptance

A source may be admitted only when bounded evidence supports:

- zero provider prompt and model response;
- zero Agent turn, task, or conversation creation;
- no workspace discovery, read, or mutation;
- no attributable quota decrement within provider granularity;
- no residual child, listener, helper, or task-owned state;
- no login URL/code or authentication material retained.

Documentation alone cannot prove these runtime properties. M8-G1 claims zero
work/spend only for its own zero-execution path.

## Browser boundary

Browser observation remains locked unless an accepted result explicitly routes
to M8-WEB-G1. Any later browser source requires provider-controlled login,
exact official routes, bounded semantic extraction, sanitized output before
handoff, and no cookie/profile/token/raw DOM/HTML access or persistence.

## M8-G1 privacy result

```text
quota/source observations: 0
credentials/private-state reads: 0
login/browser actions: 0
raw payloads retained: 0
identity retained: 0
provider prompts/tasks/spend: 0/0/0
```

`SHARED MEMBERSHIP: CONDITIONAL`
`KIMI CODE LIMITS: CONDITIONAL`
`EXTRA USAGE: UNREADABLE`
`M8-G2 remains locked.`
