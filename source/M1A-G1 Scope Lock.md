# M1A-G1 Scope Lock — Codex Dual-Source Usage Connector

## Fresh baseline

- Workspace: `/Users/juliushe/Desktop/CodexUsageMonitor`
- Branch: `main`
- HEAD / `origin/main`: `cd62d4b235b5e78a9045a36909aa656948cf54ab`
- Index: empty before M1A-G1 work
- Existing M1-era worktree changes are intentionally dirty and must not be
  staged wholesale or treated as current runtime proof.

## M1 classification

| Class | Current material | M1A-G1 treatment |
| --- | --- | --- |
| Retained connector foundation | executable resolver, app-server transport/session/client, normalized usage models, `UsageStore`, session token estimator, ledger | Diagnose against the installed schema and repair only proven connector defects. |
| Obsolete login detours | managed sign-in-page APIs, browser-oriented authorization states, official ChatGPT.app launch seam | Remove or isolate from the production connector critical path; M1A-G1 never owns browser login or ChatGPT.app launch as authentication. |
| Frozen visual work | panel material/border, glass, status/menu layout, iconography, typography, animation, general hierarchy | No styling or geometry edits. Functional state wording only if indispensable to a connector failure. |
| Unrelated WIP and generated artifacts | `.swiftpm/`, existing `.build/`, preview renderer/harness, M1 acceptance documentation and packages | Preserve; keep generated/private evidence unstaged. |

## Evidence contract

- Installed official CLI/schema, real app-server reads, and privacy-safe local
  metadata determine behavior; old M1 documents, fixtures, and screenshots do
  not prove this Goal.
- Only `account/read`, `account/rateLimits/read`, and `account/usage/read`
  are used for live provider validation, within the authorized read budget.
- Local activity accepts only allowlisted metadata and aggregate token events;
  no credential, cookie, Keychain, raw auth database, prompt, response, tool,
  source, transcript, account identity, or raw provider payload is retained or
  reported.
- A valid account channel and a valid local channel remain independently
  attributable and retainable when the other fails.
- M1A-G2, Claude Code, multi-provider UI, visual redesign, remote publishing,
  release, and deployment are out of scope.

## Completion and delivery gate

PASS requires an independently auditable, uniquely packaged temporary app
with real account data and supported local activity data reaching the existing
store/UI, refresh/recovery proof, bounded stability evidence, privacy/package
audits, exact staging, and one local commit. Until then no commit is allowed.
