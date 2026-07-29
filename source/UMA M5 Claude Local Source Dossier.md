# UMA M5 Claude Local Source Dossier

Date: 2026-07-28

## Current M5-SETUP-G1R decision

**GO — CLAUDE STATUS-LINE QUOTA SOURCE PROVEN**

The official native Claude Code 2.1.220 CLI is trusted and authenticated
through a provider-managed Claude.ai subscription. One Human-initiated normal
response caused the official local status-line command to receive a valid
post-response object. Both the five-hour and seven-day windows supplied finite
used percentages in the documented range, valid reset epochs, and a bounded
version field.

The allowlist probe retained only field-presence and validity classifications.
It calculated each remaining percentage as `100 - used` with decimal-aware
arithmetic, confirmed the result remained finite and in range, and discarded
the real values. No prompt, response, provider task content, raw status-line
JSON, quota value, reset time, credential, or account identity entered Git or
durable evidence.

The command-line settings file, probe, sanitized evidence, and task-owned
directory were removed. No persistent `statusLine` exists. This decision
admits M5-G2 as the only next task; it does not implement the relay or
connector.

## Historical M5-G1R decision

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

The official Claude Code status-line protocol is a potentially admissible
local structured source for five-hour and seven-day subscription usage.
Current-device capability is still not proven: a trusted Desktop-managed
Claude Code CLI is installed, but its own authentication status reports
logged out and no provider-managed subscription authentication is active.

This decision does not admit a production connector. No interactive Claude
session, authentication flow, prompt, response, provider task, or settings
mutation occurred. No status-line payload was observed.

## Repository and governing provenance

- Branch: `codex/uma-m5-claude`
- Starting HEAD: `6ac7e955cf6bf17aa32c948c2b6e7939e56f194f`
- Starting tree: `c80d882b8f07a84cce7839b50d5599669f8cf037`
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
| Claude CLI found | Yes, as a Desktop-managed native component |
| Normal interactive login-shell resolution | Absent |
| Desktop-managed executable | Present |
| Standard Homebrew executable candidates | Absent |
| Homebrew Claude Code package | Absent |
| Global npm package check | Not available because npm is not installed |
| Host architecture | arm64 |
| Normalized executable path | `~/Library/Application Support/Claude/claude-code/2.1.219/claude.app/Contents/MacOS/claude` |
| Claude Code version | `2.1.219 (Claude Code)` |
| Executable architecture | Mach-O arm64 |
| Executable SHA-256 | `49b1845cd34af8a57faf30c460824e4235ae4917bf15cd13288c1ae9e6077b97` |
| Signature | Valid, Team ID `Q6L2SF6YDW` |
| Gatekeeper | Accepted, Notarized Developer ID, Anthropic PBC |
| Doctor result | Exit 0; setup warnings remain |
| Official installation classification | Trusted Desktop-managed distribution; shell launcher absent |

The standalone `darwin-arm64` release-manifest checksum does not match this
Desktop-managed app-wrapped artifact, so no standalone-manifest-equivalence
claim is made. Native macOS signature and Gatekeeper checks passed outside the
sandbox. The temporary public-manifest files were deleted.

Doctor safely reported that subscription sign-in is inactive, the user
launcher is absent from the shell, and installation-method metadata is
unknown. No repair or installation command was run.

No installation, upgrade, PATH mutation, Desktop application substitution,
decompilation, or disassembly occurred.

## Authentication classification

**Authentication: logged out.**

The trusted CLI returned only the following allowlisted status:

- `loggedIn`: false;
- `authMethod`: none;
- `apiProvider`: `firstParty`.

Provider-managed Claude.ai subscription authentication is not active. No
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
| Server-managed settings | Unobservable while the CLI is logged out |

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
an authenticated CLI.

Managed-policy blocker classification:
**unverified globally**.

No settings file was printed or modified. No existing status-line command was
read.

## Required payload capability table

“Unsupported” below is the current-session classification caused by missing
authentication and the absence of a provider-generated status-line event. It
does not deny the official protocol’s documented capability.

| Official field | Official meaning | Current-device evidence | Classification |
|---|---|---|---|
| `rate_limits.five_hour.used_percentage` | Five-hour rolling-window percentage consumed, 0–100 | No authenticated provider event | unsupported |
| `rate_limits.five_hour.resets_at` | Five-hour reset time in Unix epoch seconds | No authenticated provider event | unsupported |
| `rate_limits.seven_day.used_percentage` | Weekly percentage consumed, 0–100 | No authenticated provider event | unsupported |
| `rate_limits.seven_day.resets_at` | Weekly reset time in Unix epoch seconds | No authenticated provider event | unsupported |
| `version` | Claude Code version string | CLI version independently verified; no payload field observed | unsupported as a payload field |

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
**not feasible and not used because the trusted CLI is logged out**.

- Settings backup: not created
- Settings mutation: none
- Status-line command mutation: none
- Status-line probe process launch: none
- Provider task: none
- Raw payload: none
- Temporary probe output: none
- Restoration: not required

The observed absence of local settings files remained unchanged. No backup was
created because no mutation began. Restoration was not required; this is not a
claim that a live restoration was exercised.

## Human normal-response checkpoint

**Not reached.**

No request for `ONE RESPONSE COMPLETED` was issued because authentication is
the earlier unmet precondition. The reported Human task was neither altered
nor inspected, and no provider event was awaited. No Human prompt or response
content was requested or received.

## Admission closure

The official structured source class remains potentially admissible. The
trusted runtime is now present, but provider-managed subscription
authentication is not active. No status-line field or valid quota window can
be admitted until that single setup condition is completed and M5-G1R is
rerun.

M5-G2 remains locked.

Exactly one next task is permitted:

**M5-SETUP-G1**

## M5-SETUP-G1 completion addendum

The M5-G1R decision above is retained as historical admission evidence.
M5-SETUP-G1 subsequently completed the single authorized provider setup task.

Setup result:
**PASS — CLAUDE.AI SUBSCRIPTION AUTHENTICATION AND NORMAL SHELL ACCESS
VERIFIED**.

The Human completed the provider-owned browser login without giving DEV a
password, verification code, URL, token, account identity, or screenshot.
Sanitized authentication classification after the checkpoint was:

- logged in: yes;
- authentication method: `claude.ai`;
- API provider: `firstParty`;
- API-key, copied-token, setup-token, Bedrock, Vertex, and Foundry routes:
  inactive.

The official Anthropic native installer was run once from
`https://claude.ai/install.sh` with all prohibited route variables unset. It
installed:

- launcher: `~/.local/bin/claude`;
- native binary: `~/.local/share/claude/versions/2.1.220`;
- version: `2.1.220 (Claude Code)`;
- architecture: arm64;
- SHA-256:
  `8addc857f3fe64d5a0368af9ee50321b50afb4a6918ba3ef018ab84f5dbbe081`;
- signature: valid Anthropic Developer ID, Team ID `Q6L2SF6YDW`.

The bare command-line executable is not an application bundle, so Gatekeeper's
application assessment returned the expected non-app classification. Strict
code-signature verification passed.

The user Zsh configuration was originally absent. M5-SETUP-G1 created it with
only the standard official launcher path:

`export PATH="$HOME/.local/bin:$PATH"`

A fresh login shell resolved `claude` to `~/.local/bin/claude`, reported
version 2.1.220, and completed `claude doctor` with no installation issues.
The task-owned absence backup was removed only after that verification.

No prompt, response, provider task, status-line probe, settings-file mutation,
quota field, raw usage payload, credential, account identity, or UMA runtime
was accessed or created.

M5-G2 remains locked. Exactly one next task is permitted:

**M5-G1R2**

## M5-G1R2 authenticated recheck

Repository gate:

- starting HEAD: `8b825d181205fd8d484364405044005a53bbd6ba`;
- starting tree: `0057ae69495cd32ed68454aba545cd5fead0b795`;
- worktree and index: clean;
- branch: `codex/uma-m5-claude`;
- M4 closed and Manus unsupported;
- M5 governing-source hashes unchanged.

Installed source:

- launcher: `~/.local/bin/claude`;
- native executable version: 2.1.220;
- architecture: arm64;
- SHA-256:
  `8addc857f3fe64d5a0368af9ee50321b50afb4a6918ba3ef018ab84f5dbbe081`;
- signature: valid Anthropic Developer ID, Team ID `Q6L2SF6YDW`;
- doctor: PASS with no installation issues.

Authentication is provider-managed Claude.ai subscription authentication.
All prohibited API-key, copied-token, setup-token, Bedrock, Vertex, and
Foundry route names were absent. No credential value or identity was read.

The user settings file was initially absent. Local managed-settings and
managed-preferences files were also absent. No existing status line or
`disableAllHooks` key required preservation. Global server-managed policy was
not enumerated, and no local managed-policy blocker was observed.

The temporary probe accepted at most 64 KiB of JSON through standard input,
discarded unknown and forbidden fields, made no network request, opened no
payload-supplied path, and could persist only generic presence, validation,
conversion, and reset-validity states. A synthetic self-check passed before
the live checkpoint. The Human then completed one normal response in the
installed CLI without disclosing the prompt or response.

No probe invocation was observed. The sanitized capability table is:

| Field | Current-device classification |
|---|---|
| Five-hour used percentage | unsupported; no status-line event observed |
| Five-hour remaining percentage | unavailable; no validated used value |
| Five-hour reset | unsupported; no status-line event observed |
| Seven-day used percentage | unsupported; no status-line event observed |
| Seven-day remaining percentage | unavailable; no validated used value |
| Seven-day reset | unsupported; no status-line event observed |
| Claude Code version payload field | unsupported as payload evidence; CLI version independently verified |

The probe persisted neither raw payload nor forbidden fields. Because it was
not invoked, no live percentage or reset timestamp entered temporary evidence,
Git, fixtures, screenshots, or reports.

Restoration was exact for the original absence state:

- prior settings existence: absent;
- prior `statusLine`: absent;
- temporary settings permissions: owner-only;
- temporary settings hash matched the installed temporary file before removal;
- final settings existence: absent;
- final `statusLine`: absent;
- backup marker, probe directory, and evidence path: deleted.

No synthetic Claude task was initiated. The provider response was entirely
Human controlled. The setup condition that remains is an effective official
status-line callback that produces the documented `rate_limits` projection.
Until that condition is proven, no quota source is admitted.

M5-G2 remains locked. Exactly one next task is:

**M5-SETUP-G1**

For this Completion Lock, `M5-SETUP-G1` denotes a separately authorized
status-line activation setup revision. The earlier launcher-installation and
subscription-authentication setup remains closed and must not be repeated.

## M5-SETUP-G1R authenticated activation recheck

The accepted predecessor was:

- branch: `codex/uma-m5-claude`;
- HEAD: `802249876d79f2e9cc1396111be8ac1012ada52c`;
- tree: `fcc6b819ebf715e97b066ff82bc95a6d274a7f63`;
- worktree: clean;
- index: empty.

The normal fresh login shell resolved the official user launcher and preserved
the real user home. All API-key, bearer-token, alternate-config, and enterprise
cloud override names were absent. A sandboxed authentication classification
incorrectly reported logged out, while the same allowlisted classification in
the normal user execution context reported provider-managed `claude.ai`
authentication with the first-party provider. The prior drift was therefore a
build-sandbox visibility error, compounded by incomplete first-run CLI
onboarding, not an expired subscription or alternate credential route.

The temporary session used only a command-line `--settings` file. It contained
one `statusLine` command referencing an owner-only probe. The probe:

- read standard input only;
- rejected input above 64 KiB;
- used no network;
- performed no payload-driven file or path access;
- persisted no raw JSON;
- projected only version presence and per-window presence/validity booleans;
- used decimal-aware subtraction to validate `remaining = 100 - used`;
- emitted only a fixed harmless marker.

The startup callback proved command activation. After one Human-controlled
normal response, a later callback proved:

| Allowlisted capability | Current-device classification |
|---|---|
| Five-hour used percentage | present and valid |
| Five-hour reset | present and valid |
| Five-hour remaining conversion | valid |
| Seven-day used percentage | present and valid |
| Seven-day reset | present and valid |
| Seven-day remaining conversion | valid |
| Version | present and bounded |

The real percentages and reset epochs were never written to Git or durable
records. DEV neither submitted nor read the Human prompt and did not read the
provider response.

The task-owned Claude process was identified by its neutral working directory
and terminated after evidence collection. The temporary settings, probe,
sanitized evidence, debug classification, symlink, and directory were deleted.
No persistent `statusLine`, raw payload, or task-owned backup remains.

The official first-run onboarding settings file is retained unchanged. It
contains exactly one non-sensitive `theme` preference and contains no
`statusLine`, credential, session, token, account identity, hook, API-key
route, enterprise-cloud route, provider route, or UMA probe configuration.
Founder approval supersedes literal restoration to pre-task file absence
because removing this provider-owned preference could retrigger onboarding.
No other Claude file was modified or deleted.

**ACCEPTED PROVIDER-OWNED ONBOARDING PREFERENCE — NOT A PROBE ARTIFACT**

**Admission: GO. Exactly one next task: M5-G2.**
