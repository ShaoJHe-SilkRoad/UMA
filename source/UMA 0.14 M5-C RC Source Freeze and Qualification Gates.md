# UMA 0.14 M5-C — RC Source Freeze and Qualification Gates

Status: engineering repairs and deterministic regression converged; clean RC construction follows independent staged review and local commit. M5-C is not PASS until the independent live/OS qualification gates are complete. The durable RC manifest and evidence packet record final commit/tree/package/hashes without a self-referential commit claim in this document.

## Baseline and scope

- Canonical worktree: `/Volumes/HE/DEV/UMA/Worktrees/UMA-0.14-Surface-Rebuild`.
- Branch: `codex/uma-0.14-surface-rebuild`.
- Accepted M5-B commit: `4c4369cfeb22c6487c459244bda1c68028a2be5b`.
- Accepted M5-B tree: `831f81c569a965af4140899a51b33eb2897c4cce`.
- Initial worktree CLEAN / index EMPTY. DEV_APFS verified by current disk metadata: APFS, `/Volumes/HE/DEV`, writable, ownership enabled (`GlobalPermissionsEnabled`).
- M5-A and M5-B closeouts and evidence reconcile with this baseline. Their live/OS/release limitations remain independent gates.
- Current Founder START M5-C is the execution authority. The earlier Downloads plan remains reference sequencing; it does not grant production replacement, live accounts, signing or publication.

Accepted UI/compositing, provider lifecycle, remaining quota semantics, algorithms, ApplicationPreferences, Codex/Claude-only active product admission and inert ThreadOS are unchanged. Frozen 0.13 source and protected applications are not development targets.

## Bounded engineering changes

1. Supported snapshot input with unknown JSON fields could be copied verbatim to a new backup. Backup rotation now checks the entire field structure against the same-schema typed projection. Unknown fields trigger canonical projection; legitimate legacy bytes remain unchanged despite Set ordering or numeric round-trip differences. Existing future-schema preservation, stale restoration, original timestamps and snapshot path validation remain intact.
2. The cost ledger could copy unknown fields to a backup or recovered main, and overwrite future-schema files. New backup/recovery writes now encode the typed ledger; unsupported main or backup versions refuse mutation. Existing recovery backup bytes are preserved, not indiscriminately purged. Quota/token/cost algorithms and legitimate bookkeeping fields are unchanged.
3. `Configuration/UMAProductVersion.plist` adds the ReleaseCandidate channel: build `2026090501`, production-compatible `com.silkrd.uma`, app `UMA`, minimum macOS 14. Product version remains the single `Development.MarketingVersion` value, `0.14.0`. Frozen Host metadata is explicit compatibility data, not a second product-version authority.
4. The dedicated RC packager requires exact clean commit/tree/branch and fresh APFS output/build roots, exports that commit with git archive, builds main and relay in release mode with `UMA_PRODUCTION_RELEASE`, and records source/toolchain/package/linkage/hash/signing evidence. It does not install, launch, sign, copy provisioning profiles, rebuild Host or rewrite Mach-O binaries.

## Executed regression and honest limits

Evidence: `/Volumes/HE/DEV/UMA/Build/uma014-m5c/evidence`.

| Evidence | Result |
| --- | --- |
| Privacy failure-first regression | 3 definitions / 6 parameter cases / 10 issues reproduced (`privacy-red-authorized.log`) |
| Final focused regression | 37 definitions / 6 suites PASS, including new privacy, M5-B migration/install/rollback and cost-ledger coverage (`focused-converged.log`) |
| One complete post-convergence product regression | 1,097 definitions / 107 suites PASS (`full-regression.log`) |
| Bridge regression in the same run | 56 definitions / 3 suites PASS |
| Dedicated RC packaging guards | 12 Python test methods PASS (`package-guards.log`) |
| Independent convergence review | PASS for bounded code; final staged and actual-package decisions recorded separately |

The first unprivileged build attempt failed because Xcode's build service could not write a task-owned manifest under the execution sandbox. An authorized isolated run reproduced the actual product issues. The initial projection repair also failed one existing legacy byte-preservation expectation; the final recursive field check repaired it without weakening that test. Failed logs are retained.

All live opt-ins were unset. Tests use isolated stores, synthetic transports and fixture files. Full test counts include guarded live definitions whose bodies did not run; they are not live acceptance. The suite compiles its test-profile configuration; the release package separately compiles production-only paths. A source-bound production-flag auxiliary check, if run, is classified separately from exact-RC live evidence.

## Clean RC and runtime linkage

Only a new `Packages/uma-0.14-rc-<UTC timestamp>/UMA.app` can be an RC. Exact source identity, build commands, SDK/compiler, executable and bundle hashes, load commands/rpaths and observed signing state belong in the RC manifest/report packet. A source change after this build invalidates that RC and requires a fresh unique package.

Absolute system libraries are expected. Non-system direct loads are refused. Search paths are classified unused only when actual load commands cannot use them; build-path strings are not erased. A source audit additionally checks normal resource/helper discovery and dynamic loading. The official installed Codex application and frozen Safari Host are intentional external product dependencies, not development-storage dependencies.

No distribution signing is applied. Linker-generated ad-hoc Mach-O signatures, if present, are recorded distinctly. No App Group entitlement/profile is granted. Frozen Host metadata matching does not prove OS container access, handshake, Safari extension reachability or signed release readiness. The historical shared companion constant `1.4.0` is retained; the frozen production extension package is actually `0.13.0` and its build/generation are mirrored explicitly.

## Consolidated live/OS qualification gate

The RC must retain production-compatible identity to qualify eventual production Host/hook behavior. On the Founder's logged-in account that identity can read/write the production preference/data estate and resume existing consent. A probe proved that redirecting Foundation's home with `CFFIXED_USER_HOME` does not redirect cfprefsd persistence. It wrote only a newly named synthetic qualification domain. Therefore no production-ID app is launched under a false isolation claim. A temporary offline startup experiment was entirely removed before source freeze; no new qualification UI or alternate preference architecture ships.

After the exact RC exists, one consolidated Founder gate is required:

- Create/use an explicitly approved separate macOS test user. Copy the exact RC into that user's stable `~/Applications/UMA.app`, preserving executable/bundle hashes and avoiding every protected application.
- Use duplicated synthetic or sanitized 0.13 fixture data, with an untouched reference copy, for actual installed upgrade/rollback. Do not import credentials or silently migrate consent. The only production copy is never a disposable fixture.
- Perform the actual Finder/quarantine/translocation sequence, verify transient hook refusal, then explicit stable-install repair. Unit path fixtures alone do not close this gate.
- Authorize bounded Codex and Claude live source reads and any test-user provider consent/hook configuration. One-shot Accuracy Sync and immutable Host/Safari access need explicit inclusion; continuous polling remains prohibited. Host copies/enablement, if needed in the test user, preserve frozen bytes and require permission.
- Qualify the exact executable through real first launch/relaunch, windows/settings/Quick Panel/Wizard, preferences, appearance, monitoring and sleep/wake; visually verify WHITE+LIGHT and WHITE+DARK. Complete at least 60 minutes of meaningful real use if practical, with process/resource observations bound to executable hash.

Installation, real migration/rollback, OS translocation, main-app launch/compositing, live providers/Host and real soak remain unclosed until observed. Their absence is not replaced by test counts. Signing/notarization, Gatekeeper/offline validation, final production delivery, push/tag/GitHub release remain separate future authorization. No M5-C PASS or release-ready decision is asserted by this source-freeze record.

## Exact owned files

- `Configuration/UMAProductVersion.plist`
- `Sources/CodexUsageUI/Connectors/AgentConnectorSnapshotStore.swift`
- `Sources/CodexUsageUI/Services/APICostLedger.swift`
- `Tests/CodexUsageUITests/UMA014M5CPrivacyProjectionTests.swift`
- `script/read_uma_product_version.sh`
- `script/package_uma014_rc.py`
- `script/test_uma014_rc_package_guards.py`
- This source-freeze record.
