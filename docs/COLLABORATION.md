# UMA collaboration workflow

## Roles and source of truth

The founder maintains the canonical repository:
`https://github.com/ShaoJHe-SilkRoad/UMA`.

The founder decides what enters `main`. A collaborator works in a feature
branch and proposes changes through a pull request. Local app bundles, backup
ZIPs, and private Codex state are not sources of truth.

## Founder workflow

1. Confirm the canonical repository and current `main`.
2. Review each pull request for scope, behavior, privacy, and compatibility.
3. Require relevant test/build evidence.
4. Request focused corrections when needed.
5. Merge only reviewed work; do not accept unrelated generated artifacts.

## Collaborator workflow

```bash
git clone https://github.com/ShaoJHe-SilkRoad/UMA.git
cd UMA
git switch main
git pull --ff-only origin main
git switch -c feature/short-description
```

Make focused changes and commits, then:

```bash
git push -u origin feature/short-description
```

Open a pull request to `main`, describe the change and validation, and respond
to review. Do not push directly to `main`.

## Syncing with latest main

Before opening or updating a pull request:

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git switch feature/short-description
git merge main
```

Resolve conflicts in the feature branch. Inspect every conflict marker, rerun
tests, and commit the resolution. Ask the founder before discarding either
side's work. Never use a force-push to `main`.

## Review expectations

A pull request should have one clear purpose, list changed behavior, identify
compatibility or privacy effects, and provide relevant test/build results.
Visual changes should include only current sanitized previews. Connector
changes should preserve read-only account access and the one-owned-child
boundary.

## Reporting bugs

Use the Bug report template. Provide macOS version, UMA revision, expected and
actual behavior, and reproducible steps. Redact usernames, account identifiers,
usage totals, task names, home-directory paths, tokens, and provider payloads.

## Protecting local Codex data

Do not add or attach `~/.codex`, Codex sessions, raw provider responses,
credentials, cookies, account snapshots, the UMA Application Support
directory, the token-cost ledger, logs, caches, traces, or screenshots of real
usage. Use the deterministic PreviewRenderer data for visual examples.
