# UMA M2WA Handoff

Date: 2026-07-24

## Accepted baseline

M2WA must begin from the commit that contains this handoff. Resolve the exact,
immutable identifiers without relying on a moving branch:

```bash
accepted_commit="$(git log -1 --format=%H -- 'source/UMA M2WA Handoff.md')"
accepted_tree="$(git rev-parse "$accepted_commit^{tree}")"
```

The final M2WDBG report records those resolved literal values, the matching
commit-exact package path, the source-archive SHA-256, and the executable
SHA-256. The package path is deterministic:

```text
/private/tmp/uma-m2wdbg-final-<first-12-of-accepted-commit>/UMA.app
```

Accepted predecessor commits:

- M2W-G1 Credit value model: `2a0d648`
- M2W-G2 manual WorkBuddy source: `42d97e6`
- M2W-G3 main-panel visibility: `81a71d6`

## Accepted contracts

- WorkBuddy identity is `workbuddy.manualAvailability`.
- The Credit value model is provider-neutral, versioned, overflow-safe, and
  fails closed on malformed or future schemas.
- Percentage is derived only from an explicit total or the same observation's
  validated remaining-plus-used values.
- Buddy AI and CodeBuddy share the stable pool identity
  `buddyAI.sharedCredits`; M2WA must not double-count the pool.
- WorkBuddy provenance remains visibly manual and unavailable for automatic
  freshness claims.
- The manual source owns one bounded primary/recovery record pair with `0600`
  files, an `0700` parent directory, and an 8 KiB limit.
- Save, Confirm unchanged, Enable/Disable, and Clear remain change-bounded.
  Clear means unconfigured; it never fabricates zero Credits.
- A value-identical Save may repair persistence copies but must not advance the
  confirmation timestamp or publish a new value.
- A stale Settings draft may not overwrite a newer confirmation without a
  deliberate second Save.
- Remaining-only, remaining-plus-used, remaining-plus-total, and explicit
  remaining-plus-used-plus-total entry modes remain distinct.
- Main-panel order is Codex then WorkBuddy.
- WorkBuddy remains excluded from Desktop Assistant until M2WA explicitly
  changes that surface contract.
- Shared Refresh refreshes Codex only and never changes the WorkBuddy manual
  record or confirmation time.

## M2WDBG acceptance

The deterministic matrix covers:

- 20 distinct Saves;
- 10 Confirm unchanged operations;
- 5 Enable/Disable cycles;
- 5 Clear/reconfigure cycles;
- 20 Shared Refresh operations;
- 10 source relaunches;
- invalid, oversized, corrupt-primary, backup-recovery, stale-draft, and
  explicit-three-value paths;
- English and Simplified Chinese copy;
- Light, Dark, warning, critical, Reduce Transparency, and Increase Contrast
  renderer states;
- Codex-only Desktop Assistant projection;
- one host process, one status item, no more than one owned Codex app-server
  child, controlled child recovery, bounded threads/descriptors/RSS, unchanged
  manual-record hashes, and no WorkBuddy network client.

## M2WA ownership boundary

M2WA may add a WorkBuddy presentation to Desktop Assistant only under its own
explicit Goal authority. It must consume the existing shared presentation and
manual-source state; it must not create another connector, store, timer,
observer, process, provider read, or network client.

M2WA must preserve:

- one manual source and one WorkBuddy connector;
- exact manual provenance and confirmation age;
- shared-pool identity and Credit semantics;
- main-panel behavior and action routing;
- Codex independence;
- no automatic WorkBuddy synchronization;
- no WorkBuddy account, application, browser, private-file, database, process,
  memory, credential, Keychain, OCR, or network access.

## Known limitations and explicit non-goals

- WorkBuddy values remain Human-entered snapshots.
- Automatic synchronization remains NO-GO.
- Confirmation time states when the Human confirmed the snapshot; it is not a
  provider freshness timestamp.
- Tier suggestions are convenience labels, not provider entitlements and not
  inferred balances.
- This handoff does not authorize M2WA implementation, another provider,
  installation, fetch, push, tag, release, notarization, deployment, or
  publication.
