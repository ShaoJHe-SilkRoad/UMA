# M1A-G2 QA Issue Ledger

| ID | Status | Resolution |
| --- | --- | --- |
| G2-01 | Resolved | Registry listener races could hide an immediate command result; commands now publish their current normalized snapshot synchronously to the registry. |
| G2-02 | Resolved | A slow local metadata read delayed a completed account result; the adapter now publishes the account channel first and delivers the local aggregate independently. |
| G2-03 | Resolved | Connector stop events could overwrite a deliberate consent revocation; the shared store ignores registry updates after consent is revoked. |

No open in-scope issue is accepted without a reproducible failing check.
