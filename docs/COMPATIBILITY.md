# UMA compatibility identifiers

UMA is the public product name and **Usage Monitor Altoget** is the full product
name. The following legacy identifiers remain deliberately unchanged in UMA
0.9 Development Preview to preserve existing preferences, consent, and local
usage state.

| Area | Retained identifier |
| --- | --- |
| Swift package | `CodexUsageMonitor` |
| Executable product and file | `CodexUsageMonitor` |
| App executable target | `CodexUsageMonitor` |
| UI module/target | `CodexUsageUI` |
| Bundle identifier | `com.kevinchen.CodexUsageMonitor` |
| Preference domain | `com.kevinchen.CodexUsageMonitor` |
| Language preference key | `app.language` |
| Local connector-consent key | `monitor.consentDecision` |
| Application Support directory | `~/Library/Application Support/CodexUsageMonitor/` |
| Local cost ledger | `~/Library/Application Support/CodexUsageMonitor/token-cost-ledger.json` |

The current user-facing app bundle is `UMA.app`, with `CFBundleName` and
`CFBundleDisplayName` set to `UMA`. Launch-at-login state is managed by macOS
for the retained bundle identity.

These identifiers are implementation compatibility details, not the public
brand. Renaming one can orphan local settings, trigger a new consent flow,
split the cost ledger, or change launch-at-login behavior. Change them only
through a separately designed and tested migration that preserves existing
data and supplies rollback behavior.

Local state is never part of a source export. A clean GitHub upload must exclude
the Application Support directory, preference files, login-item state,
credentials, sessions, account snapshots, and provider responses.
