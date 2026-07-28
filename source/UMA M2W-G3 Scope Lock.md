# UMA M2W-G3 Scope Lock

Date: 2026-07-24

## Baseline

- Workspace: `/Users/juliushe/Developer/UMA-M2W`
- Branch: `codex/uma-m2w`
- Starting HEAD: `42d97e68f4c49abab07f04c4dbe7e1d2ef6a38aa`
- Starting tree: `a54b2c6b25f9a03b0f3998abf1b08e3f872cc623`
- Starting index: empty
- Preserved starting work: five authorized unstaged G3 groundwork files

## Active governing authority

- `M2W_Plan.md` version 1.0 — SHA-256 `02d30be28aa0521457ae4b42b3f0523ae1b918646330dda2be4d5f76b15a3556`
- `M2W_Goals.md` version 1.0 — SHA-256 `9508d2910a91db3fd3eb334452da273f53b4d1bbfeb4ec134f99ba5a578c4d10`
- `M2W_WorkBuddy_Credit_Research.md` version 1.0 — SHA-256 `5c8ed07a2556ee47eb35cbd019fde880007d4d0ab6d3d9913aa1016704ece444`
- `UMA_Logic_1.3.md` — SHA-256 `c73cde523d92671213e4aa00cb93d01f6e4f9258ac8268891ea76dea61b2d064`
- `Goal_Mode_2.0.md` — SHA-256 `9035f2574938752f40a50346c33bcc32db33c70526989fc14825d51ff1f6d5e7`
- `Dev_Default_2.1.md` — SHA-256 `d2997e2039ef2418c98bce66b516e2a9f734394b338abd383fc92f9e6260e598`

## Locked result

Show WorkBuddy as the second provider in the UMA main panel using the accepted
manual Credit source and shared presentation model. Keep the Desktop Assistant
Codex-only. The main-panel card provides a compact balance summary, explicit
manual provenance, shared-pool scope, localized accessibility, deterministic
expanded details, and routes mutations through the accepted Settings model.

Required visibility:

```text
Main panel: Codex → WorkBuddy
Desktop Assistant: Codex only
```

## Planned edit scope

- Existing five groundwork files:
  - `Sources/CodexUsageMonitor/App/StatusBarController.swift`
  - `Sources/CodexUsageUI/Connectors/AgentUsageConnector.swift`
  - `Sources/CodexUsageUI/Connectors/WorkBuddyAvailabilityConnector.swift`
  - `Sources/CodexUsageUI/Models/SharedUsagePresentation.swift`
  - `Sources/CodexUsageUI/Stores/UsageStore.swift`
- Bounded main-panel presentation, localization, view composition, Settings
  routing, deterministic preview-renderer, and focused test files.
- This Scope Lock and `source/UMA M2W QA Issue Ledger.md`.

## Final model and UI decisions

- The former global provider-surface hiding capability is replaced for
  WorkBuddy by a provider-neutral Desktop-Assistant-only exclusion capability.
- Main-panel ordering follows connector order; no provider-name branch is added
  to `UsageStore`.
- Disabled WorkBuddy stays absent. Configured, unconfigured, invalid, and
  unavailable enabled states have deterministic main-panel presentations.
- A new manual lifecycle field is additive to shared presentation and prevents
  unconfigured or invalid states from retaining a former configured balance.
- The compact value uses the accepted Credit formatter and never gains a
  percent sign.
- A proportional bar appears only when the shared presentation supplies a
  validated normalized fraction. Absolute-only Credits do not fabricate a bar.
- Severity reuses the accepted centralized availability thresholds.
- Expansion is keyed by stable connector ID and respects Reduce Motion.
- Update routes to the existing WorkBuddy Settings section. Open, confirm, and
  two-step clear reuse the accepted injected Settings model actions.
- The existing safe SF Symbol is used for provider identity; no external asset
  or dependency is introduced.
- Panel overflow is handled by native vertical scrolling inside the accepted
  maximum geometry.

## Protected behavior

- Codex connector, account reads, refresh cadence, selected-window policy,
  Maximum Decrement, status item, and accepted main-panel cards.
- Desktop Assistant layout, density, visuals, and Codex-only projection.
- WorkBuddy source, validation, persistence, no-op shared Refresh, and
  confirmation semantics accepted by M2W-G2.
- Existing glass, exterior contour, typography system, and panel geometry.
- Regular and Minimalist Assistant behavior.

## Privacy and provider boundary

- Synthetic/manual records only for task-owned UI validation.
- No WorkBuddy account, provider, application, browser content, private file,
  database, process, memory, credential, Keychain, OCR, or network access.
- No automatic WorkBuddy synchronization and no claim that manual data is live.
- No Claude, Manus, OneDrive, or another provider.
- No M2W Desktop Assistant integration; that remains reserved for M2WA-G1.

## Verification plan

- Focused lifecycle, visibility, ordering, formatting, severity, localization,
  accessibility, routing, and privacy-contract tests.
- M2W-G1 and M2W-G2 regression suites, then the full Swift test suite.
- Debug, Release, and strict-concurrency warnings-as-errors builds.
- Deterministic task-owned renderer matrix for collapsed/expanded, configured,
  absolute-only, unconfigured, invalid, exhausted, EN/zh-CN, Light/Dark,
  Reduce Transparency, Increase Contrast, and Reduce Motion-relevant states.
- Task-owned candidate inspection with synthetic/manual records only.
- Independent architecture/privacy, QA, and staged-index reviews.

## Delivery authority

After all checks pass, exact-file or exact-hunk staging and one local commit are
authorized:

`feat(workbuddy): show manual credit availability`

No amend, fetch, push, tag, release, notarization, deployment, or publication is
authorized.

## Completion Lock

Stop after the audited local commit and final clean worktree/index verification.
Do not begin M2WDBG-G1 automatically.
