# UMA M7 Cursor Browser Source Dossier

**Goal:** M7-G1C
**Date:** 2026-08-11
**Status:** `NO-GO — CURSOR PRODUCTION SUPPORT REMAINS LOCKED`
**Production runtime:** unchanged
**Only next task:** Founder source-direction decision

M7-G1C corrects the M7-G1B source decision using current Cursor-owned public
evidence. It does not repeat browser testing, authenticate, read provider data,
or implement Cursor. M7-G2 remains locked.

## Corrected adjudication

```text
CURSOR BROWSER SOURCE ARCHITECTURE VIABLE
FREE PLAN SEMANTICS RESOLVED
FREE PLAN ENFORCEMENT RELIABILITY NOT ADMITTED
PAID PLAN CONTRACT NOT LIVE QUALIFIED
CURSOR PRODUCTION SUPPORT REMAINS LOCKED
```

The previous claim that the Free-plan percentage direction was unresolved is
superseded. Cursor-owned Support material explicitly treats the Overview meter
as a **used percentage** and describes the complement as remaining. Therefore:

```text
dashboardPercent = usedPercent
remainingPercent = 100 - usedPercent
```

Normalization is applied exactly once. Values outside the finite 0...100 range
fail closed. This is a provider-semantic rule, not a range, color, progress-bar,
or numeric-value inference.

## Current Cursor-owned public evidence

- Cursor Models & Pricing:
  <https://cursor.com/docs/models-and-pricing>
  documents two separate monthly pools for Pro, Pro Plus and Ultra:
  `Cursor Models` and `Other Models`. Both reset with the monthly billing cycle
  and are visible on the usage dashboard.
- Cursor Support usage guidance:
  <https://forum.cursor.com/t/agent-pro-usage-guidance-contradicts-docs-and-live-dashboard/166053/6>
  identifies the Usage section as the source for real-time usage, remaining
  allowance and token breakdowns, while keeping on-demand overage separate.
- Cursor Support Free-plan mismatch:
  <https://forum.cursor.com/t/auto-immediately-switches-back-to-composer-2-5-fast-locked-on-free-plan/165268>
  explicitly identifies the Overview meter as used, derives remaining as its
  complement, and confirms a known condition where the IDE blocks work while
  the dashboard still displays remaining allowance.
- Cursor Support two-pool clarification:
  <https://forum.cursor.com/t/missing-total-usage-bar-in-dashboard/166582/4>
  confirms that Cursor Models and Other Models remain separate because their
  overflow rules differ.

## Five-part decision

| Dimension | Classification |
|---|---|
| Browser source architecture | `VIABLE` |
| Percentage direction | `USED` |
| Deterministic normalization | `remainingPercent = 100 - usedPercent` |
| Dashboard remaining quantity | `YES` |
| Reliable predictor of continued availability | `NO` |
| Free-plan production suitability for predicting when work may pause | `NO-GO` |
| Paid-plan coverage | `DOCUMENTED BUT NOT LIVE QUALIFIED` |
| Overall Cursor production support | `LOCKED` |

“Truthful provider-rendered observation” means UMA can faithfully report what
Cursor's dashboard displays. It does not mean that the display is an admitted
predictor of whether Cursor will accept the next request.

## Account-mode coverage

The live Founder observation remains a one-pool Free-account surface with a
stable provider-owned label and percentage unit; no paid-plan pools manufactured
from that fixture are admitted.

Current documentation describes two independent paid-plan pools:

1. `Cursor Models`
2. `Other Models`

Those contracts are `DOCUMENTED BUT NOT LIVE QUALIFIED`. No authenticated
Pro, Pro Plus, or Ultra observation established their current DOM identity,
cardinality, reset projection, repeated stability, or extraction contract.
Free-plan evidence cannot qualify paid-plan layouts.

On-demand use is separate from the included pools. The recognized official
route family remains:

- `https://cursor.com/dashboard`
- `https://cursor.com/dashboard/usage`
- `https://cursor.com/dashboard/spending`

M7-G1B observed the first two as available for the Free account. Spending
remained visibly loading and is not required when another recognized official
surface provides a complete contract.

## Preserved browser architecture evidence

### Isolated WebKit attempt

The task-owned prototype had App Sandbox enabled, outbound network-client entitlement only,
a dedicated persistent `WKWebsiteDataStore(forIdentifier:)`,
and no JavaScript evaluation before an exact admitted route. It did not share
Safari, Chrome, Cursor, or the default WebKit store. Provider-controlled Google
authentication reached an embedded-auth compatibility failure; the isolated
architecture is rejected without another login attempt.

### Safari Browser Companion

The **UMA Cursor Browser Companion v2** proved:

- provider-controlled Safari authentication feasibility;
- exact dashboard-site permission with website access only on `cursor.com`;
- strict recognized-route checking before bounded semantic extraction;
- sanitized native handoff without raw DOM, HTML, URL, identity, billing,
  cookie, token, or session material;
- eight repeated sanitized observations with stable Free-plan structure;
- automatic read feasibility;
- fail-closed handling for unknown layouts;
- complete disable, unregister, process teardown, and security restoration.

The older task-owned companion remained disabled, and the frozen Claude BrowserExtension
was not modified.

This architecture result remains viable even though production admission is
blocked by source reliability and plan coverage.

## Preserved operation accounting

```text
Task-owned isolated probe launches: 3
Provider-controlled login sessions opened: 1
Human login completions: 1
Authenticated dashboard route navigations: 4
Successful sanitized observations: 8
Safari fallback containing-app launches: 3
Credential/cookie/private-state reads: 0
Provider prompts/tasks: 0
Intentional quota spend: 0
Unexpected Human-supplied identity exposures: 1 transient
Unexpected exact-quota accessibility exposures: 2 transient
Retained incident identity/screenshot/log/payload copies: 0
Retained exact-quota/DOM/URL copies: 0
```

M7-G1C added no provider operation:

```text
M7-G1C provider reads/browser logins/prompts/tasks/spend: 0/0/0/0/0
```

Here, `provider reads` means authenticated quota/dashboard reads from the
Human's session. Public Cursor source-document retrieval is not an
authenticated provider read and accessed no account or session data.

## Final browser cleanup

- Safari `Allow unsigned extensions` was verified `Off` before Safari quit.
- The legacy and v2 task-owned companions were disabled.
- Both task-owned extension identifiers were unregistered.
- The two exact `/private/tmp` probe roots are absent.
- The three exact task-owned app-container records were removed.
- No task-owned companion, probe, native host, process, or retained page
  evidence remains.
- Safari login data and unrelated browser state were untouched.

## Final source decision

The browser architecture is viable and the Free-plan display semantic is
resolved. The source is still not suitable for UMA's present product goal:
predicting when provider work may pause. Cursor itself documents a known
Free-plan mismatch between dashboard remaining allowance and actual IDE
enforcement, while paid-plan browser contracts are not live qualified.

**Final decision: `NO-GO — CURSOR PRODUCTION SUPPORT REMAINS LOCKED`.**
Cursor remains unsupported and hidden. M7-G2 remains locked. The only next task
is a Founder source-direction decision.
