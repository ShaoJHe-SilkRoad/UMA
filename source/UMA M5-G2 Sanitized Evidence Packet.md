# UMA M5-G2 Sanitized Evidence Packet

Date: 2026-07-29

## Decision boundary

This packet contains only offline implementation and synthetic-fixture
evidence. It contains no real Claude quota value, reset timestamp, raw
status-line payload, provider content, account identity, credential, prior
status-line command, settings backup, session, prompt, response, transcript,
task, tool, workspace, or repository content.

Live status:

**LIVE CLAUDE QUOTA NOT YET VALIDATED**

## Provenance

- branch: `codex/uma-m5-claude`;
- predecessor HEAD: `2c7db84aa98dbf8056a2184fc7f4f7d28b5914be`;
- predecessor tree: `85490a87c6bcbcb7c51418dc7a052640447e8a16`;
- governing verdict consumed:
  `GO — CLAUDE STATUS-LINE QUOTA SOURCE PROVEN`;
- final commit, tree, package hashes, and package path are recorded after the
  commit-exact delivery gate.

## Architecture evidence

The implemented offline route is:

Claude official status-line JSON → bounded relay projection → versioned
allowlisted packet → owner-only Unix-domain socket → passive Claude connector
→ provider registry → usage store → shared presentation policy.

The relay:

- forwards exact standard input to a preserved safe prior command through a
  pipe;
- streams prior standard output unchanged and preserves its exit result;
- independently publishes the sanitized packet when safe;
- publishes nothing for malformed or unsafe input;
- projects only allowlisted quota fields while publishing no expanded or
  private fields;
- uses no network, credential, transcript, account, or persistence path;
- exits without effect when the UMA listener is absent.

The packet can represent only:

- schema version;
- bounded Claude version;
- optional five-hour used percentage and its reset epoch;
- optional seven-day used percentage and its reset epoch;
- relay observation time.

`SharedUsagePresentationPolicy` owns the only used-to-remaining conversion.
The connector and views do not repeat it.

## Configuration evidence

All settings operations use isolated synthetic roots. Coverage proves:

- absent, empty, and theme-only settings;
- a safe existing status-line object and its options;
- exact backup and exact byte/permission restoration;
- enable, check, changed-helper repair, disable, and uninstall;
- concurrent unrelated modification rejection;
- corrupt, linked, nonregular, managed, hook-disabled, and future-schema
  rejection;
- no command or secret disclosure;
- no backup, metadata, or socket enters Git or the package.

The real onboarding preference remains:

**ACCEPTED PROVIDER-OWNED ONBOARDING PREFERENCE — NOT A PROBE ARTIFACT**

It was not modified by M5-G2.

One provider-owned Claude project-history pathname from the earlier,
Human-authorized setup session remains outside the repository. M5-G2 did not
create or inspect its contents. It is retained unchanged because it is
provider-owned history, not an M5-G2 probe artifact.

## Verification evidence

- focused M5-G2 suites: 48/48 PASS across three suites;
- affected Codex, WorkBuddy, registry, shared-presentation, and Desktop
  Assistant suites: 141/141 PASS across 13 suites;
- full regression suite: 403/403 PASS across 44 suites;
- Debug build: PASS;
- Release and relay-helper build: PASS;
- strict-concurrency Release with warnings treated as errors: PASS;
- active listener takeover, stale socket recovery, owner permissions, peer
  ownership, callback burst, cancellation, and app-absent no-op: PASS;
- passive registry withdrawal and failure-to-fresh recovery: PASS;
- source transparency, English and Simplified Chinese labels, scrollable
  Settings, accessibility identifiers, and absence of credential controls:
  PASS;
- Claude hidden before current admission and hidden from Desktop Assistant:
  PASS;
- package, final privacy, and Git results are appended only after their final
  gates pass.

## Delivery lock

One local commit is authorized:

`feat(connectors): add Claude Code status-line relay`

One commit-exact offline package is authorized under `/private/tmp`.
Installation, live relay enablement, provider tasks, push, release, and M5-G3
execution remain prohibited.

Exactly one next task after M5-G2 is:

**M5-G3**
