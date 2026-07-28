# UMA M2WDBG Scope Lock

Date: 2026-07-24

## Baseline

- Workspace: `/Users/juliushe/Developer/UMA-M2W`
- Branch: `codex/uma-m2w`
- Starting HEAD: `81a71d614dbe63c02af80b1ba9b2754bddf49226`
- Starting tree: `99d56fe4c912e3c63639fec2dc55b80251d12fc0`
- Starting worktree: clean
- Starting index: empty
- Accepted M2W-G1 commit: `2a0d648`
- Accepted M2W-G2 commit: `42d97e6`
- Accepted M2W-G3 commit: `81a71d6`

## Governing authority

- `M2W_Plan.md` version 1.0 — SHA-256
  `02d30be28aa0521457ae4b42b3f0523ae1b918646330dda2be4d5f76b15a3556`
- `M2W_Goals.md` version 1.0 — SHA-256
  `9508d2910a91db3fd3eb334452da273f53b4d1bbfeb4ec134f99ba5a578c4d10`
- `M2W_WorkBuddy_Credit_Research.md` version 1.0 — SHA-256
  `5c8ed07a2556ee47eb35cbd019fde880007d4d0ab6d3d9913aa1016704ece444`
- `UMA_Logic_1.3.md` — SHA-256
  `c73cde523d92671213e4aa00cb93d01f6e4f9258ac8268891ea76dea61b2d064`
- `Goal_Mode_2.0.md` — SHA-256
  `9035f2574938752f40a50346c33bcc32db33c70526989fc14825d51ff1f6d5e7`
- `Dev_Default_2.1.md` — SHA-256
  `d2997e2039ef2418c98bce66b516e2a9f734394b338abd383fc92f9e6260e598`

## Debug and repair scope

M2WDBG-G1 may stress, diagnose, and make the smallest necessary repairs to the
accepted Credit value model, manual WorkBuddy source, persistence and recovery,
Settings workflow, main-panel presentation, localization, accessibility, tests,
packaging, and M2W records. It may not redesign the accepted architecture.

The preserved ownership path is:

```text
ManualWorkBuddyAvailabilitySource
→ WorkBuddyAvailabilityConnector
→ AgentConnectorRegistry
→ UsageStore
→ SharedUsagePresentationPolicy
→ main panel
```

## Task-owned isolation

- Synthetic preference home:
  `/private/tmp/uma-m2wdbg-runtime/home`
- Synthetic storage roots:
  `/private/tmp/uma-m2wdbg-runtime/stores`
- Candidate/runtime evidence:
  `/private/tmp/uma-m2wdbg-evidence`
- Package source/build scratch:
  `/private/tmp/uma-m2wdbg-package-*`
- Final package policy:
  `/private/tmp/uma-m2wdbg-final-<short-commit>/UMA.app`

Only task-owned synthetic/manual records and preference domains may be used.
Real WorkBuddy values and user storage are excluded.

## Instrumentation

The debug matrix records:

- persistence operation-to-write counts, primary/recovery size, and permissions;
- host and owned-child process counts;
- status-item count and connector ownership;
- threads, file descriptors, CPU, and RSS;
- timers and file observers where observable;
- network sockets and provider-read count;
- relaunch, invalid-state, and recovery outcomes.

## Protected boundaries

- Main-panel order remains Codex → WorkBuddy.
- Desktop Assistant remains Codex-only.
- Exactly one passive manual WorkBuddy connector remains registered.
- Shared Refresh never mutates WorkBuddy manual data or confirmation time.
- WorkBuddy creates no process, provider read, network client, polling timer, or
  private file observer.
- Automatic WorkBuddy synchronization remains NO-GO.
- WorkBuddy account, provider, application, browser content, private files,
  databases, processes, memory, credentials, Keychain, OCR, and network are not
  accessed.
- Claude, Manus, OneDrive, and every other provider are excluded.

## Git and package authority

One bounded local repair commit is authorized when runtime or test repair is
required:

`fix(workbuddy): close manual availability main-panel defects`

If only durable debug and handoff records change, one documentation-only commit
is permitted:

`docs(m2w): record main-app debug acceptance`

No amend, fetch, push, tag, release, notarization, deployment, or publication is
authorized. The installed Desktop application must not be modified.

The final package must be built from the exact accepted commit, remain under the
task-owned `/private/tmp` path, carry exact commit/source provenance, exclude
manual snapshots and generated evidence, and pass direct isolated runtime
acceptance.

## Completion Lock

Stop after the final local commit, commit-exact package, direct package
acceptance, complete `source/UMA M2WA Handoff.md`, clean worktree/index proof,
and final M2WDBG-G1 report.

Do not begin M2WA-G1 automatically. Do not add WorkBuddy to Desktop Assistant.
