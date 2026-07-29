# UMA M5 Claude Local Source Dossier

Date: 2026-07-28

## Decision

**SETUP REQUIRED — CLAUDE CODE CLI NOT INSTALLED**

The official Claude Code status-line protocol is a potentially admissible
local structured source for five-hour and seven-day subscription usage.
Current-device capability is not proven because the official Claude Code CLI
is not installed or resolvable.

This decision does not admit a production connector. No Claude process,
authentication flow, prompt, response, provider task, or settings mutation
occurred. No status-line payload was observed.

## Repository and governing provenance

- Branch: `codex/uma-m5-claude`
- Starting HEAD: `110a81217c39339c79a702559be25041ff56b293`
- Starting tree: `e254c220eb8a51bdcac2c0d3e5cbccc5e9fc43dc`
- Starting worktree: clean
- Starting index: empty
- M4: closed
- Manus: unsupported and hidden
- Production Manus API-key path: absent

The four M5 governing files were present at their approved SHA-256 values:

| Governing file | SHA-256 |
|---|---|
| `UMA_Logic_1.5.md` | `ac67765544c772a4e650c3d5d6d45929f92c94df85a092d1ff074ea4c7ce916b` |
| `Scroll_2.1.md` | `bd22620fb9af7b6067b16ea16a62a4ec10df93d8368256ba31245db23b8c4971` |
| `M5_Plan.md` | `0c81b3a878aa9303b96ccbb9e3c36f87c319fac2c0916fb5a1f8d3c002e37fd5` |
| `M5_Goal.md` | `a7819fbd2bb9ea5f1b0e7072dccd9e22e415b858e73761d59b18240f978917c0` |

## Current official source contract

Only current official Anthropic documentation was used:

- [Claude Code installation](https://code.claude.com/docs/en/installation)
- [Claude Code authentication](https://code.claude.com/docs/en/authentication)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage)
- [Claude Code status-line protocol](https://code.claude.com/docs/en/statusline)
- [Claude Code settings](https://code.claude.com/docs/en/settings)

The official protocol states that:

1. a configured status-line command runs locally;
2. Claude Code supplies one structured JSON object through standard input;
3. the status-line command itself does not consume API tokens;
4. `rate_limits` is available only for Claude.ai Pro/Max subscribers after the
   first provider response;
5. five-hour and seven-day windows can be independently absent;
6. used percentage is a number from 0 through 100;
7. reset time is Unix epoch seconds.

There is no documented standalone quota getter. UMA must never initiate a
Claude task merely to produce a status-line event.

## Installed-source evidence

| Evidence | Current result |
|---|---|
| Claude CLI found | No |
| Normal interactive login-shell resolution | Absent |
| Standard native executable candidates | Absent |
| Standard Homebrew executable candidates | Absent |
| Homebrew Claude Code package | Absent |
| Global npm package check | Not available because npm is not installed |
| Host architecture | arm64 |
| Normalized executable path | Not applicable |
| Claude Code version | Not applicable |
| Executable architecture | Not applicable |
| Executable SHA-256 | Not applicable |
| Signature/trust classification | Not applicable |
| Official installation classification | Not installed |

No installation, upgrade, PATH mutation, binary inspection, Desktop
application substitution, decompilation, or disassembly occurred.

## Authentication classification

**Authentication: unknown because the CLI is absent.**

Provider-managed Claude.ai subscription authentication is not proven. No
secret-based route was observed in the task process or inspected local
settings layers:

- API-key variable name: absent;
- bearer-token variable name: absent;
- setup-token variable name: absent;
- Bedrock selector name: absent;
- Vertex selector name: absent;
- Foundry selector name: absent;
- local `apiKeyHelper` key: absent.

These presence checks did not access a credential value. No credential file,
Keychain value, cookie, session, token, auth database, account name, email, or
organization identity was read.

## Settings and status-line classification

Official precedence is managed settings, command-line session overrides,
local project settings, shared project settings, then user settings.

| Sanitized settings layer | Local result |
|---|---|
| User settings | File absent |
| Shared project settings | File absent |
| Local worktree settings | File absent |
| Main-checkout local settings | File absent |
| File-based macOS managed settings | File absent |
| macOS managed-preferences file | File absent |
| User preferences file for the managed domain | File absent |
| Server-managed settings | Unobservable without an installed authenticated CLI |

Allowlisted key-presence results across the inspected local layers:

- `statusLine`: absent;
- `disableAllHooks`: absent;
- `allowManagedHooksOnly`: absent;
- `apiKeyHelper`: absent;
- secret-route environment names inside settings: absent.

Local existing-status-line classification:
**absent**.

Global effective status-line classification:
**unverified**, because server-managed settings cannot be established without
an installed, authenticated CLI.

Managed-policy blocker classification:
**unverified globally**.

No settings file was printed or modified. No existing status-line command was
read.

## Required payload capability table

“Unsupported” below is the current-device classification caused by the absent
CLI. It does not deny the official protocol’s documented capability.

| Official field | Official meaning | Current-device evidence | Classification |
|---|---|---|---|
| `rate_limits.five_hour.used_percentage` | Five-hour rolling-window percentage consumed, 0–100 | No installed payload source | unsupported |
| `rate_limits.five_hour.resets_at` | Five-hour reset time in Unix epoch seconds | No installed payload source | unsupported |
| `rate_limits.seven_day.used_percentage` | Weekly percentage consumed, 0–100 | No installed payload source | unsupported |
| `rate_limits.seven_day.resets_at` | Weekly reset time in Unix epoch seconds | No installed payload source | unsupported |
| `version` | Claude Code version string | No installed payload source | unsupported |

No field was observed as present, malformed, or absent on an account/session.
Those classifications would require an installed runtime and a naturally
generated provider response. Missing windows must never be inferred as zero
usage, full remaining usage, or another window’s value.

## Privacy allowlist

A future probe or production source may project only:

- the five-hour used percentage and reset epoch;
- the seven-day used percentage and reset epoch;
- an optional bounded Claude Code version string;
- locally generated receipt time and safe validity state.

Each quota window must be accepted or rejected independently. Percentages must
be finite and within 0–100. Reset timestamps must be integral Unix seconds.
Unknown fields are denied by default. Remaining usage is derived only as
`100 - used_percentage` after validation.

## Explicit forbidden-field rejection

The following official or potential payload data is forbidden and must not be
opened, retained, logged, persisted, displayed, or forwarded:

- `session_id`;
- `session_name`;
- `prompt_id`;
- `transcript_path`;
- `cwd`;
- `workspace.current_dir`;
- `workspace.project_dir`;
- `workspace.added_dirs`;
- repository, remote, pull-request, branch, and worktree data;
- account name, email, account ID, organization, or billing identity;
- prompt, response, task, source, conversation, or tool content;
- credentials, cookies, tokens, Keychain data, or auth internals;
- raw status-line JSON;
- unknown fields or rejected subtrees.

The focused test harness uses only clearly synthetic payloads and exposes only
the allowlisted projection plus bounded generic validity states.

## Temporary probe and restore result

Temporary probe:
**not feasible and not used because the CLI is absent**.

- Settings backup: not created
- Settings mutation: none
- Status-line command mutation: none
- Claude process launch: none
- Provider task: none
- Raw payload: none
- Temporary probe output: none
- Restoration: not required

The observed absence of local settings files remained unchanged. This is not a
claim that a live restoration was exercised.

## Human normal-response checkpoint

**Not reached.**

No request for `ONE RESPONSE COMPLETED` was issued because the CLI is absent
and no safe status-line probe exists. No Human prompt or response content was
requested or received.

## Admission closure

The official structured source class is potentially admissible, but the
current device does not yet have the official runtime required to prove
authentication, effective managed policy, installed field behavior, or a
valid quota window.

M5-G2 remains locked.

Exactly one next task is permitted:

**M5-SETUP-G1**
