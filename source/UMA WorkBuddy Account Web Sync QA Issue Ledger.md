# UMA WorkBuddy Account Web Sync QA Issue Ledger

Version: 1.0
Date: 2026-07-25
Goal: M2WACCOUNT-G1

| ID | Acceptance concern | Evidence / repair | Status |
| --- | --- | --- | --- |
| WA-001 | WorkBuddy-only exemption could weaken all providers. | Scanner accepts only the two exact source/read-contract pairs; other source classes still fail closed. | Automated PASS |
| WA-002 | A cached account-web value could admit WorkBuddy. | Connector is nonrestorable and admission requires a current successful read. | Automated PASS |
| WA-003 | WorkBuddy.app might remain an admission dependency. | Account-web descriptor requires no runtime; deterministic admission test runs without application discovery. | Automated PASS |
| WA-004 | Broad page or browser data could be collected. | Bounded quota selectors emit only canonical Credit fields; static privacy denylist covers cookie, storage, full-page, network-client, Keychain, and timer APIs. | Automated PASS |
| WA-005 | Malformed or ambiguous Credits could become zero or stale data. | Exact Decimal parsing rejects malformed, duplicate, mixed, excessive, and inconsistent rows; failure withdraws admission. | Automated PASS |
| WA-006 | Account-web failure could fall back to the manual record. | Manual source stays manual-only and hidden; disconnect/failure tests prove no fallback. | Automated PASS |
| WA-007 | Consent withdrawal could leave WorkBuddy visible. | Consent-row withdrawal routes through Disconnect, clears the account-web snapshot, and removes the owned data store. | Automated PASS |
| WA-008 | Private-session choice could leave a persistent session behind. | Switching persistent → nonpersistent releases the browser and removes the dedicated persistent store. | Automated PASS |
| WA-009 | Launch sync could unexpectedly show a login window or create a new session from consent alone. | Launch/current reads use a hidden isolated view, and launch reads are gated by both current consent and a previously established persistent isolated session; only Connect/Open Account Usage show the window. | Automated PASS |
| WA-010 | Main panel and Assistant could diverge. | Both surfaces consume the same admitted snapshot; exact Regular/main and compact Minimalist formatting are covered. | Automated PASS |
| WA-011 | Package could include fixtures, records, tests, or research files. | Path-locked commit archive builder installs only the executable, icon, Info.plist, and provenance plist. | Pending commit-exact audit |
| WA-012 | Official page value and UMA value could differ or external sessions could be changed. | Requires Human login, same-time official balance comparison, WorkBuddy.app-closed proof, Disconnect proof, and Safari/Chrome/WorkBuddy session preservation check. | Pending Human gate |
| WA-013 | “Allow Once” could silently authorize later navigation to the same external host. | External approval is scoped to the single navigation decision; no host approval is cached, and every later external navigation requires a new Human confirmation. | Automated PASS |
| WA-014 | The apex domain or a query-bearing page could bypass the exact official-origin and route boundary. | Only `https://www.workbuddy.cn` is admitted without confirmation; `https://workbuddy.cn` is treated as external, and extraction rejects query- or fragment-bearing variants of the exact Plan and Usage route. | Automated PASS |

## Verification state

After the final runtime repair, the focused account-web suite passed 16 tests,
the full suite passed 209 tests across 29 suites, and Debug, Release, and
strict-concurrency Release with warnings-as-errors builds passed. Final
Light/Dark English and Simplified Chinese renderer evidence passed for the main
panel, Settings, Regular Assistant, and Minimalist Assistant. Commit-exact
package audit and Human physical validation remain required before this ledger
can close.
