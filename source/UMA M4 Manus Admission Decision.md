# UMA M4 Manus Admission Decision

Status: M4-G1 decision
Date: 2026-07-28
Decision: **CONDITIONAL GO**

## Decision statement

**CONDITIONAL GO — OFFICIAL MANUS CREDIT SOURCE ADMITTED FOR BOUNDED
IMPLEMENTATION; HUMAN LIVE BALANCE PROOF REMAINS REQUIRED.**

Current official documentation and the UMA architecture establish a secure,
read-only implementation path for:

```text
GET https://api.manus.ai/v2/usage.availableCredits
```

using the required `x-manus-api-key` header and
`data.total_credits` as the only authoritative current balance.

This is not a full GO because M4-G1 intentionally used no real API key,
performed no authenticated provider read, and made no same-time Human balance
comparison. The official documentation also does not publish an
endpoint-specific rate limit for this method. Those facts do not block a
bounded implementation, but they prevent final live acceptance.

## Admission basis

The source is admitted because:

- API v2 is current and the exact host, method, and path are public;
- the endpoint is read-only and no-task;
- endpoint authentication is explicitly API-key-only; OAuth is not accepted;
- `total_credits` is documented as actual spendable balance;
- personal and team-key scope is documented;
- all current fields can be classified without inferring private data;
- UMA can keep the full-account API key in a device-bound Keychain item;
- exact route, redirect, timeout, body-size, cadence, and decoder boundaries
  can be enforced locally;
- UMA's provider-neutral Credit model can represent the value exactly;
- no SDK, browser automation, Hook, local Manus.app process, task history, or
  private implementation inspection is required.

## M4-G2 implementation lock

M4-G2 may implement only:

- one Keychain item owned by UMA;
- one exact `usage.availableCredits` URLSession client;
- one strict decoder for the admitted schema;
- one provider-neutral Manus Credit connector;
- one-in-flight/coalesced launch, manual refresh, and bounded cadence;
- main-panel/Desktop Assistant parity after a current valid read;
- Official API provenance, Settings controls, and disconnect;
- focused tests and package/privacy proof.

M4-G2 must not:

- use an SDK or platform package to obtain this value;
- call `task.*`, `usage.list`, team logs/statistics, or any identity endpoint;
- follow redirects;
- persist or log the key, headers, body, raw provider error, request ID,
  identity, or decoded snapshot;
- reconstruct balance from component fields;
- treat quotas as remaining balance or percentage denominators;
- restore a stale Manus balance after launch;
- access Manus.app, browser sessions, cookies, credentials, tasks, or history;
- make a live authenticated request without the later explicit Human gate.

## Live acceptance lock

Production acceptance requires all of the following:

1. Human-created dedicated key in official Manus Settings.
2. UMA Keychain save and verify with no plaintext persistence.
3. One current successful read of the exact admitted endpoint.
4. Same-time numeric comparison of official balance and UMA.
5. Main-panel/Desktop Assistant parity and Official API provenance.
6. Manual Refresh coalescing and cadence validation.
7. Disconnect deletion and immediate surface withdrawal.
8. Package, logs, diagnostics, preferences, and Git remain secret-free.

If the endpoint returns a materially different schema, requires an undisclosed
permission, or cannot be reconciled with the official balance, the verdict
returns to NO-GO pending a new admission decision. A login or key alone does
not convert this conditional verdict to GO.

## Decision owner and next gate

M4-G1 admits the source contract only. It does not implement the production
connector. M4-G2 may begin after this commit. The Human-controlled live proof
belongs to the later live-validation gate defined by the M4 governing plan.
