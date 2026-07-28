# UMA M3 Claude Code Capability Dossier

Date: 2026-07-24

## Decision

**Admission decision: `NO-GO — NOT INSTALLED`.**

Claude Code does not resolve in the user’s normal interactive login shell and
no official Claude Code executable exists at the standard installation
locations checked. The installed Claude Desktop application is a different
product and cannot satisfy the Claude Code status-line source contract.

No production Claude connector, relay, wrapper, or registry integration was
implemented. M3-G2 remains unstarted.

## Repository and governing provenance

- Workspace: `/Users/juliushe/Developer/UMA-M3`
- Branch: `codex/uma-m3`
- Starting HEAD: `26a0d8fd84db652ca5359fd53809ac9017066c80`
- Starting tree: `4269495794eef92560a9db04cd00d225af137a2a`
- Starting worktree: clean
- Starting index: empty
- Active governing versions:
  - `Scroll.md` 1.3
  - `M3_Plan.md` 1.1
  - `M3_Goal.md` 1.1
  - `UMA_Logic_1.3.md` 1.3
  - `Goal_Mode_2.0.md` 2.0
  - `Dev_Default_2.1.md` 2.1

## Installed capability inventory

| Candidate | Result | Meaning |
|---|---|---|
| Normal interactive login shell `claude` | Not resolved; version/help invocation exits as command not found | The executable the user would actually run is absent |
| `/opt/homebrew/bin/claude` | Absent | No standard Apple Silicon Homebrew installation |
| `/usr/local/bin/claude` | Absent | No standard Intel Homebrew/global installation |
| `/usr/bin/claude` | Absent | No system installation |
| `$HOME/.local/bin/claude` | Absent | No official native user installation |
| `$HOME/.local/share/claude` | Absent | No official native installer tree |
| `/Applications/Claude.app` | Claude Desktop, bundle `com.anthropic.claudefordesktop`, version `1.24012.1` | Desktop application only; not Claude Code |

Claude Code executable path, symlink chain, version, SHA-256, and architecture
are **not applicable** because no executable is installed. No PATH change,
installation, upgrade, decompilation, or disassembly was performed.

Installation classification: **not installed**.

## Official source mechanism

The current official documentation describes `statusLine` as a command that
receives structured JSON on standard input and prints display text on standard
output. It documents event-driven invocation at session start, after assistant
messages, compaction, permission-mode changes, Vim-mode changes, and an
optional refresh timer. Updates are documented as debounced by 300 ms, with an
in-flight command cancelled when a newer update arrives. The command runs
locally and does not itself consume API tokens.

Sources reviewed:

- [Claude Code status-line documentation](https://code.claude.com/docs/en/statusline)
- [Claude Code settings documentation](https://code.claude.com/docs/en/settings)

This establishes that an official structured source class exists in current
documentation. It does **not** establish that this machine has an installed
implementation, that a particular account emits any optional field, or that a
production wrapper meets UMA’s latency and privacy requirements.

## Settings hierarchy and status-line map

Official precedence is managed settings, command-line overrides, local
settings, project settings, then user settings.

| Precedence | Redacted source | Local result | Effective conclusion |
|---:|---|---|---|
| 1 | Server-managed settings | Not observable offline | Unverified; must be checked with Claude Code `/status` after installation/sign-in |
| 1 | macOS managed preferences `com.anthropic.claudecode` | `statusLine` absent | No local MDM status-line value |
| 1 | `/Library/Application Support/ClaudeCode/managed-settings.json` and `managed-settings.d/` | Absent | No file-based managed status line |
| 2 | Command-line session override | Not applicable | CLI is absent |
| 3 | `<M3>/.claude/settings.local.json` | Absent | No local override |
| 4 | `<M3>/.claude/settings.json` | Absent | No project configuration |
| 5 | `$HOME/.claude/settings.json` | Absent | No user configuration |

`CLAUDE_CONFIG_DIR` was unset in the task process and GUI-session environment,
so the user-settings path was not redirected.

Local status-line classification:
**`NO EXISTING STATUS LINE`**.

Global effective classification:
**`UNVERIFIED`**, because a signed-in installed CLI is required to confirm
server-managed sources via `/status`.

There is no command representation, referenced script, executable bit,
recursion path, prior stdout/stderr behavior, or local wrapper target to
inspect.

## Documented versus observed capability table

No official payload was observed because the runtime is absent. “Documented”
below means only that the current public status-line documentation names the
path and semantics; it is not an observation from this machine, account, or
authentication mode.

| Field | Documented path | Observed path/type/value shape | Documented status and scope | Privacy | UMA suitability | Final classification |
|---|---|---|---|---|---|---|
| Claude Code version | `version` | Not observed | String; runtime version | Allow if bounded | Useful provenance only | documented but not observed |
| Model identifier | `model.id` | Not observed | String; current session model | Allow if bounded | Useful display/detail | documented but not observed |
| Model display name | `model.display_name` | Not observed | String; current session model | Allow if bounded | Useful display/detail | documented but not observed |
| Five-hour usage | `rate_limits.five_hour.used_percentage` | Not observed | Number 0–100; consumed percentage; Pro/Max and post-first-response conditional | Allow if validated | Candidate plan metric | documented but not observed |
| Five-hour reset | `rate_limits.five_hour.resets_at` | Not observed | Unix epoch seconds; conditional with window | Allow if validated | Candidate reset metric | documented but not observed |
| Seven-day usage | `rate_limits.seven_day.used_percentage` | Not observed | Number 0–100; consumed percentage; independently optional | Allow if validated | Candidate plan metric | documented but not observed |
| Seven-day reset | `rate_limits.seven_day.resets_at` | Not observed | Unix epoch seconds; independently optional | Allow if validated | Candidate reset metric | documented but not observed |
| Model-specific weekly usage | No reviewed official path | Not observed | No supported status-line contract established | Reject | Not usable | undocumented — reject |
| Other plan windows | No stable reviewed path | Not observed | No supported status-line contract established | Reject unless later documented and observed | Not usable | undocumented — reject |
| Current-session cost | `cost.total_cost_usd` | Not observed | Number; client-estimated current-session USD, not an account bill | Allow if finite and scoped | Expanded detail only | documented but not observed |
| Session duration | `cost.total_duration_ms` | Not observed | Number; wall-clock milliseconds since session start | Allow if finite and scoped | Expanded detail only | documented but not observed |
| API duration | `cost.total_api_duration_ms` | Not observed | Number; milliseconds awaiting API responses | Allow if finite and scoped | Diagnostic detail only | documented but not observed |
| Token categories | `context_window.current_usage.*` | Not observed | Input/output/cache token counts from the last API call | Allow finite aggregates only | Context detail only | documented but not observed |
| Line changes | `cost.total_lines_added`, `cost.total_lines_removed` | Not observed | Numeric current-session aggregates | Allow finite aggregates only | Optional session detail | documented but not observed |
| Context used | `context_window.total_input_tokens`, `total_output_tokens`, `used_percentage` | Not observed | Current context from most recent API response; not plan usage | Allow finite scoped aggregates | Context detail only | documented but not observed |
| Context size | `context_window.context_window_size` | Not observed | Maximum context tokens | Allow finite scoped aggregate | Context detail only | documented but not observed |
| Context remaining | `context_window.remaining_percentage` | Not observed | Current context percentage; may be null early | Allow finite scoped aggregate | Context detail only | documented but not observed |
| Transcript path | `transcript_path` | Not observed | Filesystem path to conversation transcript | Private | Forbidden | private — reject |
| Working directory | `cwd`, `workspace.current_dir`, `workspace.project_dir`, `workspace.added_dirs` | Not observed | Filesystem/workspace identity | Private | Forbidden | private — reject |
| Repository identity | `workspace.repo.*`, worktree/PR fields | Not observed | Repository, branch, worktree, or remote identity | Private | Forbidden | private — reject |
| Account identity | No admitted path | Not observed | Identity is outside the required contract | Private | Forbidden | private — reject |
| Raw session/prompt ID | `session_id`, `prompt_id` | Not observed | Unique runtime identifiers | Private | Forbidden | private — reject |

No field is admitted merely because its name resembles quota data. The optional
five-hour and seven-day objects may be independently absent according to the
official documentation; therefore neither may be inferred from the other.

## Independent rate-limit decisions

- Five-hour limit: **UNSUPPORTED** on the current machine. A documented,
  conditional field exists, but there is no installed runtime and no observed
  value, unit validation, reset behavior, timestamp, scope, or update behavior.
- Seven-day limit: **UNSUPPORTED** on the current machine for the same reason,
  independently of the five-hour result.
- Model-specific weekly limit: **UNSUPPORTED**. No reviewed official
  status-line path was established and no runtime payload was observed.

“Unsupported” here is the machine-level admission result. It is not a claim
that current Claude Code releases can never emit the documented five-hour or
seven-day fields.

## Session and context scope

If later observed and validated, session cost, duration, token categories, and
line changes may be displayed only as current-session detail. Context values
may be displayed only as current-context detail.

They must never be represented as:

- account billing;
- account-level remaining usage;
- plan quota;
- cross-device completeness;
- substitutes for an absent five-hour or seven-day limit.

## Proposed production privacy contract

Allow only explicitly documented, observed, type-checked, range-checked,
scope-correct fields:

- Claude Code version;
- bounded model identifier and display name;
- independently validated plan-window used percentage and reset;
- finite context usage/size percentages and token aggregates;
- finite current-session cost, duration, API duration, and line-change
  aggregates;
- safe locally generated receipt timestamp and schema/version metadata.

Reject and discard:

- transcript path or content;
- prompts, responses, tool inputs, tool outputs, and source content;
- working-directory, repository, branch, remote, PR, or worktree identity;
- account email, name, IDs, organization, team, or billing identity;
- raw session, prompt, conversation, or request identifiers;
- credentials, cookies, tokens, Keychain, auth databases, or auth internals;
- raw payloads, unknown keys, rejected subtrees, or excerpts of their values.

Raw input may exist only transiently in bounded process memory. Unknown fields
are denied by default. If safe field separation cannot be proven, reject the
event and retain the last valid sanitized snapshot.

Proposed future safety ceilings are 64 KiB input, 16 KiB sanitized output,
depth 16, 2,048 parsed nodes, and 128 elements per array, with finite numbers,
bounded strings, `0600` output, atomic same-directory replacement, and no
network access. These are admission conditions, not implemented behavior.

## Event frequency and latency

| Measure | Current result |
|---|---|
| Live Claude requests | 0 of 2 |
| Live validation duration | 0 minutes |
| Estimated provider spend | USD `$0.00` |
| Status-line invocations per request | Not measurable; CLI absent |
| Response-to-probe latency | Not measurable; CLI absent |
| Probe execution duration | Not measurable; no probe created |
| Previous command duration | Not applicable; no local command |
| Payload size | Not observed |
| Sanitized snapshot size | Not created |
| Duplicate frequency | Not observed |

Only the official documented behavior is known: event-driven updates, optional
timer refresh, 300 ms debounce, and cancellation of an in-flight command after
a newer trigger. Production completion under 50 ms, duplicate coalescing,
event-only sufficiency, and any once-per-minute health fallback remain
**unproven**.

## Existing-command preservation

Classification:
**`NO EXISTING STATUS LINE`** in the inspected local layers.

There is no prior local command to wrap or preserve. This does not waive a
future re-audit. Before any later write, Claude Code `/status` must confirm all
loaded settings sources, including server-managed settings. If an effective
command then exists, M3-G1 must be rerun to prove exact invocation, quoting,
environment, stdout/stderr, exit/failure behavior, recursion prevention, and
latency before production work.

## Backup, probe, and restoration result

No Claude configuration file existed at the allowed user/project/local/system
paths, and no configuration was modified. Therefore:

- no backup was necessary or created;
- no wrapper or probe was installed;
- no raw payload was captured;
- no Claude process was launched;
- no provider request was sent;
- exact restoration is proven by the same allowed files and `statusLine`
  values remaining absent after inspection.

The complete future backup and rollback protocol is recorded in
`UMA M3 Claude Configuration and Restore Contract.md`.

## M3-G2 admission condition

M3-G2 may be reconsidered only after all of the following are true:

1. The official Claude Code CLI is installed by an authorized owner choice and
   `claude` resolves in the normal interactive login shell.
2. The installed executable path, symlink chain, version, SHA-256, and
   architecture are recorded.
3. Claude Code `/status` confirms every loaded settings source and the
   effective `statusLine`, including any server-managed policy.
4. A timestamped byte-and-metadata backup and deterministic rollback plan are
   proven before any temporary configuration write.
5. At most the authorized live budget is used to observe an official payload
   through an allowlist-first task-owned probe.
6. Five-hour and seven-day fields are classified independently from actual
   values, types, scope, reset semantics, timestamps, and update behavior;
   missing fields remain unavailable.
7. Privacy, recursion, prior-command preservation, restoration, latency,
   duplicate handling, generated-artifact, and independent Examiner gates
   pass.

Until then the source-admission verdict remains:
**`NO-GO — NOT INSTALLED`**.

## Completion Lock

No production relay or `ClaudeCodeUsageConnector` was installed or
implemented. M3-G2, WorkBuddy, Manus, WidgetKit, mobile support, and all other
providers remain unstarted. OneDrive was not accessed. No push, tag, release,
notarization, deployment, or publication is authorized by this dossier.
