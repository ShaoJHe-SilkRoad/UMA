# UMA WorkBuddy Official API Migration Handoff

Version: 1.0
Date: 2026-07-25
Goal: M2WACCOUNT-G1

## Current admitted source

M2WACCOUNT-G1 admits a Human-authenticated, UMA-owned WebKit read of the
official Plan and Usage page. The implementation extracts a narrow allowlist of
Credit values from the public account page and validates canonical Decimal
strings before admission.

## Migration trigger

Replace the page extractor only when WorkBuddy publishes an official,
third-party-supported Credits API, SDK, event, getter, or extension contract
that:

- identifies the shared Credit scope;
- supplies exact remaining Credits and, when available, exact used/total;
- documents authentication and revocation;
- permits read-only third-party use by UMA;
- has a stable version and failure contract.

An undocumented endpoint, private application interface, copied credential,
browser token, or reverse-engineered protocol is not an admitted migration
source.

## Invariants to preserve

- explicit Experimental consent until Founder reclassifies the source;
- WorkBuddy-only exemption; no automatic expansion to another provider;
- exact Decimal strings and fail-closed schema validation;
- one shared admission set for main panel and Desktop Assistant;
- immediate withdrawal on authentication expiry or failed current read;
- no manual fallback or account-web snapshot restore;
- no identity, cookie, token, credential, full-page, task, or conversation data;
- launch/Manual Refresh/Sync Now/Check Again cadence with no polling;
- Disconnect revokes only UMA-owned WorkBuddy state.

## Migration proof

Any future API migration requires public-contract evidence, deterministic
fixtures, parity against the official Plan and Usage page, privacy review,
failure/revocation tests, package audit, and a new Human-controlled same-time
balance comparison.
