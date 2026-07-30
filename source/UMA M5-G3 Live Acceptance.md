# UMA M5-G3 Live Acceptance

Date: 2026-07-29

## Evidence boundary

This record contains classifications and acceptance results only. It contains
no live quota percentage, reset timestamp, raw provider payload, credential,
identity, session, transcript, prompt, response, task, tool, workspace, or
repository content.

## Candidate and checkpoints

- predecessor: `490e9a88d07a22d1d4d98984494594d16dab7dbb`;
- preflight candidate:
  `/private/tmp/uma-m5-g3-preflight-490e9a88d07a/UMA.app`;
- Human Enable Integration checkpoint: PASS;
- Human normal-response checkpoint: PASS;
- provider-generated relay callback: observed;
- sanitized accepted event count: at least one;
- rejected-event failure observed: no;
- helper daemon after callback: absent.

## Live field availability

- Five-hour window: present valid
- Five-hour reset: valid
- Seven-day window: present valid
- Seven-day reset: valid
- Version: not surfaced by the acceptance UI

The protocol admits a window only when its used percentage and matching reset
epoch both pass strict validation. No live value is copied into this record.

## Semantic and surface results

- Used-to-remaining conversion: MATCH
- selected-window policy: centralized Maximum Decrement, PASS
- selected-window reset association: PASS
- main-panel order: Codex → Claude Code → WorkBuddy
- Claude collapsed card: remaining value, selected window, and connected
  freshness state present
- Claude expanded card: independent five-hour and seven-day remaining windows
  present
- Desktop Assistant: Claude absent; Codex and WorkBuddy preserved
- shared Manual Refresh: Claude configuration health check only; no synthetic
  Claude request
- WorkBuddy transient read failure: isolated from Claude and Codex
- WorkBuddy recovery: PASS
- provider failure isolation: PASS

## Configuration and privacy results

- pre-task settings class: one provider-owned `theme` preference, no
  `statusLine`;
- final settings SHA-256 matched the pre-task value: PASS; the digest remains
  transient and is not retained in this record;
- owner-only backup and metadata: PASS;
- exactly one relay wrapper: PASS;
- recursion and literal-secret checks: PASS;
- owner-only socket and one candidate listener: PASS;
- Repair Relay through the visible Settings control: PASS;
- Disable Integration through the visible Settings control: PASS;
- exact settings bytes, owner, mode, and theme restoration: PASS;
- Exact settings restore: PASS
- final `statusLine`: absent;
- final socket, listener, helper process, backup, and metadata: absent;
- Claude subscription authentication: provider-managed and preserved;
- UMA network request for Claude: none;
- credential, transcript, raw-payload, and private-data path: none.

## Runtime defect and repair

`M5G3-001` — after a successful live admission, the visible Disable
Integration action restored the settings file but the registry retained the
last Claude card because connector shutdown published a transient waiting
state. The connector now publishes an inactive snapshot on disconnect, which
withdraws only Claude while preserving Codex and WorkBuddy.

Automated retest results:

- disconnect/withdrawal and failure-to-fresh focus: PASS;
- M5-G3 focused suite: 6/6 PASS;
- combined M5 suites: 84/84 PASS;
- full regression suite: 409/409 PASS across 45 suites;
- Debug, Release, strict-concurrency Release, and strict relay-helper builds:
  PASS.

## Delivery state

The final commit, tree, package identity, hashes, automated verification, and
clean Git state are recorded after the commit-exact delivery gate.
