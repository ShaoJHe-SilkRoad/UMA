# M1A-G2 QA Issue Ledger

| ID | Status | Resolution |
| --- | --- | --- |
| G2-01 | Resolved | Registry listener races could hide an immediate command result; commands now publish their current normalized snapshot synchronously to the registry. |
| G2-02 | Resolved | A slow local metadata read delayed a completed account result; the adapter now publishes the account channel first and delivers the local aggregate independently. |
| G2-03 | Resolved | Connector stop events could overwrite a deliberate consent revocation; the shared store ignores registry updates after consent is revoked. |
| G2-04 | Resolved | A duplicate-save shortcut prevented a schema-zero envelope from being rewritten during its required next save. The store now suppresses only a byte-identical on-disk v1 snapshot; deterministic migration coverage passes. |
| G2-05 | Resolved | Native AX/CG validation replaced the unavailable Computer Use path: Connect/Allow, two Refresh actions, sanitized quota evidence, and owned-child recovery are now proven in the unique temporary candidate. |
| G2-06 | Resolved | Refresh did not recreate an unexpectedly exited owned app-server child on the first action. The connector now performs one account-first retry only when the production client explicitly reports an owned-process exit; focused and full regression coverage pass. |

No open in-scope issue is accepted without a reproducible failing check.
