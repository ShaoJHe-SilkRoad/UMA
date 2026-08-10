# UMA M7 Cursor Local Source Dossier

**Goal:** M7-G1
**Date:** 2026-08-10
**Decision:** `CONDITIONAL GO — FALLBACK ARCHITECTURE REQUIRES FOUNDER DECISION`
**Direct local/CLI quota source:** `NO-GO`
**Only next task:** `Founder provider-controlled browser fallback architecture decision`

## Accepted baseline and scope

M7-G1 began from the clean `codex/uma-m7-cursor` branch at accepted M7-B0
commit `fb92f74bf8a702b3143b98371c8bfd16241b02f5` and tree
`d531a8d8bc5f848c0af6d12bb498889ce36e4aab`. The accepted provider baseline is
Codex, Claude Code, WorkBuddy and Google Antigravity. No product runtime,
registry, scheduler, Settings, main-panel, Desktop Assistant, package or
installed application change is part of this Goal. M7-G2 remains locked.

## Current-device inventory

The exact standard Cursor application and CLI locations were absent. Neither
the current `agent` entrypoint nor the compatibility `cursor-agent` entrypoint
resolved on `PATH`. Exact bundle registration, version/build, executable
architecture, owner/mode, symlink chain, signature, Gatekeeper, provenance and
installed help are therefore **UNAVAILABLE**, not failed.

No broad filesystem, process-argument or environment discovery was used. Cursor
private state, browser state, Keychain, cookies, profiles, authentication
databases, caches and logs were not inspected.

## Official candidate matrix

| Priority | Candidate | Authority | Current finding | Admission |
|---:|---|---|---|---|
| 1 | Structured local source | Official source required | No installed artifact and no documented local quota schema found | No direct source |
| 2 | Cursor CLI quota command | Official CLI and `/usage` exist | Official changelog defines `/usage` as activity streaks and stats; no noninteractive machine-readable plan-quota contract is documented | No direct source |
| 3 | Cursor hook/status surface | Official lifecycle hooks and auth status exist | Hooks concern agent lifecycle; `status` reports authentication/account endpoint configuration; no quota event/getter schema found | No direct source |
| 4 | Cursor dashboard Usage | Official provider-controlled human surface | Current plan usage is documented as visible in the dashboard, but no public individual structured schema or admitted bridge exists | Conditional architecture candidate |
| 5 | Unsupported/private techniques | Not admissible | Tokens, cookies, Keychain, private endpoints, local databases, UI scraping and estimates are prohibited | Rejected |

Official references:

- Cursor CLI installation: <https://cursor.com/docs/cli/installation>
- Cursor CLI use and structured agent output: <https://cursor.com/docs/cli/using>
- CLI `/usage` activity feature: <https://cursor.com/changelog/cli-jan-16-2026>
- CLI authentication/status reference: <https://docs.cursor.com/en/cli/reference/parameters>
- Human-visible plan usage: <https://docs.cursor.com/account/pricing>
- Chat usage visibility: <https://cursor.com/changelog/1-4>
- Team Admin API: <https://docs.cursor.com/en/account/teams/admin-api>
- Agent lifecycle hooks: <https://cursor.com/changelog>

## Command and schema findings

The official CLI supports JSON output only with print-mode agent execution.
Official documentation states that print mode can use agent tools, including
filesystem and shell tools. It is not a quota transport and was not executed.

The official `/usage` slash command shows activity streaks and stats. Current
official documentation does not establish plan balance, a remaining/used
semantic, reset period, freshness marker, stable pool identifier, schema
version, JSON output or a noninteractive read-only invocation.

```text
Live schema: UNAVAILABLE
Native quota unit: UNAVAILABLE
Remaining/used semantic: UNAVAILABLE
Reset semantic: UNAVAILABLE
Stable pool identity: UNAVAILABLE
Repeated-read stability: UNAVAILABLE
No-provider-work behavior: UNAVAILABLE
Automatic refresh feasibility: UNAVAILABLE
```

Cursor plan documentation describes dollar-valued API agent usage, variable
bonus capacity, model-dependent depletion and request-based team limits.
Marketing request equivalents are approximate. M7 must not invent a single
percentage or denominator from those plan descriptions.

## Authentication and rejected routes

Official browser login is provider controlled, but no admissible quota source
was proven behind it. Authentication on this device remains **UNOBSERVABLE**.
Absent artifacts are not evidence of logout.

The Team Admin API is official but rejected for this product source: it requires
an API key, exposes team/member identity and event/spend data, and does not prove
an individual current remaining-quota contract. API key, copied token, cookie,
Keychain, private endpoint, browser-profile import and internal database routes
remain rejected.

## Live operation accounting

```text
Authenticated quota reads: 0/3
Cursor login/browser actions: 0
Provider prompts/tasks: 0
Intentional quota spend: 0
Credential/private-state reads: 0
Automatic retries: 0
```

No candidate passed the authority, interface and privacy gates, so the live read
gate correctly remained closed.

## Result

The direct local/CLI source path is `NO-GO`: current quota is unavailable under
an official documented structured read-only contract. Installing the CLI would
not repair the missing quota contract, so this is not `SETUP REQUIRED`.

The M7 Goal explicitly permits feasibility classification of an official
provider-controlled account/browser fallback. Cursor documents a human-visible
Usage surface, but using it would require a new browser integration and privacy
surface. Therefore the primary M7-G1 result is:

`CONDITIONAL GO — FALLBACK ARCHITECTURE REQUIRES FOUNDER DECISION`

This is not direct implementation admission. M7-G2 remains locked. The only
next task is `Founder provider-controlled browser fallback architecture decision`.
