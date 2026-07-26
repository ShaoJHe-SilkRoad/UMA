# UMA WorkBuddy Account Web Sync Privacy Disclosure

Version: 1.0
Date: 2026-07-25
Goal: M2WACCOUNT-G1

## Experimental feature

When the Human explicitly enables Experimental Account Web Sync, UMA opens the
official WorkBuddy site in a WorkBuddy-only isolated WebKit session. The Human
completes the official login. UMA reads only the Credit balance fields on the
official Plan and Usage page.

## Data UMA may process

- exact canonical remaining Credits;
- exact canonical used Credits when the page supplies them;
- exact canonical total Credits when the page supplies them;
- extractor version;
- observation time;
- nonidentifying connection/failure state.

The validated Credit values are held in the in-memory provider snapshot used by
the main panel and Desktop Assistant. The account-web connector does not restore
a saved provider snapshot on a later launch.

## Data UMA does not extract or report

- password, QR code, cookie, token, or credential;
- email, phone number, account name, or organization identity;
- full HTML, serialized DOM, page text, screenshots, or browser history;
- `localStorage`, `sessionStorage`, Cache Storage, IndexedDB, or auth databases;
- billing, order, conversation, task, or prompt content;
- Safari, Chrome, or WorkBuddy.app session data.

UMA does not use a cookie API, browser-storage API, Keychain API, private
WorkBuddy API, OCR, broad page capture, or network client outside the visible
isolated WebKit session.

## Session storage

Keep signed in uses a dedicated UMA-owned persistent WebKit data-store
identifier. Private session uses WebKit's nonpersistent store. UMA preferences
persist only the current disclosure version, acceptance time, and selected
session mode, plus one nonidentifying boolean recording that a successful
persistent isolated session was previously established. They contain no account
identity or authentication material.

Disconnect WorkBuddy Account releases the isolated browser, removes the
dedicated persistent WorkBuddy website store, clears the disclosure preference,
and withdraws the account-web provider snapshot. Switching from Keep signed in
to Private session also removes the dedicated persistent store. The legacy
manual WorkBuddy record is not read, changed, or deleted by either operation.

## Read cadence

Reads occur only on application launch with prior consent/session, shared
Manual Refresh, Sync Now, or Check Again. There is no background polling.
