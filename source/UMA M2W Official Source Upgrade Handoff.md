# UMA M2W Official Source Upgrade Handoff

Date: 2026-07-25

## Status

`M2W-LIVE-G1` is dormant. This record does not authorize it.

The accepted WorkBuddy source remains manual user confirmation through:

```text
Manual WorkBuddy Settings
→ ManualWorkBuddyAvailabilitySource
→ WorkBuddyAvailabilityConnector
→ AgentConnectorRegistry
→ one UsageStore
→ SharedUsagePresentationPolicy
→ one immutable AgentCardViewModel
├── main panel
└── Desktop Assistant
```

Automatic structured WorkBuddy synchronization remains `NO-GO`. No WorkBuddy
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

Until those gates pass, the manual source remains the only accepted source and
the application must not attempt background discovery or synchronization.

## Provider roadmap boundary

Current:

```text
Codex → WorkBuddy
```

Future admitted order:

```text
Codex → Claude Code → WorkBuddy → Manus → Cursor → Kimi+ → Doubao / later approved providers
```

This is a stable identity-priority roadmap, not a generic “WorkBuddy always
last” rule. This handoff does not implement or authorize Claude Code, Manus,
Cursor, Kimi, Doubao, or another provider.
