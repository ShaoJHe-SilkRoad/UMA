# UMA M6 Antigravity Local Source Dossier

**Goal:** M6-G1
**Date:** 2026-08-08
**Baseline commit:** `bd09c15b466e873ece32dc3f52517ae4d3a45f67`
**Baseline tree:** `200e2d7c9bba917da834cf64c5629611a4edaec9`
**Primary decision:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`

## 1. Executive finding

The official Google Antigravity CLI remains a potentially admissible source
class, but it is not installed on this Mac. No trusted executable exists from
which M6-G1 could verify installed help, exact argv, authentication behavior,
structured quota schema, or current quota semantics.

No provider source read was attempted. M6-G1 used zero of the three authorized
quota/Credit reads and created no prompt, task, agent turn, model response,
conversation, or intentional spend.

This is a setup condition, not a source-class rejection. A separately
authorized M6-SETUP-G1 may use the official provider setup path and then return
to source admission. M6-G1 does not install, update, authenticate, or implement
the production connector.

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

## 3. Current-device executable inventory

Read-only discovery produced this sanitized inventory:

| Required fact | Current observation |
|---|---|
| Host architecture | arm64 |
| `agy` on `PATH` | Absent |
| Documented target `$HOME/.local/bin/agy` | Absent |
| `/Applications/Antigravity.app` | Absent |
| `$HOME/Applications/Antigravity.app` | Absent |
| Spotlight registrations | 0 |
| LaunchServices registrations | 0 |
| Installer receipt matches | 0 |
| Resolved executable path | Unavailable |
| Symlink chain | Unavailable |
| Executable type / architecture | Unavailable |
| Executable owner / mode | Unavailable |
| Installed version / build | Unavailable |
| Signature / Team ID | Unavailable |
| Gatekeeper result | Unavailable |
| Quarantine / provenance xattrs | Unavailable |
| Installed `--help` | Unavailable |

`arm64` describes the host only. It is not evidence of an installed binary's
architecture. Unavailable trust fields are not signature or Gatekeeper
failures; there is no artifact to assess.

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

These are public source-class facts only. They do not prove that the capability
is installed or authenticated on this Mac. The manifest supplied an official
version and archive-integrity channel; no archive or executable was downloaded.

## 5. Command classification

No installed Antigravity command was executed.

After separately authorized official setup, the first capability-only
candidates are:

```text
$HOME/.local/bin/agy --version
$HOME/.local/bin/agy --help
```

Only if installed help confirms the syntax may a later admission pass consider
the argv-equivalent candidate:

```text
$HOME/.local/bin/agy --output-format json -p /usage
```

That quota form is documented but was not installed, admitted, or tested in
M6-G1. No `/quota`, `/usage`, `/credits`, or equivalent provider read occurred.

## 6. Live quota and schema classification

Because the executable is absent, every installed/live schema fact remains
unavailable:

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

M6-G1 therefore does not encode a production field name, decoder, conversion,
bucket lineup, or reset representation. It does not infer semantics from the
planning documents.

## 7. Authentication classification

Current-device authentication is **unobservable because the CLI is absent**.
It is not classified as logged out, expired, enterprise, or authenticated.

Official installation material states that a missing provider session may open
the default browser for provider-controlled sign-in. Current-device browser
behavior was not tested. A later routine background source must fail closed
rather than unexpectedly launching login, and setup must remain a separate
Human-controlled action.

No credentials, Keychain items, cookies, browser profiles, tokens, login URLs,
account identity, or private provider state were accessed.

## 8. No-turn, no-task, no-conversation, and no-spend evidence

Official documentation supports the intended read-only print source class.
Live installed proof is unavailable because there is no executable.

| Claim | M6-G1 evidence |
|---|---|
| No provider prompt/task | No provider command executed; count 0 |
| No agent turn/model response | No provider command executed; public contract only |
| No conversation/project artifact | No provider command executed; public contract only |
| No quota spend | Intentional spend 0; live command causality untested |
| No credential receipt by UMA | No provider or credential operation occurred |

M6-G1 does not claim live proof merely because no UI appeared. The later
installed-source pass must separately validate current process/artifact behavior
and state any remaining observational limitation.

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
root review. Durable Git evidence is limited to the four M6 records and visibly
synthetic deterministic tests.

## 11. Admission conclusion

```text
SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED
```

The only next task is **M6-SETUP-G1**, and it requires separate Founder
authorization. M6-G2 remains locked.
