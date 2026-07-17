# M1A-G2 Scope Lock

## Authorized change set

- Provider-neutral `AgentUsageConnector` protocol, typed descriptor, normalized snapshot model, and deterministic registry.
- A bounded, allowlisted stale-snapshot store separate from the existing API-cost ledger.
- Codex app-server/local-metadata adapter and shared-store lifecycle migration, retaining the accepted G1 presentation contract.
- Focused connector-core tests, M1A-G1 regression migration, a unique-package helper, and this M1A-G2 evidence set.

## Non-goals locked out

- No Claude implementation, configuration, or discovery.
- No browser, credentials, cookies, Keychain, account mutation, logout, or raw account payload persistence.
- No visual redesign and no changes to unrelated M1/M1-G5 worktree edits.
- No push, tag, release, notarization, deployment, or M1A-G3 work.

## Data boundary

The registry accepts only typed aggregate channels. Connector persistence permits bounded provider labels, source versions, freshness, quota windows, aggregate account metrics, and aggregate local metrics. It rejects unsupported source tiers and excludes identities, paths, task names, timestamps, per-task token values, raw RPC, content, and credentials.
