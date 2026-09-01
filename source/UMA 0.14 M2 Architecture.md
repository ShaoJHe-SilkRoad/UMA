# UMA 0.14 M2 Architecture

Task: `GN-UMA014-M2-01`

Baseline: `4c03599c279e19e53ddc94e3acf1534db2bf54a5`

## Product-state boundary

M2 establishes one directional publication path:

```text
Codex / Claude / WorkBuddy / Antigravity connectors
→ AgentConnectorRegistryPublication
→ one UsageStore subscription
→ ProviderProductInventory
→ Main / Quick Panel / Desktop Assistant / future Settings
```

Connectors remain the owners of acquisition, authorization, refresh, cache, and privacy behavior. `ProviderProductStatePolicy` is a strict projection from sanitized connector snapshots and admission records. It does not retain connector snapshots, arbitrary provider strings, protocol receipts, paths, identities, credentials, or raw payloads.

`UsageMonitorRuntime` and `UsageStore` remain singletons at the application composition boundary. Windows and panels never construct provider runtimes.

## Coherent publication

`AgentConnectorRegistryPublication` contains one monotonically increasing revision, the ordered sanitized snapshots, and the matching admission set. The registry publishes that envelope atomically.

Each subscriber receives:

- an independent UUID-owned stream;
- an immediate replay of the current envelope;
- a newest-value buffer;
- exact, idempotent detach behavior.

Terminating one subscriber cannot remove another subscriber. `UsageStore` owns exactly one registry subscription and reduces each coherent revision once.

## Surface projections

- Main Overview reads `productInventory.overviewProviders`.
- Main Providers reads the complete four-provider inventory.
- Quick Panel filters its accepted legacy card rendering through the same Overview eligibility and uses the product-level active-agent count.
- Desktop Assistant filters its accepted card rendering through `productInventory.assistantProviders` and observes direct published values rather than pre-change `objectWillChange` callbacks.
- The status item reads the Codex primary remaining value from the product inventory.
- Future Settings receives the same inventory boundary; M2 does not perform the M4 Settings redesign.

The existing shared card renderer remains a compatibility projection during M2. Selection and Maximum Decrement continue to be owned by `SharedUsagePresentationPolicy`; surfaces do not recalculate quota selection.

## Provider adapters

- Codex: provider-reported account windows become exact remaining percentages when valid.
- Claude: exact Local Smart or Accuracy Sync observations remain exact; authorized local estimates retain estimated precision and the `≈` mark; one-shot Accuracy Sync remains an available action.
- WorkBuddy: native credit balances remain credits. They become comparison-eligible only when the existing account-web result supplies a validated same-scope denominator.
- Google Antigravity: official CLI quota buckets become remaining percentage windows without changing CLI acquisition.

Cursor and Kimi have no catalog entry and remain unsupported.

## Protected boundaries

M2 changes no provider acquisition, browser, native-host, authentication, estimator, quota math, persistence allowlist, signing, or release code. Claude Accuracy Sync remains explicit and one-shot. No automatic Safari polling is introduced.
