# UMA M8 Kimi Browser Admission Decision

Goal: M8-WEB-G1
Decision date: 2026-08-12
Overall decision: `NO-GO`
Local delivery closeout: 2026-08-17

## Decision

```text
NO-GO

SHARED MEMBERSHIP: NO-GO
KIMI CODE LIMITS: MISSING
EXTRA USAGE: ABSENT
```

The Safari/provider-controlled Browser Companion architecture is privacy-safe
and technically viable for bounded Kimi account-page extraction. That does not
admit the current source. Four retained sanitized observations and one earlier
contained page extraction did not identify the mandatory Shared Membership
channel. The repeated stable outcome was `UNSUPPORTED_LAYOUT`, without exact
values or private page state crossing the browser boundary.

M8-G2 remains locked because a complete current Shared Membership contract is a
mandatory product-truth gate.

## Gate-by-gate result

| Mandatory gate | Result |
|---|---|
| Provider-controlled authentication | PASS — normal Safari session; credentials opaque |
| Isolated Kimi web session | NOT SUITABLE FOR ADMISSION / HUMAN AUTH UX |
| Exact official origin/route gate | PASS |
| Browser-layer sanitization | PASS |
| Current authenticated membership surface | PASS — route available |
| Current sanitized page read | PASS — classification-only receipts |
| Shared Membership identity and quantity | FAIL — unsupported layout |
| Explicit used/remaining semantic | FAIL — unavailable |
| Shared cycle/reset | FAIL — unavailable |
| Repeated source success | FAIL — repeated safe failure only |
| Kimi Code 5h/provider-cycle | MISSING — not observed after mandatory failure |
| Extra Usage | ABSENT on the observed membership surface |
| Automatic source reread | NOT QUALIFIED |
| Privacy and credential boundary | PASS |
| Provider work/spend/account mutation | PASS — 0 |
| Existing-provider protection | PASS — no production mechanism changed |

## Why the result is not another outcome

- Not `GO`: Shared Membership, direction, cycle, identity, and successful
  repeatability are absent.
- Not `CONDITIONAL GO — IMPLEMENTATION READY`: Shared Membership is mandatory,
  not optional metadata.
- Not `SETUP REQUIRED`: Safari authentication, companion enablement, current-site
  permission, and exact route availability were completed. One remaining Human
  setup action cannot repair the unsupported semantic layout.

## Operation accounting

```text
Authenticated page observations used: 5 / 8
Valid sanitized receipts retained: 4
Raw provider payloads retained: 0
Exact Founder quota values retained: 0
Identity / credential / cookie / token reads: 0
Provider prompts / Agent turns / tasks: 0 / 0 / 0
Intentional spend / account changes: 0 / 0
```

No further authenticated observation is necessary or authorized by this
decision. A Code-only read cannot repair the mandatory Shared Membership gate.

## Production boundary and routing

No production connector, provider registration, scheduler, Settings UI, Main
Panel, Desktop Assistant, or browser extension was implemented. WorkBuddy,
Codex, Claude, Antigravity, and Cursor mechanisms remain unchanged.

Exactly one next task:
`Founder Kimi source-direction / M8 closeout decision`.

`M8-G2 remains locked.`

## Closeout state

The task-owned Safari companion, registration, processes, temporary roots, app
container, and exact Trash item are absent. Safari `Allow unsigned extensions`
is Off. No Safari data or Kimi login state was cleared, and no provider
operation occurred during cleanup. Claude-related changes: NONE.
