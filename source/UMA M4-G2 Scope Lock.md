# UMA M4-G2 Scope Lock

Status: historical prototype scope — retired by M4-N; do not execute
Date: 2026-07-28

## Accepted predecessor

- workspace: `/Users/juliushe/Developer/UMA-M4-Manus`
- branch: `codex/uma-m4-manus`
- predecessor commit:
  `71a43b93a26257b048b10e67d9ea4c237d1a5c79`
- predecessor subject: `docs(m4): admit Manus Credit source`

## Goal

Implement the previously admitted Manus official API v2 current-Credit
source without using a real API key or making an authenticated live request.
M4-G2 owns secure credential storage, the narrow client and decoder, connector
admission, bounded refresh, Settings, fixture-only verification, and one
commit-exact offline package.

## Locked runtime contract

The one admitted request is:

```text
GET https://api.manus.ai/v2/usage.availableCredits
x-manus-api-key: <transient Keychain value>
```

There is no request body, query, redirect, retry, task endpoint, task-history
endpoint, `usage.list`, browser source, SDK source, or local Manus-app source.
Only a fresh successful current read admits Manus. Any credential, transport,
HTTP, schema, or cancellation failure removes the current remote balance from
provider surfaces.

The exact Keychain item is a generic password:

```text
service: com.kevinchen.CodexUsageMonitor.manus-api-v2
account: primary
data-protection keychain: true
accessibility: WhenUnlockedThisDeviceOnly
synchronizable: false
access group: absent
```

The key exists only in that item and transient request memory. Settings use a
SecureField, clear the draft immediately after Save and Verify, never reveal a
saved key, and persist only a non-secret Auto Refresh preference.

## Data and presentation contract

`data.total_credits` is the sole authoritative exact remaining value.
Documented components remain provider-neutral details and never need to sum to
the primary. No percentage, total, or invented proportional fill is derived.
Unknown JSON fields are ignored; missing, negative, fractional, string, and
out-of-Int32-range Credit values fail closed. Reset time accepts documented
zero or plausible Unix seconds only.

Manus uses the stable provider order after WorkBuddy and before Cursor. M4-G2
admits a fresh Manus value to the main-panel shared presentation. It remains
explicitly hidden from Desktop Assistant until the separately gated M4A work.

## Refresh and lifecycle contract

- read on a shared launch scan only when a credential is configured;
- shared Manual Refresh, Settings Sync Now, and optional Auto Refresh;
- one provider read in flight;
- overlap coalesces into at most one follow-up;
- optional cadence is no faster than 60 seconds after completion;
- no catch-up burst or automatic retry;
- authentication failure suspends cadence;
- disconnect cancels the owned task/timer, deletes only the exact Manus item,
  clears the current snapshot, and withdraws Manus.

## Explicit exclusions

- Founder's API key or any real credential;
- authenticated Manus request or claimed live balance;
- Manus tasks, history, account identity, cookies, browser state, local app,
  or private files;
- Codex or WorkBuddy behavior changes beyond provider-neutral compatibility;
- Desktop Assistant Manus integration;
- Desktop installation or replacement;
- M4-G3, push, merge, tag, release, notarization, deployment, or publication.

## Delivery

- local commit subject:
  `feat(manus): add secure Credit source`
- package:
  `/private/tmp/uma-m4-g2-final-<short-commit>/UMA.app`
- required live status:
  `LIVE MANUS BALANCE NOT YET VALIDATED`
