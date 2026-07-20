# Contributing to UMA

Thank you for helping improve UMA (Usage Monitor Altoget). The current
repository is a development preview, so changes should be small, reviewable,
and safe for local data.

## Workflow

1. Clone the canonical repository:
   `https://github.com/ShaoJHe-SilkRoad/UMA`.
2. Sync `main` before starting.
3. Create a focused branch. Recommended prefixes are `feature/`, `fix/`,
   `docs/`, and `test/`, for example `fix/panel-refresh`.
4. Make focused commits with clear imperative messages.
5. Run the relevant tests and builds.
6. Push the feature branch and open a pull request to `main`.
7. Address review comments with additional focused commits.

Do not force-push directly to `main`. Do not mix unrelated changes in one pull
request.

## Verification before a pull request

Run at least:

```bash
swift test
swift build -c release
swift build --product PreviewRendererTool
git diff --check
```

When changing packaging, privacy boundaries, connector behavior, or UI
appearance, also run the focused package, privacy, and visual checks relevant
to that change. Explain any skipped check in the pull request.

## Privacy and repository hygiene

Never commit:

- credentials, cookies, authentication files, Keychain exports, or API keys;
- account identity, provider responses, Codex session files, or conversation
  content;
- local token-cost ledgers or Application Support state;
- `.build`, `.swiftpm`, `dist`, `work`, caches, logs, traces, app bundles, or
  temporary packages;
- screenshots with real identity, account usage, task names, or unrelated
  desktop content.

Only sanitized deterministic preview data belongs in repository screenshots.
Keep bundled third-party licenses and provenance intact.

## Compatibility

The public product name is UMA, but legacy internal identifiers are
intentionally retained. Read [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)
before changing package/target names, the bundle identifier, preference keys,
Application Support paths, or the cost ledger path. Do not perform a blind
internal rename.

## Bug reports and feature requests

Use the issue templates. Include reproducible steps and sanitized diagnostic
information, but never attach private local Codex data. Security-sensitive
reports should not disclose secrets in a public issue.
