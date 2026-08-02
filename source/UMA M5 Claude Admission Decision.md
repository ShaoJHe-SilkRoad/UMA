# UMA M5 Claude Admission Decision

Date: 2026-07-31

## Current M5-DESKTOP-D1 decision

**DESKTOP LOCAL NO-GO — STATUSLINE NOT EXECUTED**

The bounded invocation-first diagnostic conclusively classified the completed
Human-controlled Claude Desktop Code Local response as **Outcome A**:

- invocation marker: absent;
- JSON parse: not reached;
- `rate_limits`: unobserved;
- five-hour window: unobserved;
- seven-day window: unobserved;
- production relay delivery: not attempted;
- connector delivery: no packet existed to accept, reject, or lose.

The temporary command was correctly installed before the newly opened Desktop
Local session, its marker-first behavior was proven independently of quota
validity, and no managed-policy or neutral-folder override blocked it. The
absence is therefore a Desktop callback absence, not evidence that the
Desktop payload lacks quota fields and not an UMA relay defect.

The exact prior Claude settings bytes, owner, and mode were restored. All
task-owned probe, marker, backup, temporary settings, and neutral-folder
artifacts were removed, and the task-owned UMA candidate was stopped. No
prompt, response, raw payload, exact quota, reset time, credential, identity,
session, transcript, private data, or account-web state was accessed or
retained.

The command-line local source remains separately proven. The Desktop Local
route is NO-GO for automatic status-line delivery on current evidence. An
account-web fallback is now genuinely required if automatic Claude Desktop
usage remains a product requirement, but no fallback was activated or
implemented in M5-DESKTOP-D1.

The existing 18-file M5-LIVE-R1 product diff remains preserved and unstaged;
this decision adds only the two M5 source-admission records. Exactly one next
task is **M5-WEB-G1 — Claude isolated account-web usage-source dossier**.

## Current M5-SETUP-G1R decision

**GO — CLAUDE STATUS-LINE QUOTA SOURCE PROVEN**

Trust, provider-managed Claude.ai subscription authentication, normal-shell
continuity, command-line-only status-line activation, one Human-controlled
post-response callback, both documented quota windows, both reset epochs, and
the bounded version field are proven.

The real quota values and reset times were discarded. Only present/valid
classifications and the decimal-aware used-to-remaining validation result were
retained long enough to make this decision. Privacy and task-owned temporary
artifact cleanup passed.

M5-G2 is admitted as the only next task. No production relay, connector,
account-web fallback, or other provider work is included here.

## Historical M5-G1R decision

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

## M5-G1R2 decision basis

The recheck proved:

1. the official native Claude Code 2.1.220 arm64 executable is trusted;
2. `claude doctor` passes;
3. provider-managed Claude.ai subscription authentication is active;
4. prohibited secret and cloud-provider routes are inactive;
5. the original user settings file and `statusLine` were absent;
6. local managed-settings and managed-preferences files were absent;
7. a temporary owner-only allowlist probe was synthetically validated;
8. one normal Human-controlled CLI response completed;
9. no status-line callback reached the probe;
10. no valid five-hour or seven-day quota window was observed;
11. exact absence-state restoration and temporary-artifact deletion passed.

The used-to-remaining rule remains locked as:

`remainingPercent = 100 - usedPercentage`

It is applied exactly once only after a finite 0-through-100 provider value
passes validation. Missing, malformed, negative, over-100, and nonfinite
values fail closed. The two windows and their reset epochs remain independent.
Maximum Decrement receives remaining percentages only.

The current classification is:

| Capability | Result |
|---|---|
| Five-hour used and reset | unsupported on current evidence |
| Five-hour remaining | unavailable |
| Seven-day used and reset | unsupported on current evidence |
| Seven-day remaining | unavailable |
| Version payload field | unsupported on current evidence |
| Independent CLI version | verified |

No raw payload, live value, reset timestamp, session identifier, transcript
path, workspace path, prompt, response, task, tool data, credential, or
account identity entered Git or durable evidence.

The prior settings state was restored to file absence and `statusLine`
absence. The temporary settings file, absence marker, probe, and evidence
location were deleted. There is no permanent Claude configuration change.

Exactly one next task is:

**M5-SETUP-G1**

For this Completion Lock, `M5-SETUP-G1` is a new, separately authorized
status-line activation setup revision. The completed launcher-installation
and subscription-authentication setup remains closed and is not reopened.

## M5-SETUP-G1R final decision basis

1. The accepted predecessor is
   `802249876d79f2e9cc1396111be8ac1012ada52c`.
2. The official native 2.1.220 arm64 CLI remains the normal launcher.
3. The real user home and login shell were preserved.
4. Provider-managed `claude.ai` authentication with the first-party provider
   was visible in the normal user execution context.
5. No API-key, bearer-token, Bedrock, Vertex, Foundry, alternate-config, or
   account-web route was active.
6. No managed settings source or effective `disableAllHooks=true` policy was
   found.
7. A temporary owner-only `--settings` file activated one bounded local
   status-line command without changing persistent `statusLine` configuration.
8. A startup callback proved activation.
9. One Human-controlled response completed without DEV submitting or reading
   the prompt or reading the response.
10. A post-response callback contained both documented quota windows, both
    reset epochs, and a bounded version field.
11. Each used percentage was finite and within zero through 100.
12. Each remaining percentage was validated as `100 - used` exactly once with
    decimal-aware arithmetic; real values were not retained.
13. Temporary settings, probe, evidence, debug classification, and task-owned
    directory were removed.
14. The official first-run onboarding settings file is preserved unchanged
    with exactly one non-sensitive `theme` preference.
15. That retained file has no `statusLine`, credential, session, token,
    account identity, hook, API-key route, enterprise-cloud route, provider
    route, or UMA probe configuration.
16. No other Claude file was modified or deleted.

**ACCEPTED PROVIDER-OWNED ONBOARDING PREFERENCE — NOT A PROBE ARTIFACT**

| Capability | Admission result |
|---|---|
| Five-hour used and reset | present and valid |
| Five-hour remaining conversion | valid |
| Seven-day used and reset | present and valid |
| Seven-day remaining conversion | valid |
| Version payload field | present and bounded |
| Authentication route | provider-managed Claude.ai subscription |
| Privacy boundary | pass |
| Temporary configuration cleanup | pass |

The final classification is **GO** because both independent windows and resets
are valid. A missing or malformed window would still fail independently, and
Maximum Decrement continues to receive remaining percentages only.

No raw payload, real quota value, reset timestamp, identity, prompt, response,
session, transcript, workspace content, credential, or provider task content
entered Git.

Exactly one next task is **M5-G2**.

## M5-WEB-G1 superseding account-web decision

The account-web fallback is rejected. The provider's Google sign-in failed in
the embedded WebKit user agent, and no retry or bypass is allowed. No
authenticated Usage route or live Usage observation was obtained.

The isolated prototype used a nonpersistent store and cleared to zero retained
records, but source audit found two admission blockers: App Sandbox was absent,
and periodic `evaluateJavaScript` inspected bounded login-page DOM text before
route admission. It did not inspect credential values or persist cookies,
storage, identity, raw HTML, DOM, or screenshots. The exact prototype and its
task-owned artifacts were deleted.

`ASWebAuthenticationSession` remains only a documented Apple capability.
Without an official Claude callback and Usage authorization contract, it is
not implemented or admitted.

**NO-GO — SAFE ACCOUNT-WEB AUTHENTICATION NOT AVAILABLE**

Exactly one next task is a **Founder decision** about retaining the optional
terminal CLI integration, marking Claude Desktop usage unsupported, or closing
M5 without Claude production support.

## M5-OAUTH-G1 Founder override

The Founder has superseded the preceding product-source conclusion for the
bounded M5-OAUTH-G1 scope. Claude remains an UMA provider through one
Experimental provider-managed OAuth quota source, subject to complete offline,
live, privacy, and package acceptance.

The selectable production source is now `claude.providerManagedOAuthQuota`
with display source `Existing Claude login`. The status-line transport and
embedded account-web route remain retired. No API key, copied token, manual
quota, browser-cookie import, embedded login, provider task, or account mutation
is admitted.

Final GO, PASS WITH RISKS, or FAIL remains pending implementation and the
Founder-authorized live gate. Historical decisions above remain evidence and
are not rewritten.

## M5-BROWSER-G1 Founder replacement

The Founder permanently rejects the M5-OAUTH-G1 Keychain/broker route. Its
implementation and privacy records remain historical evidence only. No
provider credential, token-derived continuity value, bearer header, or private
quota request is admitted.

The embedded account-web NO-GO also remains in force. Browser Sync is a new
system-browser architecture: the browser controls official authentication, an
UMA Browser Companion runs only on the exact verified personal Usage route,
and UMA receives only a bounded normalized quota message.

**PASS WITH RISKS — CURRENT SAFARI BROWSER SYNC ADMITTED**

Initial admission still requires explicit Browser Sync consent, a supported
and verified companion, exact-route verification, a current valid observation,
at least one account-level window, and main/Assistant parity. Old cache alone
cannot establish admission. The current Safari live gate produced matching
five-hour and seven-day windows, honestly unavailable resets, Fresh shared
surface parity, and provider isolation without retaining exact values. The
remaining bounded risks are unverified Chromium and signed production/store
distribution; no rejected historical route is a fallback.
