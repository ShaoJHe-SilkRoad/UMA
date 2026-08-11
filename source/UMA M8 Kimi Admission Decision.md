# UMA M8 Kimi Admission Decision

Decision date: 2026-08-11
Goal: M8-G1 — Kimi unified source admission
Overall decision: `SETUP REQUIRED`

## Decision

```text
SETUP REQUIRED

SHARED MEMBERSHIP: CONDITIONAL
KIMI CODE LIMITS: CONDITIONAL
EXTRA USAGE: UNREADABLE
```

`CONDITIONAL` at the channel level records an official first-party candidate;
it is not an implementation-ready channel admission.

The official Kimi Code CLI is absent on the current Mac. Official Kimi sources
remain viable, but current-device installation, provider-controlled OAuth,
installed command behavior, live quota structure, stable identities,
repeatability, and no-turn/no-spend behavior are not yet proven.

This is not `NO-GO`: the missing prerequisite is official provider-owned setup,
which the M8 Plan defines as a recoverable setup gate without changing source
class. It is not `SOURCE EXPANSION REQUIRED — M8-WEB-G1`: no CLI channel has
yet been installed and admitted, so the prerequisite partial-CLI evidence does
not exist. It is not `CONDITIONAL GO — IMPLEMENTATION READY`: shared membership
and continuation truth are mandatory, not optional metadata.

## Gate-by-gate result

| Mandatory gate | Result |
|---|---|
| Official provider-owned source candidate | PASS — official CLI and official account surfaces documented |
| Trusted installed executable | NOT ESTABLISHED — absent |
| Provider-controlled authentication | NOT ESTABLISHED — no login attempted |
| Current shared membership quantity and scope | NOT ESTABLISHED |
| Current Kimi Code five-hour and cycle limits | NOT ESTABLISHED |
| Extra Usage continuation state | NOT ESTABLISHED |
| Explicit remaining/used semantics | NOT ESTABLISHED from live source |
| Stable pool/window identities | NOT ESTABLISHED |
| Repeatable sanitized observations | NOT ESTABLISHED |
| Zero-turn/no-task/no-spend source behavior | NOT ESTABLISHED |
| Credential/privacy boundary | PASS for M8-G1 — prohibited routes rejected; zero private reads |
| Source-read accounting | PASS — 0 of 3 used |

## Admitted and rejected claims

Admitted from official public documentation:

- one Kimi ecosystem with a shared membership credit pool;
- separate Kimi Code five-hour and weekly/provider-cycle limits;
- Extra Usage as a shared native continuation wallet;
- interactive TUI `/usage` availability;
- provider-owned OAuth as the preferred CLI authentication path.

Not admitted:

- a standalone or machine-readable `/usage` command;
- `kimi -p "/usage"` as a control read;
- any installed version, schema, or executable trust claim;
- current account mode, quota values, reset dates, or stable live identities;
- zero-turn/no-spend behavior of a future read;
- browser extraction or production connector architecture.

Rejected source classes:

- Kimi/Open Platform API keys or balances;
- copied OAuth material or direct token use;
- Keychain, credential, config, cookie, browser-profile, or auth-database reads;
- private/internal endpoints or DevTools replay;
- local conversation, task, transcript, activity, or token estimates;
- manual values and screenshot/OCR sources.

## Operation accounting

```text
Kimi quota/source observations: 0 / 3
Kimi prompts/tasks/conversations: 0
Intentional Kimi spend: 0
Automatic retries: 0
Kimi login/browser actions: 0
Credential/private-state reads: 0
```

No exact Founder values, reset dates, identities, or raw payloads were retained.

## Routing

Only next task: `M8-SETUP-G1`, after direct Founder authorization.

`M8-WEB-G1 remains locked.`
`M8-G2 remains locked.`

M8-G1 stops after this evidence-backed setup decision and local documentation
commit. Production runtime implementation is not authorized by this decision.
