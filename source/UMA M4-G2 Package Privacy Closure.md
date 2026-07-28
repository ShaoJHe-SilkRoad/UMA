# UMA M4-G2 Package and Privacy Closure

Status: implementation and package contract verified; final artifact is
commit-exact
Date: 2026-07-28

## Package boundary

The M4-G2 package helper builds only from `git archive` of the exact requested
commit and refuses any output other than:

```text
/private/tmp/uma-m4-g2-final-<short-commit>/UMA.app
```

It does not install or replace a Desktop application. The package declares its
full revision, source-archive SHA-256, commit-exact state, version/build, and:

```text
LIVE MANUS BALANCE NOT YET VALIDATED
```

## Required final audit

- exact commit and archive provenance;
- valid plist and stable bundle identifier;
- arm64 executable;
- strict deep ad-hoc signature;
- system-only dynamic dependencies;
- exact admitted Manus endpoint and header name present;
- no `usage.list` or task endpoint;
- no real or synthetic credential;
- no real balance fixture;
- no saved snapshot, cache, database, log, renderer evidence, source, test, or
  governing document;
- no package installation or Desktop replacement.

## Secret evidence

Production owns one Keychain generic-password item with the stable service and
account in the M4-G2 Scope Lock. The request client accepts the key only as an
in-memory argument, adds it only to the single allowlisted request header, and
emits diagnostics containing only `credential=present` or
`credential=absent`. It never records the header dictionary, raw response,
provider message, request ID, account identity, or API key.

The helper exits successfully only after repository, binary, dependency,
signature, provenance, and exact-content checks pass. Its final one-line
receipt is the artifact-specific evidence retained with the Goal report.
