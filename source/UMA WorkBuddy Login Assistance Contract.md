# UMA WorkBuddy Login Assistance Contract

Version: 1.0
Goal: M2WLOGIN-G1
Accepted predecessor: `36fed660291ce34be857293457a516ee7c346dc5`
Runtime implementation: `6db1abed7baded7beae9be89507eb8bf6259fb29`

## Purpose

UMA may help a person reach WorkBuddy's official, provider-owned login flow.
This is an opener and guidance feature, not an authentication client and not a
WorkBuddy Credits connector.

The supported path is:

1. Settings → WorkBuddy → Login for Data Sync.
2. Validate an installed app with bundle identifier
   `com.workbuddy.workbuddy`; prefer Launch Services discovery and fall back to
   `/Applications/WorkBuddy.app`.
3. Show a privacy confirmation before opening the app.
4. Require an additional official-vendor-install confirmation when macOS code
   signing cannot be verified against Team ID `FN2V63AD2J`.
   That confirmation is bound to an opaque identity of the exact reviewed
   installation and is cleared if the installation changes.
5. Open or activate only that exact reviewed WorkBuddy bundle with public
   `NSWorkspace` APIs. A different running copy with the same bundle
   identifier fails closed.
6. Give Personal or Enterprise instructions. This selection changes
   instructions only.
7. The person completes any browser or WeChat flow entirely in
   provider-owned UI.
8. Check Again performs exactly one coalesced WorkBuddy eligibility check.
9. Report honestly that the flow completed but UMA cannot safely verify
   authentication or sync Credits because there is no supported local
   WorkBuddy Credits source.

## State distinctions

- Flow launched: UMA successfully opened or activated the official app.
- User-confirmed completed: the person returned and selected Check Again.
- Machine-verified authentication: always false in this goal.

The third state must never be inferred from app launch, app lifecycle
notifications, user confirmation, a saved manual Credit value, or a successful
browser/WeChat interaction that UMA cannot observe.

## Safe persistence

The bounded, versioned record may contain only:

- schema version;
- Personal or Enterprise instruction mode;
- consent time;
- official-install warning confirmation;
- an opaque current-installation binding for that confirmation;
- flow start and user-completion times;
- safe result;
- coarse installation state;
- warning dismissal.

It must not contain an account identity, credentials, cookies, tokens, QR
codes, browser state, authentication state, WorkBuddy private paths, raw logs,
or Credit values. Unknown schemas and oversized records fail closed.
The opaque binding is derived from public bundle and file metadata and never
persists the raw bundle path.

## Product boundaries

- Manual WorkBuddy Credits remain the only WorkBuddy value source.
- The manual source remains `.manualOnly`, hidden from the main panel, Desktop
  Assistant, and status summary.
- Login success does not admit WorkBuddy to any provider surface.
- Check Again does not read Credits and does not change a manual Credit value
  or its confirmation time.
- No browser automation, OCR, accessibility scraping, private-file access,
  database access, process-memory access, Keychain access, network request, or
  automatic provider synchronization is part of this contract.

## Lifecycle and failure behavior

Concurrent Open and Check Again actions are coalesced. The flow supports
cancel, bounded timeout, launch denial/failure, missing app, wrong bundle
identity, and public WorkBuddy-launch notification refresh. Observer tokens and
tasks are removed on shutdown.

## Verification baseline

- Focused login-assistance suite: 12 tests passed.
- Full suite: 193 tests across 28 suites passed.
- Debug, Release, and strict-concurrency Release with warnings as errors:
  passed.
- Independent staged-index review: passed after exact-install binding and
  exact-path activation were verified.
