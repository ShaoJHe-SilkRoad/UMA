# UMA M6 Antigravity Local Source Dossier

**Goals:** M6-G1 and M6-SETUP-G1
**Date:** 2026-08-08
**Baseline commit:** `bd09c15b466e873ece32dc3f52517ae4d3a45f67`
**Baseline tree:** `200e2d7c9bba917da834cf64c5629611a4edaec9`
**Historical M6-G1 decision:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`
**Current setup result:** `PASS — OFFICIAL ANTIGRAVITY CLI READY FOR M6-G1R`

## 1. Executive finding

The official Google Antigravity CLI remains a potentially admissible source
class. M6-G1 correctly found that the standalone CLI was absent, but incorrectly
reported the Antigravity desktop application itself as absent. A read-only
addendum confirmed Antigravity Desktop `2.6.0` was already installed and did not
contain an admitted bundled CLI.

No provider source read was attempted. M6-G1 used zero of the three authorized
quota/Credit reads and created no prompt, task, agent turn, model response,
conversation, or intentional spend.

M6-SETUP-G1 then installed the official manifest-pinned standalone CLI `1.1.11`,
proved installed help and structured print support, and used one authorized
read-only `/usage` execution to establish setup readiness. No raw quota value or
schema field was retained. The source must now return to M6-G1R; no production
connector is implemented or authorized.

## 2. Repository and exclusion-zone evidence

Before executable discovery, the live worktree proved:

| Property | Observation |
|---|---|
| Workspace | `/Users/juliushe/Developer/UMA-M6-Antigravity` |
| Branch | `codex/uma-m6-antigravity` |
| HEAD | `bd09c15b466e873ece32dc3f52517ae4d3a45f67` |
| Tree | `200e2d7c9bba917da834cf64c5629611a4edaec9` |
| Worktree | Clean |
| Index | Empty |
| M6-B0 commit | Present |
| M5 frozen/shared runtime | Byte-identical to the M6-B0 parent |

No unrelated work required mutation. Product source, `Package.swift`,
`BrowserExtension`, scripts, existing M5 tests, and existing M5 records stayed
read-only.

## 3. Corrected current-device executable inventory

Read-only discovery produced this sanitized inventory:

| Required fact | Current observation |
|---|---|
| Host architecture | arm64 |
| `agy` on `PATH` | Available after native setup |
| Documented target `$HOME/.local/bin/agy` | Present |
| `/Applications/Antigravity.app` | Present; `2.6.0`, `com.google.antigravity`, arm64 |
| `$HOME/Applications/Antigravity.app` | Absent |
| Bundled admitted CLI | None |
| Resolved standalone path | `$HOME/.local/bin/agy` |
| Symlink chain | None; regular file |
| Executable type / architecture | Mach-O 64-bit executable, arm64 |
| Executable owner / mode | Current user, `0755` |
| Installed version / build | `1.1.11`; no separate build reported |
| Embedded identifier / Team ID | `cli` / `EQHXZ8M8AV` |
| Signature / Gatekeeper | Local PASS unavailable; see setup evidence |
| Quarantine / provenance xattrs | Quarantine absent; provenance present |
| Installed `--help` | PASS |

The installed executable is byte-identical to the verified payload extracted
from the official manifest-pinned archive. The local macOS trust service cannot
produce reliable signature assessments, including for Apple system apps; the
Founder accepted that exact limitation for setup.

## 4. Current official public contract

Current official Google material was inspected read-only:

- [Antigravity CLI overview](https://antigravity.google/docs/cli/overview)
- [CLI installation and authentication](https://antigravity.google/docs/cli/install)
- [Model Quotas `/usage` and `/quota`](https://antigravity.google/docs/cli/commands/usage)
- [Antigravity changelog](https://antigravity.google/changelog)
- [Official Antigravity CLI repository](https://github.com/google-antigravity/antigravity-cli)
- [Official darwin arm64 update manifest](https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/darwin_arm64.json)

The public documentation reported CLI version `1.1.11`, a default macOS target
of `$HOME/.local/bin/agy`, provider-managed authentication, `/usage` with alias
`/quota`, and structured `json` / `stream-json` print support for read-only
commands. The public changelog describes those read-only print commands as
creating no agent turn, quota spend, or conversation.

These were public source-class facts only during M6-G1. M6-SETUP-G1 later
downloaded the exact manifest-pinned archive, verified its SHA-512, and proved
the installed version and capability. They still do not admit a quota schema.

## 5. Command classification

M6-G1 executed no Antigravity command. M6-SETUP-G1 later proved these exact-path
capability commands:

```text
$HOME/.local/bin/agy --version
$HOME/.local/bin/agy --help
```

Installed help confirms `-p` / `--print`, slash-command expansion, and
`--output-format` values `text`, `json`, and `stream-json`. The official 1.1.11
changelog names `/usage` and `/quota`; the setup-readiness argv was:

```text
$HOME/.local/bin/agy --output-format json -p /usage
```

That form executed exactly once during M6-SETUP-G1 and returned structured JSON.
Raw output and exact values were discarded. It is setup proof only, not schema
admission. No `/quota` or `/credits` execution occurred.

## 6. Live quota and schema classification

M6-G1 left every installed/live schema fact unavailable. M6-SETUP-G1 proved
only that one JSON document can be returned; it retained no schema detail:

| Schema fact | Classification |
|---|---|
| JSON root/container | Unavailable |
| Schema/version marker | Unavailable |
| Quota bucket container | Unavailable |
| Bucket identifier / safe label | Unavailable |
| Remaining-versus-used semantics | Unavailable |
| Reset time / duration form | Unavailable |
| Disabled / unlimited representation | Unavailable |
| Observation/currentness marker | Unavailable |
| Unknown/private-field presence | Unavailable |
| Repeated-read structural stability | Unavailable |

Neither M6-G1 nor M6-SETUP-G1 encodes a production field name, decoder,
conversion, bucket lineup, or reset representation. M6-G1R must inspect and
sanitize the live schema under its own bounded authority.

## 7. Authentication classification

M6-G1 authentication was unobservable because the standalone CLI was absent.
M6-SETUP-G1's one structured readiness read completed without browser login,
proving that provider-owned authentication is currently usable by the CLI.

Official installation material states that a missing provider session may open
the default browser for provider-controlled sign-in. No browser opened during
setup. A later routine background source must still fail closed rather than
unexpectedly launching login.

No credentials, Keychain items, cookies, browser profiles, OAuth/session tokens,
login URLs, account identity, or private provider state were accessed.

## 8. No-turn, no-task, no-conversation, and no-spend evidence

Official documentation and installed capability now support the intended
read-only print source class. Full causality and artifact checks remain for
M6-G1R.

| Claim | M6-G1 evidence |
|---|---|
| No provider prompt/task | One read-only slash command; prompt/task count 0 |
| No agent turn/model response | Official contract plus structured setup result; full runtime proof deferred |
| No conversation/project artifact | No artifact intentionally created; complete audit deferred to M6-G1R |
| No quota spend | Intentional spend 0; full causality audit deferred |
| No credential receipt by UMA | CLI-owned authentication; no credential operation occurred |

M6-SETUP-G1 does not claim full live admission merely because one structured
read succeeded. M6-G1R must validate process/artifact behavior, schema meaning,
privacy reduction, and remaining observational limits.

## 9. Credits

**`CREDITS DEFER`**

No `/credits` read occurred. No Credit field, exact balance, unit semantics,
schema, or stability was observed. Credits do not block the quota setup
decision, do not become percentage, and are not combined with model quota.

## 10. Evidence handling

All three required examiners reviewed one task-owned sanitized packet. It held
only discovery states, public-contract classifications, zero-read accounting,
unavailable live-schema states, the admission decision, and the next-task
classification. It contained no raw provider payload, stderr, exact quota,
reset value, identity, credential, browser data, or provider content.

The temporary packet was not copied into Git and was deleted after examiner and
root review. M6-SETUP-G1 retained only sanitized setup facts in
`source/UMA M6 Antigravity Setup Evidence.md`; raw live JSON and exact quota
values were never written to task-owned evidence or Git.

## 11. Admission conclusion

The historical M6-G1 decision remains:

```text
SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED
```

The current setup result is:

```text
M6-SETUP-G1 PASS — OFFICIAL ANTIGRAVITY CLI READY FOR SOURCE RECHECK
```

The only next task is **M6-G1R**. M6-G2 remains locked.
