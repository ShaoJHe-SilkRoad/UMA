# M1A-G2 Evidence Ledger

| Check | Result | Evidence |
| --- | --- | --- |
| G1 dual-source regression | Pass | full bounded SwiftPM run, 2026-07-17 |
| Connector registry and persistence | Pass | `M1AG2ConnectorCoreTests`: 8 tests, including stream delivery/stop, corruption backup, stale restore, and lazy v0 migration |
| Full suite/build/package | Pass, candidate only | bounded SwiftPM run: 82 tests; a fresh ad-hoc-signed recovery candidate based on `9a7bd9692560` passed `plutil` and strict `codesign` verification |
| Privacy and fixture scan | Pass | registry/store contain no provider transport; persisted schema omits identity, raw payload, task timestamps, per-task tokens, paths, content, and credentials |
| Bounded Gate B | Pass, candidate only | native Connect/Allow; one 7-Day row; authoritative 5-Hour infinity state; two Refresh actions; then termination of the sole owned child and one in-process Refresh recovery to exactly one replacement child. Sanitized panel evidence only. |

## Evidence rules

Only sanitized aggregate values and deterministic pass/fail observations may be recorded. No account identifier, raw RPC response, cookie, credential, local path, task name, or source content is admissible.

The final candidate check retained no account identity, raw RPC response, cookie, credential, local path, task name, or source content. The second normal Refresh had correlated valid post-refresh panel, status-item, and child-process evidence even though its text classifier did not independently converge. The post-termination recovery was confirmed by a fresh sanitized quota summary and exactly one replacement direct child.
