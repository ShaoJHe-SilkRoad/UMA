# UMA WorkBuddy Account Web Sync Contract

Version: 1.1
Date: 2026-07-26
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
- requires the subscription, add-on, and benefit/gift resource sections;
- performs bounded section scrolling and section-local `查看全部` expansion;
- waits for bounded row-count stability before one atomic extraction;
- emits only normalized pool kind, bounded stable identity, exact used/total,
  optional displayed remaining, normalized effective/expiry time, and safe
  status;
- emits no HTML, DOM tree, browser storage, identity, cookie, token, or
  credential material;
- rejects missing sections, malformed or ambiguous pools, conflicting
  duplicates, excessive precision, invalid dates/status, and internally
  inconsistent rows.

Every pool computes `remaining = total - used` with exact Decimal arithmetic.
Every duplicate identity fails closed, including exact duplicate markup and
identity collisions with different values. Expired, future, historical, and
unavailable pools are excluded.
Subscription, add-on, and benefit/gift subtotals are calculated independently,
then summed into one account balance. The subscription subtotal is never treated
as the account total.

When exactly one dedicated page-level account balance exists, it must reconcile
with the pool sum within `0.01` Credits. Multiple candidates or a larger
difference reject the observation. Without a page-level balance, the all-pool
sum may be admitted but requires a same-time Human comparison before program
closeout.

Account-web values use canonical Decimal strings, at most two fractional
digits, and a maximum of `999,999,999,999.99`. The account grand total is
absolute-only: no subscription-derived denominator, percent, proportional fill,
or universal absolute severity threshold is inferred.

## Admission and failure

A successful current read publishes one provider-reported fresh account channel
to the main panel and Desktop Assistant. Main panel, Regular Assistant,
Tooltip, VoiceOver, and expanded details use thousands separators and exactly
two decimal places. Minimalist uses exact-magnitude k/M/B selection with
truncation, never rounding or unit prepromotion; positive values below one use
`<1`. Both surfaces derive from the same admitted snapshot.

Authentication expiry, navigation failure, timeout, extraction failure, or
Disconnect removes WorkBuddy from both surfaces immediately. The last valid
value is not retained. The legacy manual record is never a fallback and remains
byte- and semantically separate.
