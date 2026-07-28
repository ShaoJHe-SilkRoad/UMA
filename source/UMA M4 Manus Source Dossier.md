# UMA M4 Manus Source Dossier

Status: M4 CLI-only source recheck — current authority
Date: 2026-07-28
Baseline commit: `55104d1009f19a78b4b6f1b857afb1487068e413`
Baseline tree: `9bf0c711a0cc60c8a056f4e1618e9c2ea4f27f2b`

## Founder CLI-only override

The current product source policy is:

```text
Official Manus CLI
  → documented read-only status/usage/Credits command
  → documented structured machine-readable output
  → current total available Credits
  → UMA connector
```

No API key, OAuth, embedded login, browser/account-web source, private local
state, manual entry, estimation, or task-generating probe is admissible.

### Installed application inventory

Read-only inspection found:

| Property | Observation |
|---|---|
| Bundle | `/Applications/Manus.app` |
| Bundle identifier | `im.manus.desktop` |
| Version / build | `1.6.8` / `1.6.8` |
| Main executable | `Contents/MacOS/Manus` |
| Architecture | arm64 |
| Team ID | `5V8XDGQQB6` |
| Strict deep signature | FAIL — bundle reports a modified/invalid signature |
| Gatekeeper | FAIL — Code Signing subsystem internal error |
| PATH command | No `manus`, `manus-cli`, or `Manus` command found |
| Additional executable | `Contents/Resources/bin/sidecar` |
| Sidecar identity | arm64, identifier `sidecar`, Team ID `5V8XDGQQB6` |
| Sidecar signature | FAIL — modified/invalid signature |

The bundle's `sidecar` is not documented by Manus as a public CLI. It was not
executed, queried for private help, or treated as a product contract.

### Official documentation recheck

Current official sources inspected:

- documentation index: <https://manus.im/docs/llms.txt>;
- Desktop documentation: <https://manus.im/docs/features/desktop>;
- Desktop Credit behavior:
  <https://help.manus.im/en/articles/14134826-understanding-credit-consumption-in-the-manus-desktop-app>;
- Credits and Usage collection:
  <https://help.manus.im/en/collections/15919440-credits-usage>.

The complete official documentation index exposes Desktop, API, integrations,
and product features, but no installable Manus CLI or CLI command reference.
The Desktop documentation uses “CLI” to describe third-party command-line
tools that the Manus agent can execute. It does not document Manus itself as a
CLI and contains no status, usage, Credits, JSON, schema, authentication-reuse,
or local-freshness command contract.

No documented read-only CLI command was therefore run. No structured field was
returned. No authentication material, private application state, account
identity, task, project, file, browser, network request, or Credit-consuming
operation was accessed.

### Current CLI source conclusion

**NO-GO — NO OFFICIAL LOCAL MANUS CLI CREDIT CONTRACT EXISTS.**

The installed bundle provides no admitted CLI, and current official
documentation provides no stable structured command or schema for current
total available Credits. The undocumented `sidecar` cannot be used as a
source, and the invalid installed-bundle signature independently prevents
trusting it.

Manus remains unsupported and hidden. M4-N removes the M4-G2 API-key path from
the product and final package while preserving the original commit as
historical, unreleased Git evidence.

## Superseded M4-G1 API-key finding

The remainder of this document records the former M4-G1 API-key research for
historical traceability. It is superseded by the Founder CLI-only override
above and is not an admissible production direction.

## Executive finding

The current official Manus API v2 documents one narrow, read-only balance
source that fits UMA's provider contract:

```text
Keychain
  → narrow URLSession client
  → GET https://api.manus.ai/v2/usage.availableCredits
  → strict AvailableCredits decoder
  → data.total_credits only as the primary balance
  → provider-neutral Credit snapshot
```

The source is admitted conditionally. Documentation and local architecture
prove that a secure implementation is feasible, but no real API key, Keychain
item, authenticated request, or Human balance comparison was used in M4-G1.
That live evidence remains a later Human-controlled gate.

## Official-source inventory

Current official sources inspected on 2026-07-28:

- API v2 introduction: <https://open.manus.ai/docs/v2/introduction>
- Authentication: <https://open.manus.ai/docs/v2/authentication>
- Open App and OAuth scope: <https://open.manus.ai/docs/v2/open-app>
- Rate limits: <https://open.manus.ai/docs/v2/rate-limits>
- Available Credits endpoint:
  <https://open.manus.ai/docs/v2/usage.availableCredits>
- OpenAPI v2 schema:
  <https://open.manus.ai/docs/v2/openapi_v2.json>
- Official documentation inventory: <https://open.manus.ai/docs/llms.txt>
- Apple Keychain guidance:
  <https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets>
- Apple device-bound accessibility class:
  <https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly>

The local M4 plan contains an older `open.manus.im/docs` documentation-host
reference. Current public documentation is served from `open.manus.ai`.
This is documentation-host drift, not an API-host conflict. The official API
host remains `api.manus.ai`.

## Protocol contract

| Property | Admitted contract |
|---|---|
| Current API version | v2; v1 is deprecated |
| Scheme and host | `https://api.manus.ai` |
| Method | `GET` |
| Exact path | `/v2/usage.availableCredits` |
| Query | none |
| Request body | none |
| Authentication | `x-manus-api-key` header |
| OAuth | not supported for this `usage.*` endpoint |
| Success envelope | `ok`, `request_id`, `data` |
| Error envelope | `ok`, `request_id`, `error.code`, `error.message` |
| Primary value | `data.total_credits` |
| Numeric type | documented 32-bit integer Credit points |
| Personal scope | the key owner's personal balance |
| Team scope | the team shared pool for a team sub-account key |

The former API-key route was rejected before live use. No key was created,
received, stored, or used by UMA, and no authenticated Credit read occurred.

This balance endpoint creates no task and consumes no Credits. M4-G1 did not
perform an authenticated read.

## AvailableCredits field admission

The OpenAPI schema does not declare a JSON Schema `required` list. UMA must
therefore require the prose-authoritative envelope and `total_credits` itself
while treating documented detail fields as optional. A missing
`total_credits`, wrong numeric type, negative value, or 32-bit overflow fails
closed.

| Current documented field | Classification | UMA use |
|---|---|---|
| `total_credits` | accepted primary | Sole authoritative spendable balance |
| `free_credits` | accepted optional detail | Labeled component only |
| `periodic_credits` | accepted optional detail | Labeled current-cycle component only |
| `addon_credits` | accepted optional detail | Labeled purchased component only |
| `pro_monthly_credits` | quota only—never current balance | Optional plan/quota detail; never a denominator |
| `event_credits` | accepted optional detail | Labeled event component only |
| `refresh_credits` | accepted optional detail | Labeled current refresh component only |
| `max_refresh_credits` | accepted reset detail | Optional per-refresh amount; never current balance |
| `next_refresh_time` | accepted reset detail | Optional Unix-seconds reset metadata; `0` means no scheduled refresh |
| `refresh_interval` | accepted reset detail | Optional `daily`, `weekly`, or empty schedule |
| Any undocumented field | unknown/reject | Ignored at decode boundary; never persisted or presented |
| Identity, tasks, history, prompts, responses | private/reject | Not requested, decoded, logged, or stored |

`total_credits` is authoritative even when the optional components do not add
up to it. The official prose explicitly accounts for membership and team
overflow behavior that cannot always be reconstructed from component fields.
UMA must never derive the wallet balance by summing components.

## Transport and cadence boundary

The official docs do not publish timeout, redirect, response-size, or an
endpoint-specific rate limit for `usage.availableCredits`. The rate-limit page
lists other `usage.*` methods but omits this one. UMA therefore adopts a
conservative local safety policy instead of inventing a provider limit:

- ephemeral `URLSessionConfiguration`;
- exact HTTPS host and path allowlist;
- cookies, credential storage, and URL cache disabled;
- request timeout 15 seconds and resource timeout 20 seconds;
- reject every redirect rather than forwarding the API key;
- accept HTTP 200 only;
- require JSON-compatible content when a content type is supplied;
- cap the decompressed response at 16 KiB;
- accept `next_refresh_time` only as documented zero or plausible Unix
  seconds, never milliseconds;
- allow one read in flight;
- coalesce overlapping manual/automatic triggers;
- schedule no faster than 60 seconds after the prior read completes;
- do not immediately retry `429`, authorization, schema, or transport failure.

Documented error codes include `invalid_argument`, `not_found`,
`permission_denied`, and `rate_limited`. Diagnostics may retain only a bounded
category and HTTP status. They must never include the provider message,
request body, response body, key, header dictionary, account identity, or raw
payload.

## Secret boundary and lifecycle

The production design uses one macOS Keychain generic-password item:

| Attribute | Required value |
|---|---|
| Class | `kSecClassGenericPassword` |
| Service | `com.kevinchen.CodexUsageMonitor.manus-api-v2` |
| Account | `primary` |
| Data-protection keychain | `kSecUseDataProtectionKeychain = true` |
| Accessibility | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| Synchronizable | false |
| Access group | absent |

Only `SecItemAdd`, `SecItemUpdate`, `SecItemCopyMatching`, and
`SecItemDelete` are admitted. Keychain operations must run off the main actor.
No API key, header, response, or decoded snapshot may enter `UserDefaults`,
the package, fixtures, logs, screenshots, crash diagnostics, or Git. A safe
configured/not-configured boolean may be persisted.

The Settings `SecureField` may hold the draft only until Save and Verify is
submitted. It then clears immediately. Swift does not offer a defensible
guarantee of zeroizing every managed string copy, so the enforceable contract
is minimum lifetime, no secondary cache, no logging, and no persistence.

Disconnect must:

1. cancel cadence and any task-owned read;
2. delete the one exact Keychain item;
3. clear the in-memory Manus snapshot and safe configuration flag;
4. withdraw Manus from the main panel and Desktop Assistant;
5. leave all other providers and Keychain items untouched.

Locked-screen `errSecInteractionNotAllowed` is transient unavailable, not an
invalid-key verdict. UMA does not weaken the accessibility class unless a
future separately approved requirement proves locked-screen reads necessary.

## Local architecture fit

The provider-neutral `CreditBalance` model already stores exact Decimal Credit
values and does not require an invented percentage. Manus integer Credit
points fit without a new persisted numeric type.

M4-G2 will need one explicit remote-source seam rather than pretending this is
a local service or authenticated web scrape:

- `ProviderLocalSourceClass.officialRemoteUsageAPI`;
- `ProviderUsageReadContract.currentOfficialRemoteRead`;
- a provider-neutral Credit detail snapshot replacing the current
  WorkBuddy-specific runtime detail field;
- a narrow `ManusAPIKeyStore`, client, and connector;
- source provenance shown as **Official API**;
- `supportsRestore = false`, so no stale wallet snapshot is restored.

The connector must publish only after a current valid read. Any authorization,
transport, schema, or Keychain-access failure withdraws admission immediately.
Assistant visibility and panel open/close events do not trigger reads.

## No-task and privacy proof

The admitted route is only `/v2/usage.availableCredits`. The allowlist excludes
task creation, task listing, task detail, task history, conversations,
attachments, prompts, responses, files, identity, email, organization data,
and every other Manus endpoint.

The package-feasibility harness:

- builds with Apple's Security framework available;
- constructs only the exact GET request with an in-memory placeholder;
- produces a redacted diagnostic that records only credential presence;
- decodes only the admitted fields;
- proves missing, malformed, negative, and overflowing values fail closed;
- proves optional components do not override `total_credits`;
- performs no Keychain read and no network request.

Observed offline verification completed with the installed macOS 26.5 SDK in
task-owned `/private/tmp` caches: the 10-test feasibility suite, 25 affected
Credit/Assistant regression tests, the full 318-test suite, and the arm64
Release product build all passed. No package manifest or toolchain was
modified.

## Dossier conclusion

The API-key prototype was not admitted. The CLI-only investigation returned
NO-GO, M4 is closed, and Manus remains unsupported. Reconsideration requires a
new Founder instruction after publication of an official documented local CLI
or public local IPC Credit contract.
