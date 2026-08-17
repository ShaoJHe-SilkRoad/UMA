# UMA M5RMX QA Issue Ledger

**Version:** 1.0

**Opened:** 2026-08-17

**Current task:** `M5RMX-B0`

## 1. Scope and baseline

```text
Exact parent HEAD: 01b190260da857f55fa5fa9b14da9715cafbc221
Exact parent tree: 49f2af499c86b9b8757da0e9406a0d9e5c24495b
Source branch/worktree: codex/uma-m8-kimi / /Users/juliushe/Developer/UMA-M8-Kimi
New branch/worktree: codex/uma-m5rmx-claude / /Users/juliushe/Developer/UMA-M5RMX-Claude
Accepted predecessor full suite: 683/683 PASS
Accepted predecessor focused M8: 32/32 PASS
```

Current providers are Codex/Claude Code/WorkBuddy/Google Antigravity. Cursor/Kimi
are unsupported/hidden. Claude Safari Browser Sync is current; Chromium is
unverified; status-line is absent from production and retained only in
HISTORICAL / RETIRED records/tests. Current privacy policy:

`Credential existence is not the problem; credential crossing into UMA is the problem.`

## 2. B0 issues

| ID | Severity | Discovery | Root cause / classification | Required repair or control | Verification | State |
|---|---|---|---|---|---|---|
| M5RMXB0-001 | Blocking | Founder governing files were present only in Downloads | M5RMX had no installed program authority in the new branch | Install `M5RMX_Plan.md` and `M5RMX_Goal.md` under mutable `source/`, preserving semantic content while satisfying the required repository whitespace gate | source/download semantic comparison, original and installed SHA-256, whitespace audit | Closed; independent staged review PASS |
| M5RMXB0-002 | Blocking | Accepted Claude behavior was distributed across current source and historical M5 records | A new implementation could accidentally rebuild or contradict accepted Browser Sync | Create a current claim-to-code/live/package/commit map and file-ownership inventory | deterministic B0 contract plus independent review | Closed; independent staged review PASS |
| M5RMXB0-003 | Major | Historical status-line records/tests still exist alongside current Browser Sync records | Retained history can be mistaken for current source ownership | Record Browser Sync as current, status-line as historical/retired, active target/source absence, and package reintroduction guards | production/source/package-symbol checks | Closed; source and independent review PASS |
| M5RMXB0-004 | Major | Apple signing readiness and the historical smoke notary backend anomaly are separate states | Treating readiness as Accepted notarization would overclaim distribution | Record Team `C6TUZVJ6SJ`, `UMA-notary`, submission/backend anomaly, support IDs, and protected smoke artifacts; execute no Apple action | record-only audit against Founder evidence | Closed for B0 record truth; Apple workstream remains external |
| M5RMXB0-005 | Major | Live `origin` is `ShaoJHe-SilkRoad/UMA`, while the Founder plan names `ShaoJHe-SilkRoad/CodexUsageMonitor` | Future push could target the wrong repository if the discrepancy is ignored | Preserve live remotes, record discrepancy, require M5RMX-SYNC-G1 identity/divergence gate | `git remote -v` and local ref inventory; no remote mutation | Closed for B0; external decision deferred to SYNC |
| M5RMXB0-006 | Major | Desktop contains a dirty historical development checkout and a pre-existing 0.12 app | Automatic update could destroy Human work or misidentify the final deliverable | Inventory exact states/hashes; preserve both apps/checkouts; require later commit-exact delivery gate | read-only Desktop metadata/hash and Git status | Closed for B0; delivery deferred |
| M5RMXB0-007 | Major | Current M5 package helper still declares marketing version 0.11 and the Safari appex carries a temporary file exception | Current packaging cannot be represented as final accepted 0.12 distribution | Record exact package/entitlement state; defer repair/adjudication to the named M5RMX packaging/Apple Goals | package-source inventory | Open program work; not a B0 blocker |
| M5RMXB0-008 | Privacy | Provider-controlled credential state could be confused with UMA credential access | Earlier formulations focused on credential existence rather than boundary crossing | Adopt the exact current privacy sentence and enumerate closed sanitized packet/prohibited data classes | privacy/identity/secret scans and protocol inventory | Closed; bounded scans PASS |
| M5RMXB0-009 | Protection | `source/reference/**` contains older provider truth | Historical reference material could be rewritten to match current runtime | Classify it as checksum-locked/read-only; add current additive records only | exact reference-tree diff | Closed; unchanged from accepted parent |
| M5RMXB0-010 | Gate | Fresh B0 baseline and build evidence was not available during the docs phase | Accepted 683/683 predecessor evidence could not replace current B0 verification; parallel diagnostic reruns also exposed unrelated historical lifecycle-test timing instability | Run the required deterministic suite serially, plus focused B0, Debug, Release, and strict-concurrency gates; do not upgrade isolated parallel timing failures into B0 source defects | `6/6` focused PASS; deterministic `--no-parallel` full suite `689/689` PASS; isolated timing-test reruns PASS; Debug / Release / strict PASS | Closed |
| M5RMXB0-011 | Gate | Founder Plan/Goal source copies exposed 57 two-space Markdown hard-break lines to Git's required trailing-whitespace gate | B0 initially applied the checksum lock for historical `source/reference/**` too broadly to the new mutable `source/` authority files; neither the Founder objective nor the governing files require byte identity for these installed copies | Preserve the Downloads originals, remove only trailing hard-break spaces from the installed mutable copies, retain all semantic text and line structure, and leave Git whitespace configuration unchanged | Plan 47 / Goal 10 source hard breaks normalized to zero; tabs and three-plus endings zero; installed diff check PASS | Closed |
| M5RMXB0-012 | Evidence | Packaged Chromium companion resources could be mistaken for accepted current Browser Sync | Current accepted live evidence is Safari-only; packaging presence does not prove Chromium runtime acceptance | Mark Safari as current source owner and Chromium as unverified/future | current source/record map review | Closed in records |
| M5RMXB0-013 | Distribution | Apple credential/signing infrastructure readiness could be mistaken for a signed/notarized current product | The historical smoke is blocked by a backend anomaly and the current M5RMX package has not passed final distribution gates | Record infrastructure and protected local smoke presence separately from current product distribution status | local path presence only; no Apple query | Closed in records; final distribution remains unproven |
| M5RMXB0-014 | Evidence | Bounded local verification found both the retained smoke app and an isolated extraction of its archive currently fail strict signature verification as code modified | The current preserved state does not support repeating the historical signature-valid claim; matching executable SHA-256 values show the retained app and archive payload agree | Record the discrepancy without querying Apple or repairing, re-signing, deleting, or mutating either protected artifact; remove only the scratch extraction | protected-path presence, matching executable hashes, strict local signature classification, scratch absence | Closed for B0 truth; external Apple resolution remains open |

## 3. Required B0 verification ledger

| Gate | Required result | Current record |
|---|---|---|
| exact parent HEAD/tree | exact values above | verified before edits |
| branch/worktree | exact source/new branch/worktree above | verified before edits |
| Plan source / installed SHA-256 | source `03dd6167b663022cb615540055231241ab1439d4c0150323d72bd79179c07a67`; installed `b43837b03bea0af20bf67f7fcf3cd83b932450ffcf2c987864adfed695782ffe` | semantic content preserved; only 47 trailing two-space hard breaks removed from mutable copy |
| Goal source / installed SHA-256 | source `5a84f486deb8065732bde965dbbad4e7533720ccf984867419474fc6bde5cf6f`; installed `182f022baaeeca8494adfda888cc5ed6c54df56975966634d62b6dd360487ee8` | semantic content preserved; only 10 trailing two-space hard breaks removed from mutable copy |
| focused B0 contract | PASS | `6/6` PASS |
| full deterministic suite | PASS; legitimate current count reported | `689/689` PASS: deterministic `--no-parallel` run, 671 UI plus 18 bridge |
| Debug / Release / strict Release | PASS / PASS / PASS | PASS / PASS / PASS |
| current Claude mechanism | Browser Sync present; status-line retired | source map and independent examiner PASS |
| protected providers | Codex/WorkBuddy/Antigravity unchanged | source diff empty; no staged production/provider mutations |
| unsupported providers | Cursor/Kimi unsupported/hidden | records/source audit PASS |
| `source/reference/**` | unchanged | exact parent diff empty |
| protected Desktop rollback | executable SHA unchanged | `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` reverified |
| privacy/identity/secret scans | no prohibited retained material | bounded six-file scans PASS |
| whitespace | all six staged files clean | Plan/Goal mutable copies normalized; cached `git diff --check` PASS |
| staged index | exact B0 files; independent cached-diff PASS | exact six-file scope; PASS |

## 4. Apple and Desktop non-operation record

Apple state is record-only:

```text
Team: C6TUZVJ6SJ
Profile: UMA-notary
APPLE-G1: BLOCKED — APPLE NOTARY BACKEND / SUPPORT INVESTIGATION
Feedback: FB24386147
Support: 20000140194585
Protected smoke: /private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.app
Protected archive: /private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.zip
```

Desktop rollback identity:

```text
/Users/juliushe/Desktop/UMA_0.11.app
SHA-256: 88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a
```

B0 performed no production/provider/Apple/Desktop actions. It did not query or
resubmit notarization, touch the profile/private key, launch a provider, read an
account, mutate a Desktop app, or push.

## 5. Completion boundary

B0 can close only after the fresh baseline, build, privacy, protection, exact
staging, independent review, local commit, and clean worktree/index gates pass.
The sole next task is `M5RMX-G1`. No production Claude work, provider action,
Apple action, Desktop delivery, remote synchronization, or later M5RMX Goal
starts automatically.
