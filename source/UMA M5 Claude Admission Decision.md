# UMA M5 Claude Admission Decision

Date: 2026-07-28

## Final decision

**SETUP REQUIRED — CLAUDE CODE CLI NOT INSTALLED**

## Decision basis

The current official Claude Code documentation defines a local status-line
JSON source that can potentially carry:

- five-hour used percentage and reset epoch;
- seven-day used percentage and reset epoch;
- the Claude Code version.

The callback itself is local and does not consume provider tokens. Rate-limit
fields are documented for Claude.ai Pro/Max subscriptions after the first
provider response, and the two windows may be independently absent.

The current device cannot prove that capability because:

1. the official `claude` executable is not installed or resolvable;
2. executable identity, version, architecture, hash, signature, and trust are
   therefore unavailable;
3. provider-managed authentication is not proven;
4. server-managed settings and effective global policy are unverified;
5. no status-line payload was observed;
6. no valid quota window was observed.

## Why this is SETUP REQUIRED

The source is not rejected as inherently unsuitable. The immediate missing
condition is installation of the official Claude Code CLI through a separately
authorized owner-controlled setup task.

This is not GO or CONDITIONAL GO because no installed or live quota-window
evidence exists.

This is not NO-GO because current official documentation establishes a
potentially admissible structured local protocol, and the missing runtime is a
setup condition rather than a demonstrated source failure.

## Authentication and privacy decision

Authentication remains **unknown**. Absence of secret-route variable names in
the task process does not prove provider-managed login.

No credential, Keychain value, cookie, session, token, account identity,
prompt, response, transcript, task, workspace history, or private provider
data was accessed.

No Claude process or provider task ran. No login page opened. No prompt or
synthetic task was submitted. No raw status-line JSON was received or retained.

## Configuration decision

The inspected local settings layers contain no settings file and no
`statusLine`, `disableAllHooks`, `allowManagedHooksOnly`, `apiKeyHelper`, or
secret-route key.

This proves only local absence. Server-managed settings and the globally
effective policy remain unverified until an installed authenticated CLI can
report its loaded sources.

No settings mutation or restoration was required.

## Locked boundaries

M5-G2 remains locked. This decision does not authorize:

- Claude Code installation or login;
- a provider response;
- status-line configuration;
- production relay or connector work;
- account-web fallback;
- UMA building or installation;
- Desktop application modification.

## Exactly one next task

**M5-SETUP-G1**

That task must be separately authorized. It may establish the official
installation and trust evidence required for a later capability recheck, but
M5-G1 itself does not start it.
