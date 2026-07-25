# UMA M2W Official Source Upgrade Handoff

Date: 2026-07-25

## Status

`M2W-LIVE-G1` is dormant. This record does not authorize it.

Manual user confirmation remains retained compatibility infrastructure through:

```text
Manual WorkBuddy Settings
→ ManualWorkBuddyAvailabilitySource
→ WorkBuddyAvailabilityConnector
→ AgentConnectorRegistry
→ Settings and migration compatibility
```

It is classified `manualOnly` and is hidden from production provider surfaces.
Automatic structured WorkBuddy synchronization remains `NO-GO`. The trusted
5.3.5 Hook recheck at commit
`f59f8d5dc7773cd40aad1eeae49fc01e22413f46` admitted no public Credits
contract, event, or getter and is read-only evidence. No WorkBuddy
account, provider, application, browser content, private file, database,
process, memory, credential, Keychain, OCR, or network source was inspected or
used by M2W.

## Contracts an official source must preserve

- Stable provider identity: `workbuddy.manualAvailability` until a separately
  approved migration contract explicitly changes it.
- Stable shared-pool identity: `buddyAI.sharedCredits`.
- WorkBuddy and CodeBuddy must never display as two independent balances for
  the same shared pool.
- Native Credit values must remain Credits. They must never gain a percent sign
  or proportional tint without a valid same-observation total.
- Remaining, used, active total, scope, tier, expiry, provenance, and
  observation time must remain typed and versioned.
- A structured official provenance must not be labeled as manual, and a manual
  record must never be labeled live.
- The main panel and Desktop Assistant must continue to consume one shared
  immutable presentation rather than independently reading or calculating
  provider data.
- Shared Refresh must have one owner and must not multiply provider reads,
  connector instances, processes, timers, observers, stores, or writes.
- Codex behavior, ownership, and presentation must remain independent.

## Admission evidence required before activation

A future Founder-authorized official-source goal must establish:

1. a documented, stable, permitted structured source;
2. explicit authorization and privacy boundaries;
3. schema, freshness, error, rate-limit, and authentication behavior;
4. exact Credit and shared-pool semantics;
5. deterministic offline fixtures and fail-closed parsing;
6. provider-read, cadence, latency, recovery, and resource bounds;
7. a migration and rollback path that does not destroy the accepted manual
   record;
8. main/Assistant semantic parity and manual-versus-official provenance
   distinction;
9. package, privacy, fixture-isolation, and commit-exact acceptance;
10. a separate Founder decision to activate the source.

Until those gates pass, WorkBuddy remains hidden. Its manual source remains
preserved but cannot surface-admit a provider. The application must not attempt
background discovery or synchronization.

## Provider roadmap boundary

Current production-visible order:

```text
Codex, only when currently admitted
```

Future admitted order:

```text
Codex → Claude Code → WorkBuddy → Manus → Cursor → Kimi+ → Doubao / later approved providers
```

This is a stable identity-priority roadmap, not a generic “WorkBuddy always
last” rule. This handoff does not implement or authorize Claude Code, Manus,
Cursor, Kimi, Doubao, or another provider.
