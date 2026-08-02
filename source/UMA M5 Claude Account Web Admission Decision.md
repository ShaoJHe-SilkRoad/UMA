# UMA M5 Claude Account Web Admission Decision

> **Historical NO-GO evidence.** Embedded account-web admission remains
> rejected. The Founder-approved M5-BROWSER-G1 route is separately gated and
> cannot use WKWebView login, cookie import, or login-page DOM inspection.

Date: 2026-07-31
Goal: M5-WEB-G1

## Verdict

**NO-GO — SAFE ACCOUNT-WEB AUTHENTICATION NOT AVAILABLE**

## Decision basis

1. The task-owned nonpersistent WebKit prototype reached the official Claude
   sign-in surface.
2. The Human-controlled Google sign-in path failed because the identity
   provider rejected the embedded user agent.
3. No retry, alternate factor, embedded-user-agent bypass, cookie transfer,
   or browser-session import is permitted.
4. No authenticated Usage route or current five-hour/weekly observation was
   obtained.
5. Source review found that the prototype had no App Sandbox entitlement.
6. Source review found periodic `evaluateJavaScript` execution on the login
   page before a verified Usage route. It read bounded DOM text landmarks, not
   credential values, but the capability exceeded the approved boundary.
7. Disconnect & Clear returned zero website-data records; exact bundle-owned
   persistence paths, crash reports, and processes were absent afterward.
8. The exact task-owned prototype directory was deleted.
9. Apple documents a system-browser authentication session, but Anthropic does
   not publish a compatible Claude account Usage authorization callback or
   third-party Usage-page contract for UMA.

## Admission outcome

- `isolatedAccountWeb`: rejected.
- Embedded Google OAuth in `WKWebView`: prohibited.
- `ASWebAuthenticationSession`: documented capability only; not admitted or
  implemented without an official Claude callback and Usage authorization.
- Browser cookie/session transfer: prohibited.
- UI scraping, Accessibility, OCR, private API, and network replay: prohibited.
- Production connector, scheduler, Settings, main panel, and Assistant work:
  locked.

No live value, credential, identity, cookie, token, raw HTML, DOM dump, or
screenshot is retained.

## Exactly one next task

**Founder decision** — retain optional terminal CLI integration, mark Claude
Desktop usage unsupported, or close M5 without Claude production support.

Do not start another source class automatically.
