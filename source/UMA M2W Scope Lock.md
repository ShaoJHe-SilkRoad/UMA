# UMA M2W-G1 Scope Lock

Date: 2026-07-24

## Baseline

- Workspace: `/Users/juliushe/Developer/UMA-M2W`
- Branch: `codex/uma-m2w`
- Starting HEAD: `bb10e827831ef23e832ffa75085f15d06bb813f3`
- Starting tree: `d032ba1c823487172422beb84f6c99a8cb543a9a`
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

Add a provider-neutral native Credit availability value alongside the existing percentage path. The change must provide strict integer validation, safe same-observation fraction derivation, distinct manual and official provenance, reusable shared-pool identity, capability-based shared formatting, Codable compatibility, and deterministic tests. Existing Codex percentage behavior remains unchanged.

## Planned edit scope

- `Sources/CodexUsageUI/Models/AgentAvailability.swift` — provider-neutral value, Credit balance, validation, scope, provenance, formatting primitives.
- `Sources/CodexUsageUI/Connectors/AgentUsageConnector.swift` — optional typed availability on a shared channel only.
- `Sources/CodexUsageUI/Models/SharedUsagePresentation.swift` — capability-based Credit presentation and centralized severity reuse.
- `Sources/CodexUsageUI/Stores/UsageStore.swift` — mechanical preservation of the shared presentation field only.
- `Tests/CodexUsageUITests/M2WG1CreditAvailabilityCoreTests.swift` — focused deterministic contract tests.
- This Scope Lock and `source/UMA M2W QA Issue Ledger.md`.

The connector snapshot-store schema remains unchanged during M2W-G1. Provider-specific manual persistence belongs to M2W-G2. No package-source-list edit is expected because SwiftPM discovers source and test files automatically.

## Final model decisions

- `AgentAvailabilityValue` is additive and does not replace accepted `SharedRemainingValue`.
- Percentages and Credits use validated value types; invalid source input produces a typed invalid value rather than a clamped balance.
- Credit arithmetic uses `Int64`, rejects negative values and overflow, and requires exact consistency when remaining, used, and total are all present.
- A normalized Credit fraction is available only from an explicit valid total or a same-balance derived total of `remaining + used`.
- `CreditPoolIdentity.buddyAISharedCredits` is the reusable WorkBuddy/CodeBuddy deduplication key; scope kind remains separately typed as personal shared, enterprise shared, unknown Buddy AI, or an unrelated non-Buddy scope.
- Credit pool identities are syntax-validated, bounded to 64 UTF-8 bytes, and revalidated during decoding. Every Buddy AI scope kind is invariant-locked to `buddyAI.sharedCredits`, while an unrelated scope must use a distinct pool identity.
- Manual confirmation and official structured observation are distinct typed provenance values. Manual source metadata is explicit, never implies connector health, and cannot be promoted to a live/fresh presentation.
- The shared presentation policy formats based on value capability. Credit values never receive a percent sign.
- A newer manual confirmation replaces an older manual Credit value even while the provider channel remains unavailable; a later missing/failed observation retains the last valid value.
- Existing selected-window, Maximum Decrement, percentage stale retention, and percentage rendering remain untouched.

## Protected modules and behavior

- Codex transport, app-server session, refresh cadence, and connector behavior.
- `UsageStore` provider-neutral ownership; no provider-name branch.
- Main-panel and Desktop Assistant view hierarchy and compact Codex output.
- Selected-window policy, Maximum Decrement, reset/refill handling, stale last-valid retention, and percentage thresholds.
- Settings, installed applications, package/release scripts, and all WorkBuddy source/UI paths.
- Historical M3 and M3W records.

## Compatibility requirements

- Finite 0–100 percentage, unlimited, unavailable, invalid-source rejection, stale retention, and centralized thresholds remain accepted.
- Credits remain absolute Credits and never gain a `%` suffix.
- A fraction exists only for validated, same-balance `remaining/total` or `remaining/(remaining+used)` data.
- Missing totals never fabricate a fraction.
- Manual provenance is not represented as a healthy live provider connection.
- Existing schema-zero/schema-one Codex snapshots remain readable; malformed identities, mismatched Buddy scopes, malformed Credit records, and unknown outer or nested Credit schemas fail closed.
- No old percentage record is converted into Credits.

## Privacy and provider boundary

- No WorkBuddy account, application, usage page, login state, browser, UI automation, OCR, cookies, credentials, Keychain, auth database, network traffic, or provider payload access.
- No WorkBuddy connector, persistence workflow, Settings, main-panel row, or Assistant row.
- No Claude, Manus, OneDrive, or another provider access.
- No new network dependency, provider process, file observer, or polling timer.
- No account identity, raw provider payload, local path, task name, or credential field.

## Verification plan

- Focused Credit validation, fraction, severity, scope, provenance, formatter, presentation, and Codable tests.
- Existing percentage boundary, stale retention, selected-window, main-panel, and Assistant contract suites.
- Existing connector snapshot migration and corruption tests.
- Full Swift test suite.
- Debug, Release, and strict-concurrency warnings-as-errors builds.
- Diff checks, formatting/source hygiene, privacy scan, dependency audit, generated-artifact audit, and package-source inventory.
- Independent architecture/privacy review before staging.
- Exact staged-index audit before the authorized local commit.

## Delivery authority

After all required checks pass, exact-file or exact-hunk staging and one local commit are authorized:

`feat(core): add credit availability value model`

No amend, fetch, push, tag, release, notarization, deployment, or publication is authorized.

## Completion Lock

Stop after the audited local commit and final clean worktree/index verification. Do not begin M2W-G2 automatically.
