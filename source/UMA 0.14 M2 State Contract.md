# UMA 0.14 M2 State Contract

Task: `GN-UMA014-M2-01`

## Canonical inventory

`ProviderProductInventory` contains exactly four stable products in this order:

1. Codex
2. Claude
3. WorkBuddy
4. Google Antigravity

The Providers surface always receives all four. Overview receives products that are active, have current or retained truth, are detected/configured, or require action. A provider with meaningful setup or failure state does not silently disappear.

## Orthogonal axes

Each provider exposes separate typed axes:

- precision: exact, estimated, unavailable;
- freshness: fresh, cached, stale, unavailable;
- availability: available, setup required, disabled, unavailable, unsupported;
- connection: connected, transitional, authentication required, disconnected, unavailable, failed;
- health: healthy, degraded, needs attention, error.

These axes are not inferred from one another. For example, an exact retained observation may be stale, and an authentication requirement is not an active provider.

Normal product state uses a closed diagnostic taxonomy. Request IDs, paths, bundle generations, protocol stages, raw provider messages, and arbitrary connector strings are not representable.

## Remaining and precision semantics

- Percentages always mean remaining.
- Exact `82` renders as `82%`.
- Estimated `82` renders as `≈82%`.
- Missing, malformed, failed, and unsupported values render as unavailable, never `0%`.
- Unlimited is not a comparable zero or percentage.
- Native credits stay in their native unit.

## Primary and limiting quotas

The provider primary quota preserves the accepted shared-selection and Maximum Decrement behavior.

The global limiting factor considers only finite, valid, current or cached normalized remaining percentages. It excludes:

- stale or unavailable values;
- missing or malformed values;
- unlimited values;
- native credits without a validated denominator.

The lowest eligible remaining percentage wins, with stable provider/window order as the deterministic tie breaker. Action attention is a separate result and can outrank numeric urgency in M3 without corrupting the numeric limiting factor.

## Actions and active agents

Available actions and required action are distinct. Authentication, retry, monitoring enablement, refresh, Settings, and Claude Accuracy Sync are typed product actions.

A provider is active only when monitoring is enabled and its connection is connected or transitional. Setup-required, disabled, unavailable, unsupported, and failed products are not counted active. Visibility never defines activity.

The product inventory owns the active-agent count. More than four active agents activates the existing automatic full Minimalist behavior; M2 does not redesign Assistant density.

## Privacy projection

The adapter allowlist retains only stable product identity, bounded locally resolved labels, sanitized quota values, reset timestamps, precision, freshness, typed state/actions, bounded source classification, and content-free diagnostics.

It excludes identities, paths, URLs, credentials, cookies, tokens, provider payloads, raw DOM, protocol receipts, task/session content, connector source strings, reconciliation internals, process metadata, and unrestricted persistence. The product model is not `Codable` and is not a new cache.
