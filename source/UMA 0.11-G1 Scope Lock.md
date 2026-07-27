# UMA 0.11-G1 Scope Lock

Date: 2026-07-27

## Accepted baseline

- Workspace: `/Users/juliushe/Developer/UMA-0.11-MultiAgent`
- Branch: `codex/uma-0.11-multiagent`
- Starting commit: `dde272c947374658f9937c2cc96ff2b30902b4cb`
- Starting tree: `8d2783675054b5d7f3660b04597cec17c0cdf0f6`
- Marketing version/build preserved: `0.11 / 202607270002`
- Installed evidence is read-only:
  - `/Users/juliushe/Desktop/UMA_0.11.app`
  - `/Users/juliushe/Desktop/UMA_0.10.1.app`

The isolated worktree was created from the exact accepted baseline with a clean
worktree and empty index. The predecessor stability worktree is read-only.

## Governing contracts

UMA Logic 1.3.1 and Goal Mode 2.0 remain authoritative except where the
Founder explicitly overrides older Codex-centric layout and launch-discovery
behavior in this Goal.

Protected behavior:

- one host, one registered-provider catalog, one registry, one serialized
  store, and one shared presentation policy;
- provider-source admission remains current-read and fail-closed;
- shared main-panel/Desktop Assistant provider membership and roadmap order;
- WorkBuddy-only authenticated Account Web Sync exemption;
- WorkBuddy all-pool exact Decimal calculation and detailed formatting;
- WorkBuddy one-minute Auto Refresh with one timer, one WebView, and no
  overlapping reads;
- no manual WorkBuddy fallback into production surfaces;
- Codex local read, child ownership, recovery, consent, and privacy boundaries;
- one selected-window result shared by main panel, status item, Desktop
  Assistant, Tooltip, and VoiceOver;
- no credentials, cookies, tokens, authorization headers, raw account
  identity, or broad DOM/process data in the new settings record.

## Founder overrides

- The product header becomes provider-neutral (`UMA`).
- All admitted providers use one compact equal card shell.
- Cards are collapsed by default and have independent Details and Agent
  Settings actions.
- Show All and Hide All operate only on currently visible providers.
- Codex rate limits, Recent Tasks, Token Cost, and reset credits move under
  Codex Details.
- WorkBuddy-specific values and controls remain under WorkBuddy.
- Global Settings becomes one Global section plus one on-demand Agents list.
- Known-provider settings persist while inactive and apply before later
  monitoring.
- First-ever discovery is manual. After its first successful manual scan, Auto
  Search defaults on unless explicitly disabled. Later enabled launches perform
  exactly one coalesced registered-provider scan.
- The finite meaningful seven-day Codex window outranks an
  unlimited/unavailable/unchanged five-hour window. Five-hour data remains
  available as secondary detail.

## Architecture inventory

| Component | Current behavior | Required behavior | Minimal change | Risk | Focused tests |
|---|---|---|---|---|---|
| Main panel | Codex has a hero header and global cards; later providers use a compact row. | Neutral header and equal compact cards for every admitted provider. | Render all shared presentation cards through one shell; keep provider detail adapters outside `UsageStore`. | Recovery/connect actions are embedded in the old header. | Zero/one/many providers; parity; empty/recovery. |
| Provider cards | Percentage cards cannot expand; Credit cards have inline expansion. | Independent Details and Agent Settings for all providers. | Provider-ID expansion state and one settings destination route. | Dynamic height and one-contour ownership. | Independent expansion, transitions, accessibility. |
| Codex content | Rate limits, tasks, cost, and footer are global. | All Codex-specific content belongs to Codex Details. | Reuse existing components inside the Codex detail adapter. | Legacy source-string tests describe old ownership. | No global Codex cards; metric parity. |
| WorkBuddy content | Exact account Credit breakdown is already available in the additional-provider card. | Preserve exact values/provenance within WorkBuddy Details. | Reuse the current breakdown in the shared shell. | Two-decimal and privacy wording regression. | Exact values, no percent/fill without total. |
| Expansion | Stable provider-ID state exists; no global mode. | Independent state plus Show All / Hide All. | Add expand/collapse-all over visible IDs and clear removed IDs. | Stale hidden expansion state. | Show/Hide All, admission/removal, no reads. |
| Header | Title, plan, and state are Codex-specific. | Short neutral identity, admitted count, global actions. | Localized neutral title and global summary. | Status item and old localization assertions. | EN/zh-CN, accessibility, menu parity. |
| Settings | Flat screen contains card toggles and full WorkBuddy configuration. | Compact Global section and on-demand Agents list. | Provider-neutral destination and persistent preference coordinator. | WorkBuddy has multiple connector IDs but one settings identity. | Routes, inactive known provider, bounded scrolling. |
| Presentation | Roadmap order and selected window already live centrally. | Preserve as sole immutable presentation authority. | Extend central selection/card metadata only where required. | Cross-surface drift if a view chooses independently. | Main/Assistant/status/Tooltip/VoiceOver equality. |
| Discovery | Registered-only coalesced scanner exists; launch scan is unconditional when enabled. | First-ever manual; later launch scan only after persisted completion and when Auto Search is on. | Versioned discovery preferences gate the existing scanner. | Conflating discovery with WorkBuddy Auto Refresh. | Exact scan counts, OFF/manual, coalescing, no polling. |
| Persistence | Scattered global defaults and separate provider stores; no known-provider record. | Versioned bounded provider-neutral preferences without secrets. | Add typed records keyed by canonical provider identity; migrate only safe display settings. | Future-schema clobber and write churn. | Migration, corrupt/future fail-closed, no-op writes. |

## Edit scope

Authorized source scope:

- provider-neutral presentation, panel, settings, localization, and expansion
  models;
- a versioned Agent preference model/store and safe migration;
- `UsageStore` launch/manual discovery gating and known-provider updates;
- the central selected-window policy and status-item parity;
- focused G1 tests and required durable records.

Protected source scope:

- WorkBuddy extractor, WebKit data handling, pool aggregation, session store,
  and scheduler semantics;
- Codex app-server protocol and child-process ownership;
- Desktop Assistant geometry, tint, border, and accepted typography;
- version/build metadata and packaging behavior except for read-only audits.

## Persistence and migration plan

- Store one schema-versioned, size-bounded envelope with deterministic ordering.
- Persist `initialScanCompleted`, Auto Search value/explicitness, and safe
  per-provider records.
- Canonicalize multiple connector IDs for one provider (notably WorkBuddy) to a
  single settings identity.
- Provider payloads contain only safe display/monitoring settings. WorkBuddy
  consent, WebKit session, Auto Refresh, manual Credit records, and login
  metadata remain in their existing owners.
- Migrate existing 0.11 display preferences idempotently without deleting or
  resetting legacy keys.
- Save only on semantic change; reject corrupt, oversized, and future-schema
  records without rewriting them.

## Verification plan

- Focused provider-card, details, Settings, persistence/migration, discovery,
  selection, localization, accessibility, and parity suites.
- Existing Codex, WorkBuddy, Assistant, Auto Refresh, and privacy regressions.
- Full Swift test suite.
- Debug, Release, and strict-concurrency warnings-as-errors Release builds.
- `git diff --check`, privacy/schema/process/discovery audits, and static
  package-content contract audit.
- Exact staged-index audit by an independent reviewer before the one authorized
  local commit.

## Git authority and Completion Lock

After every blocking and major in-scope defect is closed, stage only exact
authorized files or hunks and create exactly one local commit:

`feat(uma): add compact multi-agent monitor architecture`

No amend, push, tag, release, notarization, deployment, publication, Desktop
application replacement, or candidate installation is authorized. Goal 2 must
not begin automatically.
