# UMA Logic 1.3 WorkBuddy Account Web Exemption

Version: 1.0
Date: 2026-07-25
Goal: M2WACCOUNT-G1

## Founder override

For WorkBuddy only, the accepted production admission path is:

```text
Founder consent
→ authenticated UMA-owned official WorkBuddy web session
→ current successful read of official Plan and Usage
→ validated native Credits
→ WorkBuddy appears in the main panel and Desktop Assistant
```

WorkBuddy.app running state, a local Hook, local IPC, and a local structured
Credits source are not admission conditions for this path.

## Provider-neutral boundary

The provider-neutral model adds:

- source class `authenticatedAccountWeb`;
- authentication method `umaOwnedAuthenticatedAccountWebSession`;
- read contract `currentAuthenticatedAccountWebRead`.

The generalized scanner accepts only the exact matching pairs:

- `admittedStructuredLocal` + `currentStructuredLocalRead`; or
- `authenticatedAccountWeb` + `currentAuthenticatedAccountWebRead`.

This does not relax unsupported, manual-only, or mismatched connectors. All
other providers remain governed by the local-live admission contract.

## WorkBuddy behavior

- Account-web source ID: `workbuddy.accountWebCredits`.
- A current successful read admits both provider surfaces.
- WorkBuddy.app may be absent or closed.
- Failure, expiry, or Disconnect withdraws both surfaces immediately.
- Account-web snapshots are never restored.
- The legacy manual source remains manual-only and cannot become a fallback.
- Account-web reads are restricted to launch, Manual Refresh, Sync Now,
  Check Again, and the accepted WorkBuddy-owned default-on Auto Refresh lane.
  Scheduled reads occur no sooner than 60 seconds after the prior read
  completes, with one timer, one WebView, one in-flight read, no catch-up, and
  no view- or Assistant-triggered multiplication.

## Superseded WorkBuddy rule

The M2WLOGIN-G1 conclusion that WorkBuddy login assistance cannot admit a
provider is superseded only for this account-web source. Its official-app login
implementation and all historical records remain unchanged.
