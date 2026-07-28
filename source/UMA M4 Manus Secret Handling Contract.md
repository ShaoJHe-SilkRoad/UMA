# UMA M4 Manus Secret Handling Contract

Status: superseded historical M4-G2 design — do not execute
Date: 2026-07-28

> M4-N retired and removed the API-key product path before production
> admission. This document is retained only to explain the rejected
> prototype's former safety boundary. It is not setup guidance, and UMA must
> not request, accept, persist, or use a Manus credential.

## Secret classification

A Manus API key grants full account access according to the official
documentation. UMA treats it as a password-equivalent secret even though the
admitted endpoint is read-only.

The key is allowed in only three transient locations:

1. the Settings `SecureField` before submission;
2. one task-local save/verify operation;
3. one request header assembled immediately before the admitted call.

It is durable only in the exact UMA-owned Keychain item described below.

## Keychain item

```text
class:          kSecClassGenericPassword
service:        com.kevinchen.CodexUsageMonitor.manus-api-v2
account:        primary
dataKeychain:   true
accessible:     kSecAttrAccessibleWhenUnlockedThisDeviceOnly
synchronizable: false
accessGroup:    absent
```

Every add, read, update, and delete query must include
`kSecUseDataProtectionKeychain = true`. No access group, shared web
credential, internet-password item, synchronizable item, environment variable,
command-line argument, file, or preferences value is allowed.

The key store is a dedicated actor or otherwise serialized service off the
main actor:

- add with `SecItemAdd`;
- on `errSecDuplicateItem`, update only the exact matching item;
- read with `SecItemCopyMatching`, `kSecReturnData`, and
  `kSecMatchLimitOne`;
- delete with `SecItemDelete`;
- treat `errSecItemNotFound` during delete as successful cleanup;
- treat `errSecInteractionNotAllowed` as transient locked/unavailable;
- map other statuses to bounded internal categories without emitting raw query
  dictionaries or secret-bearing context.

M4-G1 defines this query contract but performs no `SecItem` operation.

## Input lifecycle

Save and Verify must:

1. reject an empty draft locally;
2. transfer the draft to the key store once;
3. clear the `SecureField` binding immediately;
4. discard temporary UI validation state;
5. read the stored value inside the client for verification;
6. never return the key to a presentation model.

Swift-managed strings cannot truthfully be promised as cryptographically
zeroized. The enforceable controls are short lifetime, no duplication beyond
the one operation, no caches, no persistence, and no diagnostics.

## Network lifecycle

The key may be attached only to:

```text
GET https://api.manus.ai/v2/usage.availableCredits
header: x-manus-api-key
```

The client must use an ephemeral session with cookies, shared credentials, and
URL cache disabled. Redirects are rejected so the header cannot be forwarded.
No query or body is permitted. The client accepts only one successful JSON
response no larger than 16 KiB and immediately releases raw bytes after strict
decode.

No other host, path, method, provider SDK, browser session, or Manus.app
process may receive the key.

## Persistence and diagnostics

Allowed persistence:

- a safe configured/not-configured boolean;
- nonsecret display preferences;
- no cached Manus balance.

Forbidden everywhere outside Keychain:

- API key or fragments;
- `x-manus-api-key` header values or header dictionaries;
- request/response body;
- raw provider error message;
- request ID;
- account, team, email, or organization identity;
- task, history, prompt, response, file, cookie, token, or session data;
- secret-bearing OSStatus context.

Logs and evidence may record only:

- operation category;
- exact admitted host/path with no query;
- credential present/absent;
- HTTP status category;
- bounded failure category;
- safe timing and coalescing counts.

Source fixtures must use unmistakable placeholders and may never resemble a
real provider key. Screenshots must exclude the SecureField and provider-owned
key-creation screen.

## Failure and cadence

- `401`/`403` or `permission_denied`: authorization required; withdraw
  admission and suspend automatic reads until user action.
- `429`/`rate_limited`: withdraw current admission and wait for the next
  conservative scheduled opportunity; never retry immediately.
- timeout/network failure: transient unavailable; no retained stale card.
- locked Keychain: transient unavailable, not invalid credentials.
- malformed/missing/negative/overflowing schema: fail closed and withdraw
  admission.
- overlapping triggers: one in flight; coalesce to at most one follow-up.

The earliest automatic read is 60 seconds after the prior read completes.
Panel and Assistant visibility changes do not initiate reads.

## Disconnect and replacement

Disconnect is scoped and atomic from the user's perspective:

1. stop future scheduling;
2. cancel the task-owned request if possible;
3. delete only the exact Manus Keychain item;
4. clear transient key and decoded state;
5. clear the safe configuration flag;
6. withdraw Manus from both surfaces.

Deleting or replacing the Manus key must not touch Codex, WorkBuddy, browser
sessions, Manus.app, any other Keychain item, or provider preferences.

Key replacement uses the same one-item update path. A failed replacement may
not leave the new draft in preferences or logs. The UI reports only a bounded
failure category.

## Package and test obligations

Before production delivery, tests and package audit must prove:

- every Keychain query uses the data-protection keychain;
- the accessibility class is device-bound and non-synchronizing;
- no access group or secret preferences key exists;
- exact host/path/method/header construction;
- diagnostics redact the key;
- redirects cannot receive the header;
- missing/partial/wrong-type/negative/overflow data fails closed;
- auth and Keychain-lock failures have distinct safe categories;
- disconnect deletes the item and withdraws admission;
- the package contains no secret, raw response, live balance, private fixture,
  or credential-shaped sample.
