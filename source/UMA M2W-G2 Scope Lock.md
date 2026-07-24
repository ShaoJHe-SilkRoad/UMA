# UMA M2W-G2 Scope Lock

Date: 2026-07-24

## Baseline

- Workspace: `/Users/juliushe/Developer/UMA-M2W`
- Branch: `codex/uma-m2w`
- Starting HEAD: `2a0d648abeea2f2a47ab16cae227a3b6756dff8b`
- Starting tree: `978537023da5065c17f51222a994185912aa6869`
- Starting worktree: clean
- Starting index: empty

## Active governing authority

- `M2W_Plan.md` version 1.0 — SHA-256 `02d30be28aa0521457ae4b42b3f0523ae1b918646330dda2be4d5f76b15a3556`
- `M2W_Goals.md` version 1.0 — SHA-256 `9508d2910a91db3fd3eb334452da273f53b4d1bbfeb4ec134f99ba5a578c4d10`
- `M2W_WorkBuddy_Credit_Research.md` version 1.0 — SHA-256 `5c8ed07a2556ee47eb35cbd019fde880007d4d0ab6d3d9913aa1016704ece444`
- `UMA_Logic_1.3.md` — SHA-256 `c73cde523d92671213e4aa00cb93d01f6e4f9258ac8268891ea76dea61b2d064`
- `Goal_Mode_2.0.md` — SHA-256 `9035f2574938752f40a50346c33bcc32db33c70526989fc14825d51ff1f6d5e7`
- `Dev_Default_2.1.md` — SHA-256 `d2997e2039ef2418c98bce66b516e2a9f734394b338abd383fc92f9e6260e598`

## Locked result

Add one deterministic, local-only WorkBuddy manual Credit source, one versioned privacy-safe record, one passive connector, and a bounded Settings workflow. Reuse the accepted M2W-G1 `CreditBalance`, `CreditScope`, `AvailabilityProvenance`, and `buddyAI.sharedCredits` types. WorkBuddy remains hidden from the detailed main panel and Desktop Assistant until M2W-G3.

## Architecture lock

```text
WorkBuddy Settings
→ ManualWorkBuddyAvailabilitySource
→ WorkBuddyAvailabilityConnector
→ AgentConnectorRegistry
→ UsageStore provider snapshot
→ hidden provider-neutral presentation gate
```

- Connector ID: `workbuddy.manualAvailability`
- Pool identity: `buddyAI.sharedCredits`
- Provider display: `WorkBuddy`
- Scope copy: `Shared with CodeBuddy`
- Source mode: `Manual confirmation`
- One source instance is shared by Settings and the one connector instance.
- The connector is passive, source-owned, never connected, never fresh, and excluded from generic connector snapshot persistence.
- Shared Refresh continues to target the primary Codex connector only.
- M2W-G3 activates visible provider surfaces by removing the connector's provider-neutral hidden-presentation capability after its own acceptance work.

## Persistence contract

- Logical schema: version 1.
- Path: `~/Library/Application Support/CodexUsageMonitor/workbuddy-manual-availability.json`.
- Atomic primary and recovery-copy writes, sorted keys, 8 KiB maximum, duplicate suppression, directory mode `0700`, record mode `0600`.
- Allowlist: schema version, enabled state, stable connector/source identity, validated Credit balance, scope enum, tier enum, optional expiry, confirmation time, and manual source mode.
- Clear removes only the exact primary and recovery-copy record.
- Disable preserves the valid observation and confirmation time; re-enable republishes it unchanged.
- Future schema and invalid/corrupt values fail closed and never become zero.

## Settings and accessibility lock

- One collapsed WorkBuddy disclosure inside the existing scrolling Settings card.
- Enable, fixed manual source, scope, tier, absolute/used/total entry, optional expiry, explicit tier suggestion acceptance, preview, save, confirm unchanged, clear confirmation, and exact official-page action.
- Preview is draft-only.
- English and Simplified Chinese copy, stable labels/hints, visible validation, keyboard-native controls, and localized action announcements.
- Existing material, Light/Dark, contrast/transparency/motion behavior, panel geometry, and unrelated Settings controls remain unchanged.

## Privacy and provider boundary

- No WorkBuddy account, application, process, file, database, cache, log, browser content, login state, provider payload, network traffic, OCR, cookies, credentials, Keychain, or auth-database access.
- No OneDrive, Claude, or Manus access.
- The only URL action is the explicit-click HTTPS destination `https://www.workbuddy.cn/docs/workbuddy/Usage`; deterministic injection tests are preferred and no page content is read.
- No background polling, provider process, file observer, browser reader, or network client exists in the G2 source.

## Protected behavior

- Codex transport, provider operations, percentage semantics, selected-window policy, Maximum Decrement, refresh cadence, and persistence.
- Existing detailed main-panel and Desktop Assistant provider rows.
- Installed applications, predecessor repositories, governing sources, packaging/release behavior, and remote state.

## Verification and delivery

- Focused validation, lifecycle, persistence/schema, registry/visibility, Refresh, Settings/localization/accessibility, privacy, and exact-URL suites.
- Full test suite; Debug, Release, and strict-concurrency warnings-as-errors builds.
- Diff, dependency, privacy, persisted-field, generated-artifact, and package-content audits.
- Independent source/privacy review and independent staged-index review.
- Exact-file or exact-hunk staging and one authorized local commit:

`feat(workbuddy): add manual credit availability source`

No amend, fetch, push, tag, release, notarization, deployment, or publication.

## Completion Lock

Stop after the audited local commit and final clean worktree/index verification. Do not begin M2W-G3 automatically.
