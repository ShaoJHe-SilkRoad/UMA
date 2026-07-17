# M1A-G2 Evidence Ledger

| Check | Result | Evidence |
| --- | --- | --- |
| G1 dual-source regression | Pending final commit-exact run | `M1AG1DualSourceConnectorTests` |
| Connector registry and persistence | Pending final commit-exact run | `M1AG2ConnectorCoreTests` |
| Full suite/build/package | Pending final commit-exact run | bounded `.build/m1a-g2-*` paths |
| Privacy and fixture scan | Pending final audit | no raw account payload or runtime task arrays persisted |
| Bounded Gate B | Pending final commit-exact package | Connect/Allow, refresh, recovery evidence |

## Evidence rules

Only sanitized aggregate values and deterministic pass/fail observations may be recorded. No account identifier, raw RPC response, cookie, credential, local path, task name, or source content is admissible.
