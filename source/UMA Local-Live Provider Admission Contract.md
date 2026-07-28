# UMA Local-Live Provider Admission Contract

Version: 1.0
Date: 2026-07-25
Authority: UMA Logic 1.3 and Founder M2WADBG-R3 override

## Production rule

A registered provider is visible only when one current eligibility scan proves
all of the following:

1. its declared official application, CLI, or local service is active;
2. an existing authenticated provider session is usable;
3. its descriptor names an admitted, structured, local, read-only source;
4. one current local usage read succeeds;
5. the returned scope, provenance, freshness, and values validate.

Every other result is hidden. This includes inactive, logged-out, manual-only,
unsupported, malformed, failed, and stale-only providers. A last-valid value
may remain internal but cannot keep a provider visible.

## One admission owner

```text
registered descriptors
→ LocalProviderEligibilityScanner
→ ProviderSurfaceAdmissionSet
→ AgentConnectorRegistry
→ UsageStore
→ SharedUsagePresentationPolicy
├── main panel
└── Desktop Assistant
```

Views never inspect processes, authentication, schemas, or login state. The
main panel and Assistant consume the same admitted IDs in the same stable
priority. The Assistant remains presentation-only and owns no scanner,
connector, timer, store, or provider child.

## Scan triggers

One coalesced scan is allowed on application launch, explicit Manual Refresh,
or explicit Check Again. Check Again is one Manual Refresh. Panel visibility,
Assistant visibility, rendering, countdowns, expansion, Settings navigation,
language, appearance, density, app activation, wake, periodic timers, and
background polling never discover providers.

After admission, a connector-owned official local event stream may publish
updates. A transient in-flight read does not start a new discovery scan.
Explicit logout, runtime termination, source loss, unsupported schema, stale
completion, or failed completion removes the provider from both surfaces.

## Registered descriptor contract

Each candidate declares a stable ID and priority, runtime requirement, source
class, authentication method, usage-read contract, and login-assistance
capability. Unknown applications are ignored. Source contracts are versioned,
validate required fields, tolerate only documented optional fields, and fail
closed after incompatible change.

The stable priority is:

```text
Codex
Claude Code
WorkBuddy
Manus
Cursor
Kimi+
Doubao / later approved providers
```

Filtering creates no placeholder, gap, or reordering.

## Source and privacy boundary

Surface-eligible sources are official or explicitly admitted, structured,
local on the UMA side, read-only, current, scope-correct, credential-safe,
privacy-safe, and package-feasible. Manual entry, screenshots, OCR,
Accessibility text extraction, browser UI, websites, cookies, private tokens,
Keychain, auth databases, private caches/databases, memory, network
interception, inferred quota, stale cache, and fixtures are not eligible.

Visibility state does not persist. UMA does not persist login state, account
identity, process IDs, raw probe payloads, credentials, unsupported-provider
inventory, or browser state.

## Current decisions

- Codex is visible only when its accepted local runtime, existing session, and
  app-server usage read are currently valid.
- WorkBuddy manual Credit infrastructure and records remain intact for
  compatibility, migration, Settings, and tests, but `manualOnly` can never
  surface-admit it.
- WorkBuddy 5.3.5 has no admitted official local real-time Credits source.
  WorkBuddy is hidden from the main panel, status summary, and Assistant and
  exposes no login action.
- M2W-LIVE-G1 remains dormant.

## Empty state

With no admitted provider, the main panel says:

```text
No locally accessible signed-in Agents detected.
Open a supported Agent, ensure it is signed in,
then choose Refresh.
```

The status item uses a neutral summary with no fabricated percentage. The
Assistant has no rows and no floating shell while preserving its enabled
preference.
