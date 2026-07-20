# UMA GitHub Publication Scope Lock

Date: 2026-07-20
Task: bounded local preparation for Human-managed GitHub upload

## Authority and prohibitions

Codex may prepare repository content, sanitized demo assets, documentation,
proportional verification, one exact local publication commit, a clean export
folder, and a backup ZIP.

Codex must not push, rename or configure a remote repository, create a tag or
Release, invite a collaborator, begin the four-hour long-debug/P3, notarize, or
deploy. The Human owns all GitHub publication actions.

This steer arrived after the preceding, then-authorized publication task had
already renamed the GitHub repository, updated its About metadata, and started
a fast-forward push. Read-only reconciliation showed that the push completed
before the interruption. Those actions are historical facts, not authority for
any further remote mutation. This task performs no additional remote changes
and does not attempt an unauthorized rollback.

## Authoritative source evidence

- Isolated worktree: `$TMPDIR/CodexUsageMonitor-P2`
- Publication branch: `codex/m1a-g2-p2`
- HEAD observed at scope lock: `97703074845d159e83b2ff879ab7d7f9f3de79a6`
- Latest accepted UMA visual-correction commit:
  `817ea5df27b59745eaf090cc50325bebf09963f5`
- Latest accepted functional-repair commit:
  `c81fb74`
- Original checkout: `~/Desktop/CodexUsageMonitor`
- Original checkout HEAD: `f1da999cf518433d108867d14ea1476678911ebf`
- P3 worktree: `$TMPDIR/codexusage-m1a-g2-dbg-c-p3-worktree`
  at `3ca7bc9`; out of scope.

At observation time the isolated publication worktree had no unstaged or staged
changes. The original checkout contained extensive tracked and untracked WIP
and must remain untouched. A later local publication-preparation commit will be
the commit-exact export source.

## Top-level classification

| Entry | Classification | Publication treatment |
| --- | --- | --- |
| `.git/` | Git metadata | Exclude from clean manual-upload folder |
| `.gitignore` | Repository hygiene | Include |
| `.codex/` | Repository development environment metadata | Exclude from clean manual-upload folder |
| `.build/` | Generated Swift build output | Exclude |
| `.swiftpm/` | Local SwiftPM state, if present | Exclude |
| `Assets/` | App icon and sanitized current Demo assets | Include |
| `Package.swift` | Swift package manifest | Include |
| `README.md` | Public bilingual product documentation | Replace and include |
| `Sources/` | Application/UI/preview source and bundled font resources | Include |
| `Tests/` | Test source | Include |
| `script/` | Build, package, and review scripts | Include current generalized scripts; exclude obsolete milestone installers |
| `source/` | Historical milestone, evidence, and scope documentation | Exclude from clean manual-upload folder |
| `docs/` | Public compatibility, metadata, and collaboration docs | Include |
| `.github/` | Lightweight issue templates | Include |
| `CONTRIBUTING.md` | Public contribution workflow | Include |
| `MANUAL_GITHUB_UPLOAD.md` | Human upload guide | Include |
| `outputs/` | Obsolete/current generated previews | Remove obsolete previews; current demos belong in `Assets/Demo/` |
| `dist/` | Generated local app bundle | Exclude |
| `work/` | Local caches and build work | Exclude |

## Sensitive and generated exclusions

The export must contain no `.git`, `.build`, `.swiftpm`, `dist`, `work`, app
bundles, ZIPs, temporary packages, Finder metadata, logs, traces, profiling
files, ledgers, Codex sessions, account snapshots, raw provider responses,
credentials, cookies, authentication files, real-usage screenshots, private
identity, or absolute private paths.

The original dirty checkout is evidence-only and must not be cleaned, staged,
or otherwise modified to produce the export.

## Compatibility boundary

Public naming is `UMA`, `Usage Monitor Altoget`, and `UMA.app`. Internal Swift
names, bundle identifier, preference domain, local consent/language keys,
Application Support directory, and cost-ledger path stay unchanged unless a
separately tested migration is approved. See `docs/COMPATIBILITY.md`.

## Completion lock

After the commit-exact folder and verified backup ZIP exist, stop. Wait for the
Human to perform the manual GitHub upload and any later collaboration setup.
