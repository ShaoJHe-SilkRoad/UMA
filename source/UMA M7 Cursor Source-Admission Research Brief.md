# UMA M7 Cursor Source-Admission Research Brief

**Version:** 1.0
**Goal:** M7-B0
**Current-device decision:** `UNADMITTED — M7-G1 DOSSIER REQUIRED`

## 1. Purpose

This brief defines the questions and proof standard for M7-G1. It does not
claim that Cursor, a Cursor CLI, a quota command, authentication or a schema is
present on this Mac. M7-B0 performed no Cursor installation, update, launch,
login, account/browser access, authenticated request or provider read.

## 2. Candidate source order

M7-G1 must evaluate, in order:

1. an official local structured Cursor source;
2. an official documented local CLI read-only command;
3. an official provider-owned hook or status source;
4. provider-controlled account/browser login only when required and separately
   admitted;
5. unsupported.

Third-party wrappers, private endpoints and inferred usage do not become
official merely because they return structured data.

## 3. Mandatory proof matrix

| Area | Required proof before GO |
|---|---|
| Identity | Exact official artifact/source identity, version, provenance and stable invocation/contract |
| Quota | Current provider-native remaining or used quota with unambiguous conversion semantics |
| Windows | Stable provider-owned window/pool identity; no unrelated pool merging or inferred labels |
| Structure | Documented or repeatedly stable machine-readable schema with strict bounded decoding |
| Freshness | Current observation behavior and safe reset/age semantics |
| Authentication | Provider controlled; UMA receives no password, token, cookie, Keychain secret or browser profile |
| Operation | Read-only; no provider prompt/task, conversation or intentional quota spend |
| Privacy | Strict allowlisted projection; no identity, raw content, credential or private workspace data retained |
| Lifecycle | Bounded process/request, cancellation, timeout, teardown and fail-closed behavior |

Optional labels, resets or secondary metadata may support `CONDITIONAL GO` only
when current quota, stable identity, structure, authentication, privacy and
no-provider-work behavior are already proven. Missing primary quota or a source
that requires prohibited credentials/private access is `NO-GO`, not a runtime
workaround.

## 4. Decision and follow-on rules

- `GO`: M7-G2 may be proposed after Founder acceptance.
- `CONDITIONAL GO`: only an explicitly accepted optional gap may remain.
- `SETUP REQUIRED`: M7-SETUP-G1 is the only next task; admission must be rerun.
- `NO-GO`: Cursor stays unsupported and hidden.

No decision authorizes a Cursor connector, card, scheduler, package or live UI
by itself. Runtime work starts only in M7-G2 after source admission is accepted.

## 5. Product boundary carried into later Goals

If admitted, Cursor is provider five. Later acceptance must prove stable order
`Codex → Claude Code → WorkBuddy → Google Antigravity → Cursor`, shared
main-panel/Assistant semantics, and automatic forced Minimalist at five visible
providers. Those behaviors are not implemented or exercised in M7-B0.

## 6. B0 accounting

```text
Cursor executable launches: 0
Cursor authenticated reads: 0
Cursor login/browser actions: 0
Cursor prompts/tasks: 0
Intentional Cursor quota spend: 0
Cursor runtime/configuration changes: 0
```

**Only next task:** `M7-G1 — Cursor Official Source, Authentication, and Schema Admission`
