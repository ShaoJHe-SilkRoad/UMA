# UMA M6 Antigravity Privacy Contract

**Goal:** M6-G1
**Date:** 2026-08-08
**Admission state:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`

## 1. Boundary

UMA may eventually consume only normalized current quota facts from one exact,
trusted, official Antigravity CLI executable. The CLI owns authentication. UMA
must never receive or inspect provider authentication material.

M6-G1 performed discovery only. It executed no provider command and received no
provider payload.

## 2. Future process boundary

After separately authorized setup and renewed admission, a source probe must:

- resolve one exact trusted executable outside the repository;
- reject working-directory shadows, unresolved chains, and symlink escapes;
- invoke a fixed argv array without a shell or string interpolation;
- close stdin and inject no credential environment value;
- use an empty owner-only task directory outside user repositories;
- own one child process and allow one read in flight;
- bound stdout to 64 KiB and stderr to 16 KiB;
- use a 15-second normal timeout and 20-second hard timeout;
- terminate and reap only its owned child;
- persist no raw stdout, stderr, or provider payload.

These are admission constraints, not an M6-G1 runtime implementation.

## 3. Strict quota allowlist

A later decoder may publish only fields proven by installed structured output:

- required bounded provider bucket identifier;
- optional bounded non-identifying display label;
- exactly one explicitly documented remaining or used semantic;
- optional documented reset time or reset duration;
- explicit disabled/unlimited state only when documented and observed;
- safe bounded CLI version/capability classification;
- observation and freshness classification.

Numeric rules:

- `remaining_fraction` is finite and within `0...1`, then converts once through
  `remainingPercent = remaining_fraction × 100`;
- an explicitly documented `used_percentage` is finite and within `0...100`,
  then converts once through `remainingPercent = 100 - usedPercentage`;
- used versus remaining is never inferred from range;
- malformed values are never clamped;
- missing is unavailable, not zero;
- independent buckets are never summed, split, or deduplicated by label.

No installed field name, container path, schema marker, reset type, or unlimited
representation is admitted by M6-G1. Those facts remain unavailable.

## 4. Rejected data

Discard before any shared model, cache, diagnostic, or durable record:

- email or account/organization identity;
- plan, billing, purchase, or payment data;
- login URL or browser state;
- cookie, token, Keychain, keyring, credential, or session material;
- conversation, message, prompt, response, task, tool, or project content;
- cwd, workspace, source-code, repository, branch, or VCS data;
- raw provider stdout/stderr or complete JSON;
- unknown free text and future unadmitted fields.

Unsafe labels are omitted rather than retained. If required quota meaning cannot
be separated from identity or private content, the source is `NO-GO`.

## 5. Schema and diagnostics

Ingress order for a later probe:

```text
byte caps
→ UTF-8
→ one JSON object
→ verified container
→ exact-key/type validation
→ semantic validation
→ sanitized projection
```

Unknown provider-envelope fields may be noticed only as bounded category
presence and are discarded in memory. A sanitized evidence packet accepts no
unknown keys. If no schema marker exists, the admitted contract binds to the
verified CLI version and observed structure; incompatible changes fail closed.

Diagnostics are fixed categories and counters only:

```text
notInstalled
unsupportedVersion
loginRequired
sessionExpired
browserLoginSideEffect
unsupportedAccountMode
enterpriseAmbiguous
providerUnavailable
timeout
malformedOutput
unsupportedSchema
noValidQuota
```

Raw provider messages never enter logs, crash diagnostics, packages, or Git.

## 6. Authentication

Current-device authentication is unobservable because the CLI is absent. It
must not be reported as logged out, expired, authenticated, or enterprise.

After setup:

- a bounded noninteractive provider `loginRequired` state may return
  `SETUP REQUIRED` and suspend reads;
- a routine quota command that opens or attempts browser login is
  `browserLoginSideEffect` and fails the automation source closed;
- API key, copied token, UMA OAuth, Keychain/keyring read, browser-cookie import,
  private endpoint, or identity-dependent interpretation is `NO-GO`.

UMA disconnect must eventually clear only UMA-owned normalized state and must
not sign the Human out or alter provider authentication.

## 7. Credits separation

M6-G1 classifies Credits as **`CREDITS DEFER`**. A later Credit channel requires
an exact structured current spendable balance and explicit native-unit
semantics. Credits never become percentage, never combine with model quota, and
never exceed the provider-wide two-channel limit.

## 8. Evidence retention

Durable records may retain only executable/provenance states, safe command
forms, public documentation links, field-name classifications, byte counts,
bounded bucket identifiers, semantic classifications, safe versions, reset
types, read accounting, and fixed outcomes.

Never retain exact live quota values, reset timestamps, Credit balances, raw
payload hashes, account identity, credentials, browser data, or screenshots.
Tests use visibly synthetic values only.

The single M6-G1 packet was owner-only (`0700` directory, `0600` regular file),
contained sanitized discovery classifications only, passed source/privacy/QA
review, was never copied into Git, and was deleted after review.

The only next task is **M6-SETUP-G1** after separate Founder authorization.
M6-G2 and all production runtime work remain locked.
