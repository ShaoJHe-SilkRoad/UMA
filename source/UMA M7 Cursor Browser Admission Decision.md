# UMA M7 Cursor Browser Admission Decision

**Goal:** M7-G1C
**Date:** 2026-08-11
**Current state:** COMPLETE
**Final decision:** `NO-GO — CURSOR PRODUCTION SUPPORT REMAINS LOCKED`
**Only next task:** Founder source-direction decision

M7-G1C supersedes only the semantic-ambiguity rationale in M7-G1B. The accepted
direct local/CLI result remains `NO-GO`. No production Cursor source was
implemented, and M7-G2 remains locked.

## Corrected decision matrix

### A. Browser source architecture feasibility

`CURSOR BROWSER SOURCE ARCHITECTURE VIABLE`

Provider-controlled Safari authentication, exact-site permission, bounded
sanitized extraction, repeated observation, native handoff, fail-closed layout
handling, and complete cleanup/security restoration were proven in M7-G1B.
The rejected isolated WebKit login path does not invalidate the separately
proven Safari architecture.

### B. Free-plan semantic correctness

`FREE PLAN SEMANTICS RESOLVED`

Free-plan percentage semantic: `USED`.

```text
dashboardPercent = usedPercent
remainingPercent = 100 - usedPercent
```

The complement is applied once. No double inversion and no range-based
inference are permitted. The dashboard remaining quantity is a truthful
provider-rendered observation of the displayed dashboard state.

### C. Free-plan enforcement reliability

`FREE PLAN ENFORCEMENT RELIABILITY NOT ADMITTED`

Free-plan enforcement reliability: `NOT ADMITTED`.

Current Cursor Support evidence confirms a known mismatch: the IDE can reject
work as usage-limited while the dashboard still displays remaining allowance.
The dashboard is therefore not a reliable predictor of actual continued Cursor
availability or of when work will pause.

### D. Paid-plan coverage

`PAID PLAN CONTRACT NOT LIVE QUALIFIED`

Cursor documents two independent monthly pools for Pro, Pro Plus, and Ultra:
`Cursor Models` and `Other Models`. Both are documented as visible on the
usage dashboard and resetting with the monthly billing cycle.

Classification: `DOCUMENTED BUT NOT LIVE QUALIFIED`.

No paid-plan account was observed. The Free one-pool fixture does not qualify,
manufacture, merge, or split paid-plan pools.

### E. Overall production support

`CURSOR PRODUCTION SUPPORT REMAINS LOCKED`

The current project goal is not merely to mirror a dashboard meter; it is to
monitor availability well enough to warn when provider work may pause. A
display that can report remaining allowance while enforcement already blocks
work does not satisfy that contract. Unqualified paid-plan layouts add a second
mandatory coverage gap.

Therefore the corrected result remains `NO-GO`, but for reliability and
coverage—not semantic ambiguity. This is not `CONDITIONAL GO`, because the
missing enforcement signal and unqualified core account modes are mandatory,
not optional metadata. It is not `SETUP REQUIRED`, because login/setup is not
the sole remaining condition.

## Privacy and operations

No authenticated browser or provider-data action was performed during M7-G1C.
Existing incident containment remains closed, Safari unsigned-extension mode
remains `Off`, and all task-owned companion/probe artifacts remain absent.

```text
M7-G1C provider reads/browser logins/prompts/tasks/spend: 0/0/0/0/0
```

Here, `provider reads` means authenticated quota/dashboard reads from the
Human's session. Public Cursor source-document retrieval is not an
authenticated provider read and accessed no account or session data.

API key, copied token, cookie, Keychain, browser-profile import, private
endpoint, manual quota, and inferred quota routes remain rejected.

**Final:** Cursor remains unsupported and hidden. M7-G2 remains locked. The only
next task is a Founder source-direction decision.
