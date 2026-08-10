# Usage Monitor Altoget — M7 Plan

**Milestone:** M7 — Cursor Support
**Version:** 1.0
**Status:** Source admission only; runtime work locked
**Accepted parent commit:** `a6b846ea2785448c4d4e51ec0e775ff9220d33f5`
**Accepted parent tree:** `d7f789c3d2fd4e98a43256737b733c37fe5b0c81`

## 1. Result target

M7 may make Cursor the fifth UMA provider only after a separate source-admission
Goal proves a current, provider-owned, structured quota source that satisfies
UMA's privacy, authentication, freshness, identity and no-inference rules.
Cursor remains hidden and unsupported until that gate passes.

The accepted provider baseline is:

```text
1. Codex
2. Claude Code
3. WorkBuddy
4. Google Antigravity
5. Cursor — not yet admitted
```

M7 must preserve the first four providers exactly. It must not modify the
protected Desktop application or any checksum-locked `source/reference/**`
record.

## 2. Source priority

Investigate Cursor sources in this order, stopping at the first admissible
source:

```text
1. official local structured Cursor source
2. official documented local CLI read-only command
3. official provider-owned hook or status source
4. provider-controlled account/browser login, only if required and separately admitted
5. unsupported
```

Source admission is not permission to implement the connector. M7-G1 returns
one of `GO`, `CONDITIONAL GO`, `SETUP REQUIRED` or `NO-GO`. `GO` or an accepted
`CONDITIONAL GO` unlocks M7-G2. `SETUP REQUIRED` permits only a separately
authorized M7-SETUP-G1. `NO-GO` keeps Cursor unsupported unless the Founder
chooses a new source direction.

## 3. Hard privacy and source boundaries

M7 must not use or request:

- a user-entered API key, copied token or pasted credential;
- password, OAuth/access/refresh token, cookie, Keychain secret, browser
  profile, authentication database or private application database;
- an undocumented/private endpoint or replayed provider request;
- manual quota, manual deduction or a locally estimated balance;
- activity, token count, cost, task history or work performed recast as current
  account quota;
- UI scraping, Accessibility extraction, OCR, screenshots, process injection,
  memory inspection or packet capture as a stable source;
- a provider prompt/task or intentional quota spend merely to create evidence.

Authentication must remain provider controlled. UMA may retain only the
minimum normalized quota presentation admitted by the source contract. Raw
provider payload, identity and credential material must not enter Git, logs,
packages, screenshots or durable evidence.

M6's standing process-inspection contract remains mandatory: inspect only an
exact executable path/name, exact PID, required parent/child relation, process
count, bounded resource counters and exit/absence state. Broad process command
lines, unrelated argv, environment dumps and provider session metadata are
prohibited.

## 4. Five-provider density contract

Provider density remains centralized and source independent:

```text
0 through 4 visible providers → Regular mode remains permitted
5 or more visible providers   → Minimalist mode is forced
```

Cursor is expected to prove the first real four-to-five transition only after
its source, connector and live presentation are separately accepted. M7-B0 and
M7-G1 must not register Cursor, expose a Cursor card or alter Desktop Assistant.

## 5. Goal sequence

```text
M7-B0
→ M7-G1
→ M7-SETUP-G1 only if required
→ M7-G2
→ M7-G3
→ M7DBG-G1
→ M7A-G1
→ M7ADBG-G1
→ M7-CLOSE-G1
```

Every Goal requires direct authorization and ends under Completion Lock. No
Goal starts automatically. M7-G1 — Cursor Official Source, Authentication, and
Schema Admission — is the only task permitted after M7-B0.

## 6. M7-B0 delivery contract

M7-B0 creates only this plan, the Goal map, the Scope Lock, the source-admission
research brief and a focused deterministic contract test. It performs no
Cursor installation, update, login, authenticated read, provider process
launch, account/browser access, runtime registration, UI integration or
package replacement.

Required baseline evidence includes exact branch/HEAD/tree, a clean worktree
and empty index, the deterministic serial test suite, the project-required
build matrix, M5 and provider protected-file comparison, whitespace and
privacy/identity/secret audits. Stage only exact M7-B0 paths and create one
local commit:

```text
docs(m7): establish Cursor source-admission plan
```

Remote delivery, installation, release, signing, notarization and deployment
remain unauthorized.
