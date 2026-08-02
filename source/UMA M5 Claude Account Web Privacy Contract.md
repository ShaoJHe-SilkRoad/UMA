# UMA M5 Claude Account Web Privacy Contract

> **Historical NO-GO evidence.** This contract records the rejected embedded
> account-web experiment. It is not production authority. The active
> M5-BROWSER-G1 boundary keeps authentication in the system browser and accepts
> only a bounded normalized WebExtension message.

Date: 2026-07-31
Status: rejected source contract retained for audit

## Required boundary

Any future account-web proposal would have to prove all of the following
before implementation:

- provider-controlled authentication in a documented system-browser flow;
- an official callback and Usage authorization contract;
- no password, passkey, verification code, cookie, token, session, identity,
  or browser profile transfer to UMA;
- App Sandbox enabled with only required outbound networking;
- no ambient Desktop, Documents, Downloads, user-selected-file, temporary
  directory, Keychain group, Apple Events, Accessibility, Screen Recording,
  camera, microphone, Bluetooth, or location access;
- no DOM evaluation until exact official origin, exact authenticated Usage
  route, and required Usage landmarks are all proven;
- no login-page DOM inspection;
- no `WKScriptMessageHandler`, full page text, HTML, DOM, console, request,
  response, header, local/session storage, or cookie extraction;
- one bounded atomic normalized result or one rejected result;
- exact clear, teardown, expiry, and zero-retention proof;
- no effect on Safari, Chrome, Claude Desktop, or other Claude sessions.

## Current audit result

| Requirement | Result |
|---|---|
| Provider-controlled login | Attempted; embedded Google path incompatible |
| Credentials read or retained | No evidence; none persisted |
| Nonpersistent WebKit data store | Pass |
| Zero retained website-data records | Pass |
| Exact task-owned cleanup | Pass |
| App Sandbox | Fail; disabled |
| Login-page DOM exclusion | Fail; bounded text landmarks were inspected |
| Credential-field value inspection | Not performed |
| Raw HTML/DOM persistence | Pass; absent |
| Cookie/storage export | Pass; absent |
| System-browser callback contract | Fail; no official Claude contract found |
| Overall privacy admission | Fail |

The failures are capability and contract failures. They do not establish that
credentials or identity were exposed. No sensitive value is reproduced in
this record.

## Required future handling

The WebKit prototype must not be revived. A future system-browser proposal may
be investigated only after Anthropic publishes an official compatible flow
that leaves credential entry with the system browser and explicitly authorizes
the requesting application to read Usage data. The provider callback and any
authorization material would require a separate privacy review before use.
