# UMA M8 Kimi Setup Record

Goal: M8-SETUP-G1 — Official Kimi Code installation/update and OAuth setup

Result: `PASS — READY FOR M8-G1R`

Observation date: 2026-08-11

## Accepted predecessor

| Field | Value |
|---|---|
| Workspace | `$HOME/Developer/UMA-M8-Kimi` |
| Branch | `codex/uma-m8-kimi` |
| Starting HEAD | `20af2b857b7dbbb5023cc7601e074b49e61c6087` |
| Starting tree | `690170d205187f21adda4eb4a1b6496e02988a12` |
| Starting worktree | clean |
| Starting index | empty |

M8-G1 remained the historical source decision. This setup Goal did not change
its admission decision or begin M8-G1R.

## Official installation source

Only current Kimi-owned sources were used:

- documentation: `https://www.kimi.com/help/kimi-code/cli-getting-started`;
- official repository: `https://github.com/MoonshotAI/kimi-code`;
- installer: `https://code.kimi.com/kimi-code/install.sh`;
- version marker: `https://code.kimi.com/kimi-code/latest`;
- manifest: `https://code.kimi.com/kimi-code/binaries/0.34.0/manifest.json`;
- arm64 artifact: `https://code.kimi.com/kimi-code/binaries/0.34.0/kimi-code-darwin-arm64`.

The installer was downloaded before execution and read in full. It resolves a
Kimi-owned version marker and manifest, selects the native platform artifact,
verifies the manifest SHA-256, installs into the user-local Kimi directory,
optionally updates a shell profile, and can migrate legacy Python shims.

The inspected installer SHA-256 was:

```text
638927825e96825edbb563de5e0cb06f8a0551c53e026ade8b717b0f25cb83d2
```

The current official marker resolved to `0.34.0`. The pinned manifest
SHA-256 was:

```text
91bba9e4f59d9a2243ba36e6c60af1d94fe69e43da5c1427b59d1323f973e5f7
```

The native manifest entry was `darwin-arm64`, filename
`kimi-code-darwin-arm64`, SHA-256:

```text
9f4337e10da47843f6b550474012a53ba8b30dd665f83b176a5cd479c5f7e859
```

## Installation method and side effects

The inspected official installer was executed with:

```text
KIMI_VERSION=0.34.0
KIMI_NO_MODIFY_PATH=1
```

This pinned the verified artifact and disabled shell-profile modification. No
legacy Kimi shim existed, so no migration or deletion occurred. No `sudo`,
global package manager, global security change, quarantine removal, or
third-party mirror was used.

Installed target:

```text
$HOME/.kimi-code/bin/kimi
```

## Installed executable identity

| Field | Result |
|---|---|
| Resolved path | `$HOME/.kimi-code/bin/kimi` |
| Symlink | NO — regular file |
| Owner/group | current user / `staff` |
| Mode | `0755` |
| File type | Mach-O 64-bit executable |
| Architecture | arm64 |
| Version | `0.34.0` |
| SHA-256 | `9f4337e10da47843f6b550474012a53ba8b30dd665f83b176a5cd479c5f7e859` |
| Embedded identifier | `kimi` |
| Team ID | `2J9472RW75` |
| Signing authority | `Developer ID Application: Beijing Moonshot Technology Co., Ltd (2J9472RW75)` |
| Hardened runtime | present |
| Strict code-sign verification | PASS |
| Gatekeeper app assessment | not applicable to this standalone CLI; returned `code is valid but does not seem to be an app` |
| Extended attributes | provider provenance present; quarantine absent |

The installed executable is byte-identical to the current official manifest
entry. Exact-path `--version`, `--help`, and `login --help` completed without
provider work.

## Installed capability

Installed help exposes:

- interactive TUI launch;
- provider-controlled `login` device-code flow;
- version and help capability;
- prompt mode only through `-p` / `--prompt`;
- provider, doctor, ACP, web, export, migrate, and upgrade commands.

Current official slash-command documentation exposes `/usage` as an
interactive information command. This setup Goal did not invoke it and did not
claim its schema, semantics, repeatability, or no-work behavior. Those remain
M8-G1R evidence requirements. `kimi -p "/usage"` remains prohibited because
installed help confirms that `-p` is Agent prompt mode.

## Provider-controlled authentication

The exact installed `kimi login` command opened the official RFC 8628
provider-controlled device flow in a visible Human-owned terminal/browser
interaction. The Human returned only `KIMI LOGIN COMPLETED`.

Authentication-state classification:

```text
PROVIDER-CONTROLLED OAUTH SETUP COMPLETED — CREDENTIALS OPAQUE TO UMA/DEV
```

Official Kimi documentation states that the resulting provider credential is
loaded automatically on later Kimi invocations. DEV did not inspect the Kimi
data directory, credential file, token, login URL, device code, browser state,
account identity, or configuration contents. No repeated login was requested.

## Operation accounting

```text
readiness quota/source observations: 0 / 1
automatic retries: 0
Kimi prompts: 0
Kimi Agent turns: 0
Kimi tasks/conversations: 0
intentional Kimi spend: 0
membership or Extra Usage mutations: 0
credential/private-state reads: 0
```

No `/usage` observation was necessary. No exact quota, reset, Extra Usage
balance, identity, raw provider output, login URL, or device code was retained.

## Privacy and provider protection

- credential access: NONE;
- token, cookie, Keychain, browser-profile, and auth-database access: NONE;
- raw auth or quota payload persistence: NONE;
- broad process command-line or environment capture: NONE;
- provider prompts/tasks/spend: NONE;
- Codex mechanism changed: NO;
- Claude mechanism changed: NO;
- WorkBuddy mechanism changed: NO;
- Antigravity mechanism changed: NO;
- Cursor remains unsupported and hidden;
- Kimi runtime connector/provider registration: NOT STARTED;
- Main Panel and Desktop Assistant changes: NONE;
- protected Desktop UMA replacement: NONE;
- `source/reference/**` changes: NONE.

Task-owned installer, manifest, version-marker, and downloaded-artifact files
must be removed after repository verification. The installed official CLI and
provider-owned authenticated state must remain intact for M8-G1R.

## Verification

| Check | Result |
|---|---|
| Focused M8-SETUP-G1 tests | PASS — 8 / 8 |
| Historical M8-G1 source-admission tests | PASS — 14 / 14 |
| Canonical serial full suite | PASS — 665 / 665 |
| Git whitespace check | PASS |
| Privacy, identity, and secret scan | PASS |
| Protected provider/runtime diff audit | PASS |
| M5 frozen-set and `source/reference/**` audit | PASS |
| Installed executable recheck | PASS |
| Independent staged-index review | PASS — exact two-file scope; no actionable finding |
| Post-commit clean worktree/index audit | pending final run |

No production, packaging, or configuration source changed, so separate Debug,
Release, and strict-concurrency builds were not repeated. The canonical suite
compiled the unchanged production target before executing all tests.

## Readiness decision

The current official Kimi Code CLI is installed at a stable exact path, bound
to a current Kimi-owned manifest and Developer ID identity, and its official
provider-controlled OAuth setup is Human-confirmed. M8-G1R can now perform the
bounded live source re-admission work defined by the governing Goal.

Exactly one next task:

`M8-G1R — Live installed Kimi CLI source re-admission`

M8-G1R is not started by this record. M8-WEB-G1, M8-G2, provider #5 runtime,
Main Panel, and Desktop Assistant work remain locked.
