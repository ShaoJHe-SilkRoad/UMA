# UMA M3-G1 Scope Lock

Date: 2026-07-24

## Repository baseline

- Workspace: `/Users/juliushe/Developer/UMA-M3`
- Branch: `codex/uma-m3`
- Starting HEAD: `26a0d8fd84db652ca5359fd53809ac9017066c80`
- Starting tree: `4269495794eef92560a9db04cd00d225af137a2a`
- Starting worktree: clean
- Starting index: empty
- M3 product changes at start: none
- Remote actions at start: none

If HEAD, tree, branch, worktree, or index diverges before Claude inspection,
M3-G1 stops with `M3-G1 BASELINE DIVERGENCE — CLAUDE INSPECTION NOT STARTED`.

## Governing authority

- `Scroll.md` 1.3 — `9623edc4f5a82fcf81893b5e93f23d2d4e373cbda3a3e856bd0510e7b705dc2e`
- `M3_Plan.md` 1.1 — `e5cc0dc24c0810d020d7f06837ba921869bf6012e35e3c484c22920ededdaae2`
- `M3_Goal.md` 1.1 — `0ae2c360b7c98d7cdc5e5dab6f7a4289976ff60092cdeeca304148783ac7bde6`
- `UMA_Logic_1.3.md` 1.3 — `c73cde523d92671213e4aa00cb93d01f6e4f9258ac8268891ea76dea61b2d064`
- `Goal_Mode_2.0.md` 2.0 — `9035f2574938752f40a50346c33bcc32db33c70526989fc14825d51ff1f6d5e7`
- `Dev_Default_2.1.md` 2.1 — `d2997e2039ef2418c98bce66b516e2a9f734394b338abd383fc92f9e6260e598`

Current live repository evidence and current Founder instructions outrank stale
historical documents.

## Installed Claude discovery boundary

Permitted:

- normal-shell command resolution for `claude`;
- exact executable and symlink-chain identification;
- version, SHA-256, architecture, and relevant CLI help;
- installed public status-line/settings documentation or schemas.

Candidate executable paths are unresolved until the bounded command-resolution
inventory completes. No PATH change, install, upgrade, disassembly, or
decompilation is permitted.

### Resolved inventory

- Normal interactive login shell: `claude` does not resolve.
- Standard candidates checked and absent:
  `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`,
  `/usr/bin/claude`, `$HOME/.local/bin/claude`, and
  `$HOME/.local/share/claude`.
- Claude Code version, executable path, symlink chain, SHA-256, and architecture:
  not applicable because no Claude Code executable is installed.
- `/Applications/Claude.app` exists as Claude Desktop
  (`com.anthropic.claudefordesktop`, version `1.24012.1`); it is not a Claude
  Code CLI installation and is not admitted as the requested source.
- Final installation classification: `NOT INSTALLED`.

## Configuration boundary

Permitted only when required to determine effective official `statusLine`
configuration:

- user settings candidate `~/.claude/settings.json`;
- officially documented project/local/managed settings layers;
- the exact active script referenced by `statusLine`, when present.

Only configuration structure, precedence, `statusLine` representation,
invocation, output behavior, recursion risk, environment assumptions, and
preservation requirements may be retained. Unrelated settings and private
values must not be displayed or copied.

### Resolved configuration inventory

- `CLAUDE_CONFIG_DIR`: unset in both the task process and GUI-session
  environment.
- User settings: `$HOME/.claude/settings.json` absent.
- Project settings: `<M3>/.claude/settings.json` absent.
- Local settings: `<M3>/.claude/settings.local.json` absent.
- macOS managed preferences domain: no `statusLine` value.
- System managed settings file and drop-in directory: absent.
- Server-managed settings: unobservable without an installed, signed-in Claude
  Code session; global effective configuration therefore remains unverified.
- Local status-line classification: `NO EXISTING STATUS LINE`.
- No settings file or referenced script was read beyond the allowed
  existence/`statusLine` checks, and no Claude configuration was modified.

## Temporary evidence and live authority

- Task-owned root: `/private/tmp/uma-m3-g1-*`
- Probe, sanitized snapshots, timing data, configuration backups, and raw
  ephemeral input are excluded from Git.
- Maximum live Claude requests: 2
- Total provider spend cap: USD $0.50
- Maximum live duration: 20 minutes
- No automatic retry beyond the two-request total.

Capability resolution consumed zero live requests, zero live minutes, and
USD `$0.00`. Because Claude Code is not installed, a probe, wrapper, raw
payload capture, configuration backup, and temporary settings mutation are not
justified and were not created.

## Privacy allowlist

Only when observed and scope-correct:

- Claude Code version;
- model identifier and display name;
- provider-supplied plan-limit usage/reset fields;
- context-window used/size/percentage;
- current-session cost, duration, token aggregates, and line-change aggregates;
- safe event timestamp;
- safe schema/version metadata;
- field paths, JSON types, safe enum/value shapes, payload size, and timing.

## Forbidden data

- credentials, tokens, cookies, Keychain, auth stores, or auth internals;
- account email, account ID, organization, username, or billing identity;
- transcript path or contents;
- prompt, response, tool input, or tool output contents;
- source-code contents or raw source paths;
- working-directory or repository identity;
- raw session ID;
- raw provider payload in Git or normal logs;
- OneDrive content or metadata.

## Exact tracked edit scope

Planned tracked files:

- `source/UMA M3 Scope Lock.md`
- `source/UMA M3 Claude Capability Dossier.md`
- `source/UMA M3 Claude Configuration and Restore Contract.md`
- `source/UMA M3 Claude QA Issue Ledger.md`

No production connector, product source, package script, or shared test
infrastructure may change. A tracked probe helper or focused test may be added
only after this Scope Lock is amended with an exact file list and justification.
The initial plan uses a task-owned external probe and records only sanitized
results in the four documents.

## Generated evidence exclusions

Never stage:

- `/private/tmp` evidence or backups;
- raw or sanitized payload snapshots;
- logs, screenshots, process captures, or configuration backups;
- `.build`, `.swiftpm`, generated binaries, caches, or account data.

## Roles

- Source / Protocol Auditor: architecture-audit agent
- Configuration Steward: gap-inventory agent
- Privacy Steward and initial QA Runner: QA-baseline agent
- Probe Operator and Documentation Owner: primary Codex agent
- Independent Examiner: assigned after restoration and tracked-diff completion

## Delivery authority

After technical, privacy, restoration, QA, and Examiner gates pass:

- stage only the four exact approved records;
- independently audit the staged index;
- create one local commit:
  `docs(m3): record Claude Code source capability`;
- do not amend or push.

The resolved tracked scope remains exactly the four documents listed above.
No helper or focused test is added because there is no installed runtime,
payload, configuration mutation, or executable sanitizer implementation to
exercise.

## Completion Lock

Stop after the final report and local commit. Do not install a production relay,
implement `ClaudeCodeUsageConnector`, begin M3-G2, inspect WorkBuddy/Manus/other
providers, or push, tag, release, notarize, deploy, or publish.
