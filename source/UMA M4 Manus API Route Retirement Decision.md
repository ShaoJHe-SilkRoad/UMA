# UMA M4 Manus API Route Retirement Decision

Status: final
Date: 2026-07-28
Decision: retire the M4-G2 API-key prototype from product source and packaging

## Decision

Founder rejected API-key product access and limited any future Manus
reconsideration to an official documented local CLI or public local IPC
contract that directly supplies current Credits without exposing credentials
or private data.

M4-N therefore removes the prototype's connector, client, strict decoder,
Keychain store, scheduler, Settings controls, registry admission, panel and
Desktop Assistant presentation, localization, tests, and active package
helper. Shared source changes that served only that route return to their
accepted pre-M4-G2 behavior.

No real Manus key was used. No live Manus Credit request completed. The
prototype was never installed, released, deployed, notarized, or admitted for
production. Its original implementation remains reviewable in historical
commit `695201d5ad56935a126ac5086ff0e8460dc4724e`; it is not present in the
retirement commit's product tree or package.

## Final provider state

```text
Manus: UNSUPPORTED — NO ADMITTED LOCAL CLI SOURCE
```

There is no manual-entry fallback, estimated balance, browser source, OAuth
flow, API-key route, hidden feature flag, or live-validation continuation.
