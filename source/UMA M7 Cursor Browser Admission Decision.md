# UMA M7 Cursor Browser Admission Decision

**Goal:** M7-G1B
**Date:** 2026-08-10
**Current state:** `COMPLETE`
**Final decision:** `NO-GO`

## Decision boundary

The accepted direct local/CLI result remains `NO-GO`. The current task asks
whether the official authenticated Cursor Spending dashboard can support one
privacy-safe browser source.

The decision may become:

- `GO` only when all live quota, identity, privacy, repeated-read,
  currentness, no-provider-work, bounded-lifecycle, and automatic-refresh
  gates pass;
- `CONDITIONAL GO` only when every core gate passes and an optional reset
  detail is the sole missing field;
- `SETUP REQUIRED` only when a fully admissible architecture is proven and
  provider-controlled login/setup is the sole remaining prerequisite;
- `NO-GO` when login is incompatible, values or pool identity are ambiguous,
  privacy requires cookie/token/private-endpoint access, or repeatable bounded
  extraction cannot be proven.

## Final evidence

1. Cursor officially documents two independent monthly pools for Pro-class
   plans: `Cursor Models` and `Other Models`.
2. Cursor officially documents that both pools appear on its dashboard.
3. Cursor distinguishes on-demand usage from included allowance.
4. The exact HTTPS Spending route redirects unauthenticated access to
   Cursor-controlled authentication.
5. A sandboxed, arm64, task-owned isolated WebKit probe with only outbound
   network entitlement was built and tested.
6. The probe used a dedicated persistent WebKit data store and had no
   credential, cookie, storage, file, Keychain, Accessibility, screenshot,
   script-injection, or page-content output path during login.
7. One Human-controlled login attempt reached a provider-side embedded-auth
   compatibility failure. Normal reopen/reload returned to provider login, so
   the isolated architecture is rejected without another attempt or bypass.
8. One Human-supplied screenshot unexpectedly exposed account-identity metadata
   to transient tool context. It was not reproduced, inspected further, copied,
   persisted, committed, packaged, logged, or retained in task-owned evidence.
9. Two filtered Safari accessibility-state reads exposed an exact quota value
   in transient tool output. The first filter admitted dashboard page text; a
   later cleanup-readiness filter matched the provider origin and repeated the
   same exposure class. The value is not reproduced here and was not copied,
   persisted, committed, packaged, logged, or retained. The final repair
   prohibited dashboard-state reads entirely: remaining UI verification used
   only a Safari Settings window, while all admitted page evidence came from
   the sanitized v2 receipt.
10. Safari retained provider-controlled authentication across restart. The v2
    companion was registered, enabled, and granted access only on `cursor.com`;
    the older companion remained disabled.
11. The official `/dashboard`, `/dashboard/usage`, and
    `/dashboard/spending` route classes were observed in the required order.
    Each produced two automatic sanitized classifications without another
    toolbar action, prompt, task, intentional spend, cookie read, or token read.
12. The live Free account exposed one stable provider label,
    `Free Plan usage`, and a percentage unit. No two paid-plan pools were
    manufactured.
13. The Usage route separated on-demand content. The Spending route remained
    Human-visible as loading; a shared Free-plan label did not establish that
    the route itself had completed.
14. The bounded UI text/accessibility contract did not classify the one Free
    percentage as used or remaining and exposed no same-pool denominator.
    Current official paid-plan documentation does not define that different
    Free-account percentage semantic.
15. The native handoff accepted only allowlisted classifications and reported
    zero private fields. No raw DOM, HTML, URL, exact value, identity, billing
    detail, credential, cookie, token, or session value entered durable evidence.
16. Final cleanup disabled and unregistered both task-owned companions,
    verified Safari unsigned-extension mode `Off`, removed the exact task-owned
    probe roots and app-container records, and left provider login data
    untouched.

## Decision

`NO-GO`

The Safari architecture is technically feasible and privacy-bounded, but the
source contract is not numerically honest for the observed Free account.
Without an explicit used/remaining semantic or a complete same-pool denominator,
UMA cannot normalize the percentage. Inferring direction from the number,
progress-bar direction, or paid-plan documentation is prohibited.

This is not `CONDITIONAL GO`: numeric direction is a mandatory quota field, not
optional reset metadata. It is not `SETUP REQUIRED`: provider authentication,
extension enablement, and exact-site permission all succeeded. The remaining
gap is the provider-rendered contract itself.

## Consequence

No Cursor production browser source is admitted. Cursor remains unsupported and
hidden. M7-G2 remains locked. The only next task is a Founder source-direction decision.
