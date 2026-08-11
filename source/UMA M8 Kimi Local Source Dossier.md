# UMA M8 Kimi Local Source Dossier

Status: M8-G1R complete
Observation date: 2026-08-11
Accepted starting commit: `d65fffe68b8d82c0e0c05b1299a3aa2d21257521`
Accepted starting tree: `9b8dcdbc17eb05276dc47b8c59dd94cbfe17e971`
Overall source result: `NO-GO`

## Executive finding

The official Kimi Code CLI is installed, authenticated by the provider-owned
OAuth flow, and byte-identical to the accepted M8-SETUP-G1 artifact. Current
official documentation and public source prove that `/usage` is an interactive
TUI built-in rather than an Agent prompt, and that its current renderer has
separate Kimi Code plan-limit and Extra Usage sections.

The bounded current-device re-admission did not retain one successful sanitized
`/usage` observation. All three conservatively accounted observations are
consumed. The first control attempt was intercepted by the provider's
workspace-trust dialog; the second reached the idle TUI but did not yield a
recognized usage panel; the final positively gated probe returned no durable
sanitized packet. No further read is authorized. Live structure, identities,
account mode, repeated behavior, and continuation truth therefore remain
unadmitted.

This is a current-device CLI-source `NO-GO`, not evidence that the official
account surfaces are invalid. M8-G2 remains locked.

## Repository and installed-source baseline

| Field | Result |
|---|---|
| Workspace | `$HOME/Developer/UMA-M8-Kimi` |
| Branch | `codex/uma-m8-kimi` |
| Starting HEAD/tree | accepted M8-SETUP-G1 commit/tree above |
| Starting worktree/index | clean / empty |
| CLI path | `$HOME/.kimi-code/bin/kimi` |
| Version | `0.34.0` |
| File identity | regular executable; arm64; mode 0755; current-user owned; not a symlink |
| SHA-256 | `9f4337e10da47843f6b550474012a53ba8b30dd665f83b176a5cd479c5f7e859` |
| Team ID | `2J9472RW75` |
| Strict signature | PASS when assessed through the macOS Code Signing subsystem outside the restricted sandbox |
| Provider authentication | Human-confirmed provider-controlled OAuth; credentials remained opaque |
| Provider read cap | 3 / 3 conservatively consumed |

The exact executable hash, version, architecture, ownership, mode, symlink
status, Team ID, and strict-signature result matched the accepted setup
baseline immediately before live probing. A sandboxed Code Signing call
returned a subsystem error; the identical read-only check outside that
restriction verified the binary as valid on disk and satisfying its designated
requirement. Gatekeeper classified the standalone CLI as not an app, which is
not an executable-integrity failure.

## Official control and data contract

Current first-party references:

- [Kimi Code slash-command reference](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/slash-commands.html)
- [Kimi command reference](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html)
- [Official MoonshotAI Kimi Code repository](https://github.com/MoonshotAI/kimi-code)

The installed help and official references establish:

1. There is no standalone `usage` subcommand and no admitted structured
   non-interactive `/usage` command.
2. `-p` / `--prompt` is Agent prompt mode and is prohibited for source reads.
3. The only supported non-Agent candidate is: launch the exact CLI with no
   prompt/session arguments, wait for the idle interactive TUI, positively
   identify the built-in `/usage` autocomplete entry, and submit that exact
   control.
4. Unknown slash input can fall through to an Agent message. The live probe
   therefore did not send Enter unless the provider-owned `/usage` description
   was present.
5. Public source for version 0.34.0 renders plan rows as explicit `percent
   used`, with provider reset hints. Its current labels distinguish a weekly
   summary and a five-hour window. Remaining normalization would be
   `100 - usedPercent` exactly once.
6. The public renderer treats Extra Usage as native money with balance, monthly
   used amount, and a bounded or unlimited monthly charge limit. It is never a
   percentage.

These are official contract facts, not current-account live admission. No raw
public-source fixture was copied into Git.

## Live observation accounting and outcomes

| Field | Result |
|---|---|
| Maximum observations | 3 |
| Conservatively consumed | 3 |
| Successful sanitized observations retained | 0 |
| Automatic retries | 0 |
| Provider prompts / Agent turns / tasks | 0 / 0 / 0 |
| Intentional spend | 0 |
| `/credits` reads | 0 |
| Credential/private-state reads | 0 |
| Raw TUI transcripts retained | 0 |
| Exact Founder values retained | 0 |

Observation classifications:

- Observation 1: the new neutral directory triggered the official workspace
  trust gate. The attempted control was not recognized as `/usage`; no usage
  panel or provider error was retained. The resulting exact task-owned trust
  marker was later removed.
- Observation 2: an idle-TUI footer marker was present and the control sequence
  was sent, but no usage panel or provider error was recognized within the
  bound. Output remained below 16 KiB, the neutral workspace remained empty,
  and teardown/reap completed.
- Observation 3: the probe required the exact provider-owned `/usage`
  autocomplete description before any Enter could be sent. The capped run
  returned no retainable sanitized packet. It is counted, but contributes no
  source-schema evidence.

No raw output, exact percentage, balance, reset, identity, or provider payload
was written to disk or Git. The absence of a retained success means M8 cannot
promote public renderer facts into a live account contract.

## Channel and account-mode adjudication

Current account mode: `unknown/unsupported`. Authentication existence was
Human-confirmed, but no identity or plan data was read.

```text
SHARED MEMBERSHIP: MISSING
KIMI CODE LIMITS: NO-GO
EXTRA USAGE: UNREADABLE
```

- Shared Membership is `MISSING`: the CLI did not produce a retained live
  ecosystem-wide quantity or same-scope denominator.
- Kimi Code Limits are `NO-GO` for current production admission: the public
  source describes weekly and five-hour rows, but no successful current-device
  observation or repeatability proof exists.
- Extra Usage is `UNREADABLE`: the public contract describes the native-money
  schema, but the Founder's absent/disabled/enabled state and exact balance
  availability were not established.

No channel is admitted from documentation alone. Missing is not zero,
unlimited is not 100%, and native money is not a percentage.

## Normalization contract if a future source is admitted

- explicit remaining quantity: retain remaining;
- explicit used percentage: `remainingPercent = 100 - usedPercent` exactly once;
- same-pool used plus total: `(total - used) / total * 100`;
- missing: unavailable, never zero;
- unlimited: semantic unlimited, never 100%;
- Extra Usage: native money, never percent or quota fill.

Array order, visual direction, reset timestamp, plan price, and another Kimi
product's allowance are never identity or normalization authority.

## No-work, teardown, and privacy result

The probe used the exact CLI, an empty owner-only neutral directory, in-memory
bounded PTY capture, a safe environment allowlist, no shell, and exact-path
process evidence. The final control path could not fall through to an Agent
message because Enter was gated on the provider-owned built-in autocomplete
description. Official public source independently routes `/usage` to the local
usage panel and contains a no-model-call test.

`ZERO_AGENT_TURN_CONFIRMED`, `NO_CONVERSATION_CREATED`, `NO_TASK_CREATED`,
`NO_WORKSPACE_MUTATION`, and `NO_RESIDUAL_PROCESS` are supported for the
bounded control attempts. `NO_ATTRIBUTABLE_QUOTA_DECREMENT` is not admitted:
there were no two successful normalized observations to compare, and M8 did
not intentionally spend quota to manufacture that proof.

The task-owned neutral directory, probe, official-source clone, bytecode cache,
and exact workspace-trust marker are cleanup artifacts, not product state or
evidence. They must be absent at closeout.

## Result

```text
NO-GO
SHARED MEMBERSHIP: MISSING
KIMI CODE LIMITS: NO-GO
EXTRA USAGE: UNREADABLE
```

Exactly one next task: `Founder source-direction decision`.

`M8-WEB-G1 remains locked.`
`M8-G2 remains locked.`
