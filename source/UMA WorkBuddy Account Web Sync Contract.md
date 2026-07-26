# UMA WorkBuddy Account Web Sync Contract

Version: 1.0
Date: 2026-07-25
Goal: M2WACCOUNT-G1

## WorkBuddy-only exemption

WorkBuddy may be admitted to UMA provider surfaces when all of these conditions
are true:

1. the Human has accepted the current Experimental Account Web Sync disclosure;
2. UMA owns the isolated WebKit session used for the read;
3. the session is authenticated by the Human through the official WorkBuddy
   website;
4. the exact official Plan and Usage route is current;
5. one current allowlisted Credit extraction validates successfully.

WorkBuddy.app, a local Hook, local IPC, and a local structured Credits source are
not required for this WorkBuddy-only path. Every other provider retains the
local-live admission contract.

## Source identity

- Provider: WorkBuddy
- Source class: `authenticatedAccountWeb`
- Source ID: `workbuddy.accountWebCredits`
- Credit-pool identity: `buddyAI.sharedCredits`
- Scope kind: unknown Buddy AI until the official page supplies a narrower
  Personal/Enterprise declaration
- UI provenance: `Account web sync`
- Risk label: `Experimental`
- Official origin: `https://www.workbuddy.cn`
- Exact read route: `https://www.workbuddy.cn/profile/plans-usage`

The account-web connector is not restorable. A cached or persisted provider
snapshot cannot admit WorkBuddy.

## Human-controlled session

Settings offers an explicit disclosure and two session choices:

- Keep signed in: a dedicated UMA-owned persistent WebKit data store.
- Private session: a nonpersistent WebKit data store.

Connect and Open Account Usage show the isolated WebKit window. The Human owns
all official login interaction. UMA never supplies a custom credential form.
Unexpected external HTTPS hosts require exact-host confirmation; non-HTTPS and
invalid navigation fail closed.

Switching from Keep signed in to Private session removes the dedicated
persistent store. Disconnect removes only the dedicated UMA-owned WorkBuddy
store, consent record, nonidentifying established-session marker, and current
account-web admission. Safari, Chrome, WorkBuddy.app, and the legacy manual
record are outside that operation.

## Read and extraction contract

Account-page reads are permitted only for:

- application launch when valid consent and an isolated session already exist;
- shared Manual Refresh;
- Sync Now;
- Check Again.

There is no timer, background polling, visibility-triggered read,
Desktop-Assistant-triggered read, or render-triggered read. Concurrent scans are
coalesced by the existing shared eligibility scanner.

The page extractor:

- verifies the exact HTTPS origin and Plan and Usage path;
- scopes queries to the Plan and Usage component;
- reads only the bounded Credit quota rows;
- emits only canonical Decimal strings for remaining, used, and total;
- emits no HTML, DOM tree, browser storage, identity, cookie, token, or
  credential material;
- rejects missing, malformed, duplicated, excessive, or internally
  inconsistent rows.

The connector aggregates at most eight unique base/gift rows. `CreditBalance`
remains the exact Decimal authority.

## Admission and failure

A successful current read publishes one provider-reported fresh account channel
to the main panel and Desktop Assistant. Main-panel and Regular Assistant
details use exact Credits; Minimalist may use the accepted compact Credit
formatter. Both surfaces derive from the same admitted snapshot.

Authentication expiry, navigation failure, timeout, extraction failure, or
Disconnect removes WorkBuddy from both surfaces immediately. The last valid
value is not retained. The legacy manual record is never a fallback and remains
byte- and semantically separate.
