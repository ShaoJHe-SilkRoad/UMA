# UMA M6 Antigravity Connector Contract

**Goal:** M6-G2
**Status:** Implementation contract
**Source:** Official Antigravity CLI only

## Source and process boundary

UMA may invoke only `$HOME/.local/bin/agy`, admitted version `1.1.11`, without a
shell and with the exact arguments `--output-format`, `json`, `-p`, `/usage`.
The process uses closed stdin, an empty UMA-owned working directory, no injected
credential environment, a 15-second soft timeout, a separate 20-second hard
resource ceiling, 64 KiB stdout and 16 KiB stderr caps, and one completely
terminated/reaped owned child. Raw output is never persisted. Login-required
classification during routine refresh suspends the source and requires a
separate Human setup action.

## Decoder boundary

Admit only `command.name == usage`, the groups/buckets shape, a bounded stable
bucket ID, finite `remaining_fraction` in `0...1`, optional bucket-scoped ISO
reset, schema-only group/window fields, safe CLI version and local observation
time. Remaining percentage equals `remaining_fraction × 100` once. Never clamp,
infer used-versus-remaining, convert unavailable to zero, aggregate pools, use
array position/reset/balance as identity, or synthesize Credits. Duplicate
bucket IDs and ambiguous/private/future schema fail closed.

Response, conversation, prompt, task, tool, message, project, free text, exact
provider counters, identity, plan, billing, login URL, browser state, cookie,
token, credential, workspace, source/VCS and raw payload fields are prohibited.

## Scheduler, Settings and admission

One source-owned scheduler reads on launch and five minutes after each completed
cycle, with a three-minute minimum, one in-flight read, trigger coalescing and
no catch-up or immediate retry. A current successful structured read with one
valid bucket is required for fresh admission. One provider failure affects only
Antigravity.

Settings expose Check, official Install/Open, Login Required,
Connected/Refreshing/Fresh/Cached/Stale, Auto Refresh, Sync Now, Disable and
source/privacy transparency in EN/zh-CN. The Settings model receives injected
operations and owns no process, decoder, credential, browser or persistence.

## Shared and frozen boundaries

Order is Codex → Claude Code → WorkBuddy → Google Antigravity. Shared edits add
Antigravity-only branches. M5 frozen files and existing provider mechanisms are
unchanged. Four providers do not force Minimalist. Views own no process, timer,
decoder, cache or selected-window policy. The connector publishes at most two
channels, uses a safe `sourceVersion` of at most 32 characters, and does not
change the existing six-scalar local-activity persistence payload.
