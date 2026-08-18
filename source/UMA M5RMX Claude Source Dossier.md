# UMA M5RMX Claude Source Dossier

**Version:** 1.0

**Date:** 2026-08-17

**Goal:** M5RMX-G1

**Status:** Browser Sync retained; no superior official replacement admitted

## 1. Current source owner

Claude account-capacity truth currently comes from:

```text
Safari owns Claude authentication and session state
→ exact https://claude.ai/new#settings/usage route
→ bounded semantic extraction in the Safari Browser Companion
→ versioned sanitized browser/native packet
→ owner-only local handoff and cache
→ ClaudeCodeUsageConnector
→ shared Main Panel and Desktop Assistant presentation
```

The accepted source is `claude.browserSync`. The retired status-line route is
historical evidence only and is not an automatic fallback.

## 2. Current source-candidate matrix

The candidates were evaluated in the required preference order. A higher rank
does not create authority; every replacement gate must pass.

| Rank | Candidate | Account-capacity truth | Automatic no-work refresh | Credential opacity | Current decision |
|---|---|---|---|---|---|
| 1 | Official Claude local service or IPC | No current official, documented, bounded account-quota contract is proven | Not proven | Local trust is unadmitted: current strict verification of Claude.app fails | `NOT ADMITTED` |
| 2 | Official hook, event, or status interface | Official status-line input documents five-hour and seven-day used percentages and matching reset fields | No; quota appears only after the first API response, and a timer rerun is not proven to obtain fresh provider truth | Raw status-line stdin carries broader sensitive context and would require sanitization before UMA | `HISTORICAL / RETIRED` |
| 3 | Official read-only CLI or provider-owned local metadata | No current documented read-only quota command with stable account-window schema is proven | Not proven | Current strict verification of the installed 2.1.220 CLI fails | `NOT ADMITTED` |
| 4 | Safari Browser Sync | Current provider-rendered five-hour and weekly account windows are accepted | Yes; one completion-relative five-minute cycle with one in-flight read | Yes; Safari owns authentication and only a closed packet crosses | `ACCEPTED CURRENT` |

No candidate replaces Browser Sync. A future candidate must prove all of:

- official and documented authority;
- current account-capacity truth rather than this-Mac activity;
- explicit used-versus-remaining semantics;
- stable window identities and matching reset scopes;
- provider-owned authentication;
- zero Claude prompt/task generation and zero intentional spend;
- automatic refresh without requiring provider work;
- credential opacity and a bounded sanitized output;
- live parity with the official Usage surface;
- safe rollback to Browser Sync.

## 3. Official status-line delta and coverage

The current official status-line input contract includes:

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
```

These fields do not promote the retired product route. They are supplied only
after the first API response in a running Claude Code session. Re-running a
status-line command on a timer is not proven to fetch a fresh provider value.
The raw status-line stdin also carries broader sensitive session and workspace
context, so any use would require a sanitizer before UMA rather than sending
the raw callback across a process boundary.

Documented quota-field coverage is Claude.ai Pro and Max. Team, Enterprise, and
unknown account modes are not qualified and must not be inferred from Pro/Max
schema evidence. Browser Sync remains current because its accepted provider-
rendered Usage-page contract does not depend on reviving this event source.

## 4. Current local trust result

Read-only strict verification on 2026-08-17 returned:

```text
$HOME/.local/bin/claude: invalid signature (code or signature have been modified)
In architecture: arm64

/Applications/Claude.app: invalid signature (code or signature have been modified)
In architecture: arm64
```

The launcher resolves to `$HOME/.local/share/claude/versions/2.1.220`. These failures
make the current local CLI/application trust boundary unadmitted for a promoted
quota source. They do not weaken Safari Browser Sync: Safari remains the
provider-controlled authentication owner and the current source does not rely
on either local executable as its credential or quota authority.

## 5. Admitted account semantics

The current normalized account channel admits:

- five-hour used percentage and optional matching reset;
- weekly/all-model used percentage and optional matching reset;
- at most one explicitly scoped model-family weekly window when separately
  provider-rendered and unambiguous;
- observation time, source/browser classification, schema versions, exact-route
  verification state, and freshness.

Each percentage must be finite and within `0...100`. Browser Sync transports
provider-rendered **used** percentage. Shared production logic performs exactly
one conversion:

```text
remainingPercent = 100 - usedPercent
```

Missing, malformed, duplicate, or ambiguous windows are unavailable, never
zero. A missing reset stays unavailable. Five-hour and weekly windows remain
independent.

## 6. Continuation and usage-credit decision

No continuation, overage, extra-usage, usage-credit, billing-balance, purchase,
or payment field is currently admitted. The exact Usage extractor deliberately
excludes spending and billing sections. UMA must not infer continuation from a
quota percentage, local activity, plan label, model availability, or the
presence of an authenticated session.

Official usage-credit continuation means that `0%` included-plan remaining does
not prove Claude work must stop. UMA therefore presents that account window as
exhausted without claiming overall provider unavailability. Whether work can
continue through usage credits remains `UNAVAILABLE / UNKNOWN` until an
explicitly scoped provider-rendered continuation field is separately admitted.

If Claude later renders an explicit continuation state, it requires a separate
source-admission decision proving its label, scope, native unit, reset or cycle,
and privacy-safe extraction. Until then it is `UNAVAILABLE / NOT ADMITTED`.

## 7. Browser and native boundary

The current contract identifiers are:

```text
source ID: claude-browser-usage
message kind: claudeUsageObservation
bridge schema: 1
extractor schema: 1
maximum message: 4096 bytes
Safari extension: com.silkrd.uma.ClaudeBrowserCompanion
native message identity: com.silkrd.uma.claude_browser
exact Usage route: https://claude.ai/new#settings/usage
```

The current Safari manifest requests exactly `nativeMessaging`, `storage`, and
`https://claude.ai/new*`, with a persistent background script. This supersedes
historical activeTab/toolbar-only records; those describe an earlier product
stage, not the current runtime. The fragment cannot be represented in a host
permission, so the extension revalidates protocol, host, path, empty query, and
`#settings/usage` before any DOM query and again before returning a result.
There are no static content scripts or broader host permissions.

On the exact route, the extractor tries explicit provider-owned Usage-card
selectors first. If they are absent, it performs bounded in-browser matching of
exact allowlisted leaf-text landmarks across at most 4096 candidate elements.
That fallback may inspect unrelated leaf text transiently inside the browser as
it rejects nonmatches. It does not serialize, retain, or forward those strings;
only the normalized allowlisted observation may cross the native boundary.

The closed observation packet contains only fixed identifiers, browser family,
route state, observation time, extractor version, allowlisted quota windows,
optional matching resets, and an optional bounded model-family enum. The native
decoder rejects unknown keys, invalid schemas, oversized messages, invalid
timestamps, out-of-range percentages, and observations without an account
window.

## 8. Lifecycle and fallback

- one connector owns one completion-relative five-minute scheduler;
- at most one read is in flight;
- at most one extension-owned inactive Usage tab exists;
- ownership uncertainty suspends automation and never adopts a user-owned tab;
- authentication, permission, route, or layout uncertainty fails closed;
- a validated last-known snapshot may be Cached or Stale but never becomes
  Fresh merely because it was restored;
- Disconnect cancels scheduling, closes only a proven extension-owned tab, and
  clears UMA-owned Claude state without changing Safari login data;
- local Claude activity and API-equivalent cost remain a separate this-Mac
  estimate channel and never substitute for account quota.

If Browser Sync is temporarily unavailable, UMA may retain only the accepted
bounded Cached/Stale behavior. It must not fall back to status-line, manual
quota, API-key, Keychain, cookie, token, private-endpoint, or inferred data.

## 9. G1 decision

```text
BROWSER SYNC: ACCEPTED CURRENT
SUPERIOR OFFICIAL REPLACEMENT: NOT PROVEN
FIVE-HOUR WINDOW: ADMITTED
WEEKLY / SEVEN-DAY WINDOW: ADMITTED
MODEL-SPECIFIC WEEKLY WINDOW: OPTIONAL, EXPLICIT-SCOPE ONLY
CONTINUATION / USAGE-CREDIT STATE: NOT ADMITTED
OVERALL WORK AVAILABILITY AT 0% INCLUDED REMAINING: UNKNOWN
STATUS-LINE ROUTE: HISTORICAL / RETIRED
STATUS-LINE ACCOUNT COVERAGE: PRO/MAX DOCUMENTED; TEAM/ENTERPRISE/UNKNOWN UNQUALIFIED
LOCAL CLI / CLAUDE.APP TRUST: UNADMITTED
```

M5RMX-G1 changes source/privacy contracts and deterministic tests only. It does
not change production extension/runtime behavior.
