# UMA M5 Claude Admission Decision

Date: 2026-07-28

## Final decision

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

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

1. a trusted Desktop-managed Claude Code 2.1.219 arm64 executable is present,
   but the normal shell launcher is absent;
2. strict native signature and Gatekeeper verification pass for the
   Desktop-managed CLI;
3. the CLI reports `loggedIn: false`, `authMethod: none`, and a first-party
   provider;
4. provider-managed subscription authentication is therefore not active;
5. server-managed settings and effective global policy are unverified;
6. no status-line payload was observed;
7. no valid quota window was observed.

## Why this is SETUP REQUIRED

The source is not rejected as inherently unsuitable. The immediate missing
condition is provider-managed Claude.ai subscription authentication through a
separately authorized owner-controlled setup task.

This is not GO or CONDITIONAL GO because no authenticated provider event or
live quota-window evidence exists.

This is not NO-GO because current official documentation establishes a
potentially admissible structured local protocol, the executable is trusted,
and missing authentication is a setup condition rather than a demonstrated
source failure.

## Authentication and privacy decision

Authentication is **logged out**. The CLI’s allowlisted authentication status
reports no active authentication method. All six prohibited secret or
enterprise route variable names were absent from the task process, but their
absence alone is not used as proof of provider-managed login.

No credential, Keychain value, cookie, session, token, account identity,
prompt, response, transcript, task, workspace history, or private provider
data was accessed.

No Claude provider task ran under M5-G1R. No login page opened. No prompt or
synthetic task was submitted. The reported Human task was not inspected or
altered. No raw status-line JSON was received or retained.

## Configuration decision

The inspected local settings layers contain no settings file and no
`statusLine`, `disableAllHooks`, `allowManagedHooksOnly`, `apiKeyHelper`, or
secret-route key.

This proves only local absence. Server-managed settings and the globally
effective policy remain unverified until the trusted CLI is authenticated.

The temporary probe did not begin. No backup, settings mutation, or
restoration was required, and all temporary trust-check artifacts were
removed.

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

That task must be separately authorized. It may establish provider-managed
subscription authentication and repair the missing user launcher before a
later capability recheck, but M5-G1R itself does not start it.

## M5-SETUP-G1 completion addendum

The M5-G1R decision above remains the historical source-admission result.
Founder-authorized M5-SETUP-G1 later resolved both setup conditions:

- provider-managed paid-subscription authentication is active through
  `claude.ai`;
- the official native `~/.local/bin/claude` launcher resolves in a fresh Zsh
  login shell.

The launcher reports Claude Code 2.1.220 arm64. Strict Anthropic Developer ID
signature verification and `claude doctor` passed. All prohibited secret,
token, and cloud-provider route names remained absent from both the setup
process and the final fresh shell.

This setup result does not admit the status-line source and makes no quota
claim. No prompt, provider task, status-line configuration, status-line event,
usage value, credential, account identity, or UMA runtime was accessed or
created.

M5-G2 remains locked. Exactly one next task is:

**M5-G1R2**
