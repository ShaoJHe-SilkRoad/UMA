# UMA M8 Kimi Admission Decision

Decision date: 2026-08-11
Goal: M8-G1R — live installed Kimi CLI source re-admission
Overall decision: `NO-GO`

## Decision

```text
NO-GO

SHARED MEMBERSHIP: MISSING
KIMI CODE LIMITS: NO-GO
EXTRA USAGE: UNREADABLE
```

The trusted, authenticated official CLI and its interactive built-in `/usage`
control class are real. The bounded current-device gate nevertheless retained
zero successful sanitized usage observations from a conservatively exhausted
3/3 budget. Stable live identities, repeatability, current account mode,
shared-membership truth, Code-window truth, Extra Usage state, and an
attributable no-decrement comparison are therefore not established.

The decision is not `GO` or `CONDITIONAL GO — IMPLEMENTATION READY`: shared
membership and continuation truth are mandatory rather than optional. It is
not `SOURCE EXPANSION REQUIRED — M8-WEB-G1`: that outcome requires an admitted
useful partial CLI source, which the failed live gate did not establish.

## Gate-by-gate result

| Mandatory gate | Result |
|---|---|
| Official provider-owned source candidate | PASS |
| Exact installed executable trust | PASS — exact setup hash/version/identity and strict signature |
| Provider-controlled authentication | PASS — Human-confirmed; credentials opaque |
| Non-Agent control classification | PASS — interactive TUI built-in only; prompt mode rejected |
| Successful current sanitized read | FAIL — 0 retained successes from 3/3 accounted observations |
| Current shared membership quantity/scope | FAIL — missing |
| Current five-hour and provider-cycle values | FAIL — no retained live observation |
| Extra Usage current state | FAIL — unreadable |
| Explicit live semantics | FAIL — public renderer contract alone is insufficient |
| Stable live pool/window identities | FAIL |
| Repeated live observations | FAIL |
| Zero Agent turn/task/conversation | PASS for the bounded gated control path |
| No attributable quota decrement | NOT ESTABLISHED |
| Credential/privacy boundary | PASS |
| Process teardown | PASS — no residual owned process |
| Read accounting | PASS — 3/3, no retries, no `/credits` |

## Current source classification

- Source class: official interactive Kimi Code TUI built-in.
- Exact candidate: `$HOME/.kimi-code/bin/kimi` 0.34.0, no prompt/session argv.
- Automation feasibility: not admitted; current PTY control did not produce a
  retainable successful contract.
- Account mode: `unknown/unsupported`.
- Shared membership: no live source contract.
- Code windows: official public renderer describes explicit used-percent weekly
  and five-hour rows, but this is not current-account live proof.
- Extra Usage: official public renderer describes native money, but live state
  and balance readability are unknown.

## Operation accounting

```text
Kimi /usage observations: 3 / 3
Successful sanitized observations retained: 0
Automatic retries: 0
Provider prompts / Agent turns / tasks: 0 / 0 / 0
Intentional Kimi spend: 0
/credits reads: 0
Credential/private-state reads: 0
Raw payloads or exact Founder values retained: 0
```

## Rejected substitutions

- `kimi -p "/usage"` or any Agent-prompt route;
- API keys, copied OAuth material, Keychain/config/token/cookie/profile reads;
- private/internal endpoints or DevTools replay;
- manual values, local estimates, conversation/task history, screenshots/OCR;
- inferring shared membership or Extra Usage from the public renderer;
- exceeding the live-read cap to obtain a more convenient answer.

## Routing

Exactly one next task: `Founder source-direction decision`.

`M8-WEB-G1 remains locked.`
`M8-G2 remains locked.`

Production runtime implementation is not authorized by this decision.
