# UMA M8 Kimi Local Source Dossier

Status: M8-G1 complete
Observation date: 2026-08-11
Repository baseline: `801fd521298fd6f2483cc9eab037562c0bc5a4f9`
Overall source result: `SETUP REQUIRED`

## Executive finding

Kimi remains an official first-party source candidate, but the current Mac has
no installed Kimi Code CLI and no installed Kimi or Kimi Work application.
Official documentation establishes an interactive `/usage` command and
provider-owned membership, Kimi Code-limit, and Extra Usage surfaces. It does
not establish an installed, repeatable, machine-readable, zero-turn quota read
on this device.

No Kimi process was launched. No login was attempted. No quota/source
observation was performed. M8-G1 therefore stops at provider-owned setup.

## Accepted repository baseline

| Field | Result |
|---|---|
| Workspace | `$HOME/Developer/UMA-M8-Kimi` |
| Branch | `codex/uma-m8-kimi` |
| Starting HEAD | `801fd521298fd6f2483cc9eab037562c0bc5a4f9` |
| Starting tree | `0ec25ebaf84e2970e05f29f533ddadc67e46c981` |
| Starting worktree | clean |
| Starting index | empty |
| Provider-read budget | 0 of 3 consumed |

## Current-device installed-source inventory

Exact-path and command-resolution inspection produced this sanitized result:

| Field | Result |
|---|---|
| `command -v kimi` | absent |
| shell resolution for `kimi` | absent |
| `$HOME/.local/bin/kimi` | absent |
| `$HOME/.cargo/bin/kimi` | absent |
| `/opt/homebrew/bin/kimi` | absent |
| `/usr/local/bin/kimi` | absent |
| `/Applications/Kimi.app` | absent |
| `/Applications/Kimi Work.app` | absent |
| user Applications Kimi bundles | absent |
| exact-name Spotlight matches | 0 |
| Kimi/Moonshot LaunchServices matches | 0 |
| host architecture | arm64 |

Because no provider executable exists, these installed-artifact fields are
`unavailable`: resolved executable path, symlink chain, file type, executable
architecture, owner, mode, version/build, signature, Gatekeeper assessment,
quarantine/provenance attributes, installed `--help`, and authenticated state.
The host architecture is not evidence of executable architecture.

## Current official public contract

The recheck used only current first-party Kimi documentation and the official
MoonshotAI repository:

- [Kimi Code slash commands](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/slash-commands.html)
- [Kimi command reference](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html)
- [Kimi Code benefits](https://www.kimi.com/help/kimi-code/benefits)
- [Kimi Code membership guide](https://www.kimi.com/help/kimi-code/membership-guide)
- [Membership credit update and usage rules](https://www.kimi.com/help/membership/update-rules)
- [Kimi Code changelog](https://www.kimi.com/code/docs/en/kimi-code-cli/release-notes/changelog.html)
- [Official MoonshotAI Kimi Code releases](https://github.com/MoonshotAI/kimi-code/releases)

The public contract proves:

1. `kimi` is the official Kimi Code CLI entry point.
2. `/usage` is an information command inside the interactive TUI and shows
   token usage, context consumption, and quota information.
3. `--prompt` / `-p` is Agent prompt mode; `--output-format` supports `text`
   and `stream-json` only with prompt mode.
4. Current documentation does not declare `/usage` as a standalone structured
   shell command. M8 must not treat `kimi -p "/usage"` as a safe control read.
5. Kimi membership features share a credit pool, while Kimi Code also has its
   own five-hour and weekly/provider-cycle limits.
6. Extra Usage is a native continuation wallet shared by Kimi web and Kimi
   Code. When enabled and funded, it can continue work after time-limited
   subscription credits are exhausted.
7. Current public material contains plan-transition drift: merged membership,
   newer split Code plans, weekly Code cycles, and monthly membership cycles
   must not be collapsed into one inferred denominator.

The official release page identified `@moonshot-ai/kimi-code@0.29.0` as the
current release observed on 2026-08-11. This is documentation evidence, not an
installed version claim.

## Candidate matrix

| Candidate | Authority | Current metric | Credential boundary | M8-G1 disposition |
|---|---|---|---|---|
| Official Kimi Code TUI `/usage` | official | documented quota information; exact current structure unobserved | provider OAuth | primary; setup required |
| Official Kimi Code Console | official | Code limits and Extra Usage described; live layout unobserved | provider web login | conditional future source |
| Official Subscription / My Quota | official | shared membership and Extra Usage described; live layout unobserved | provider web login | conditional future source |
| Kimi Open Platform API/balance | official but separate product | API product balance | API key | rejected |
| Local credential/config files | provider-private state | not an admitted quota source | exposes secret/private state | rejected |
| Conversations, logs, activity estimates | local inference | not current account quota | none | rejected |
| Private/internal account endpoint | undocumented/private | unqualified | credential/session dependency | rejected |

## Channel and account-mode adjudication

Current account mode: `unknown/unsupported` because no provider-owned source was
installed or authenticated and identity-bearing account state was not read.

Channel decisions describe source viability, not production admission.
`CONDITIONAL` means a first-party candidate exists but current-device proof is
still gated by setup; it does not unlock runtime.

| Channel | Current decision | Reason |
|---|---|---|
| Shared membership | `CONDITIONAL` | official shared-pool/account surfaces exist, but no current value, scope, or cycle was observed |
| Kimi Code limits | `CONDITIONAL` | official five-hour and weekly limits exist, but stable live identities, values, and resets were not observed |
| Extra Usage | `UNREADABLE` | official continuation semantics exist, but current absent/disabled/enabled state and exact native balance were not observed |

No channel is admitted from documentation alone. The dossier does not infer a
monthly cycle from a weekly Code document, manufacture two windows, or convert
Extra Usage money into a percentage.

## Source-execution and observation result

| Counter | Result |
|---|---|
| Qualified quota/source observations | 0 / 3 |
| Live-source elapsed window | 0 minutes / 15 minutes |
| Automatic retries | 0 |
| Provider prompts | 0 |
| Provider tasks/conversations | 0 |
| Intentional model/token spend | 0 |
| `/credits` reads | 0 |
| Login/browser actions | 0 |

The CLI absence prevented an exact installed-help-derived control sequence.
Launching an uninstalled command or substituting prompt mode would not be a
qualified read. No raw provider payload, transcript, quota value, reset date,
identity, login URL, or code was produced or retained.

## No-work/no-spend classification

For M8-G1 itself, zero provider work and zero spend are proven because no Kimi
executable, page, login, or source read was invoked. The no-turn/no-spend
behavior of a future `/usage` read remains `unproven`; it must be established
after official setup, not inferred from public descriptions.

## Safe future capability sequence

Only after direct authorization for M8-SETUP-G1:

1. inspect the current official installer and pinned artifact;
2. install the minimum official CLI;
3. verify the exact installed path, version, file identity, provenance, and
   installed `--help`;
4. allow provider-controlled OAuth setup without exposing credentials;
5. return to a bounded source-admission recheck before production work.

`kimi --version` and `kimi --help` are candidate capability-only forms after
installation. No `/usage` argv or input sequence is admitted until installed
help and bounded behavior prove it.

## Result

`SETUP REQUIRED`

`M8-G2 remains locked.`

Only next task: `M8-SETUP-G1`, after direct Founder authorization.
