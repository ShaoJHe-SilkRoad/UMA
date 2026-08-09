# UMA M6 Antigravity Setup Evidence

**Goal:** M6-SETUP-G1
**Date:** 2026-08-08
**Result:** `PASS — OFFICIAL ANTIGRAVITY CLI SETUP READY FOR M6-G1R`
**Accepted predecessor:** `20a29658d83bef81df3032776ac80ec55c19f5b7`

## Scope

This record contains sanitized installation and capability facts only. It does
not admit a production schema, implement a connector, register Antigravity in
UMA, or authorize M6-G2.

## Desktop correction

The Antigravity desktop application was already installed when M6-G1 ran. The
earlier absence statement was a discovery error, not evidence that the product
was missing.

| Fact | Sanitized observation |
|---|---|
| Application | `/Applications/Antigravity.app` |
| Bundle identifier | `com.google.antigravity` |
| Product/build | `2.6.0` |
| Architecture | arm64 |
| Main executable class | Electron application |
| Bundled `agy` | Absent |
| Other admitted bundled CLI | Absent |

The bundle contains Electron helpers, framework/updater components, an internal
language server, a media encoder, and Chrome DevTools MCP scripts. None is an
official structured read-only Antigravity CLI source. No private protocol or
language-server operation was attempted.

## Official installation provenance

The Founder explicitly accepted the disclosed trust limitation for the current
official Google installer and manifest-pinned release.

| Fact | Sanitized observation |
|---|---|
| Installer source | `https://antigravity.google/cli/install.sh` |
| Installer SHA-256 | `ee1ea43ce4e9e56356c4ab6dad907ef357ae4bdfcaadb682735909fb57c9c640` |
| Release manifest | Official Google-hosted darwin arm64 manifest |
| Manifest version | `1.1.11` |
| Archive SHA-512 | `8a410e20350a5d225526fde43168a3742625dad30f43d254423df8d947a4b6f879ead126801a527e3ff255c508ed2d5edc6352cefb488a849c8885c0895cd21f` |
| Manifest/archive match | Exact |
| Third-party installer or wrapper | None |

The installer downloaded the same manifest-pinned archive, verified SHA-512,
installed the binary in the provider-supported location, removed quarantine
from that installed binary, ran its native setup, and added the documented PATH
export to `$HOME/.zshrc` and `$HOME/.zprofile`.

No global Gatekeeper or macOS security setting changed.

## Installed executable

| Fact | Sanitized observation |
|---|---|
| Installed path | `$HOME/.local/bin/agy` |
| Resolved path | Same; regular file, not a symlink |
| Version | `1.1.11` |
| Build | No separate build identifier reported |
| Type | Mach-O 64-bit executable |
| Architecture | arm64 |
| Ownership | Current user |
| Mode | `0755` |
| Executable SHA-256 | `198ff7c3f6d173daa510b0814aa70c6ce14c94035bcd4707a3c0e79fa38a7bc3` |
| Manifest payload identity | Exact match to the verified extracted payload |
| Embedded identifier | `cli` |
| Embedded Team ID | `EQHXZ8M8AV` |
| Hardened runtime metadata | Present |
| Quarantine | Absent after installer-scoped removal |
| Provenance xattr | Present |

macOS reported the binary signature as invalid and Gatekeeper returned an
internal Code Signing subsystem error. Control checks against Apple system apps
also failed with a local trust-service error, so a reliable local signature or
Gatekeeper PASS was unavailable. The Founder accepted this exact limitation;
provenance for this setup is the byte-identical official installer plus the
official manifest and exact archive checksum, not a successful Developer ID
assessment.

## Installed capability

The exact installed executable returned:

```text
--version: 1.1.11
--help: PASS
```

Installed help confirms:

- noninteractive `--print` with `-p` short form;
- `--output-format` values `text`, `json`, and `stream-json`;
- slash-command expansion in print mode;
- closed-stdin execution without a workspace source tree.

Installed help does not enumerate individual read-only slash commands. The
official 1.1.11 changelog names `/usage` and `/quota`; one setup-readiness
execution proved that the installed argv form produces structured JSON.

No field names, quota values, reset values, bucket lineup, private fields, or
schema shape were retained or admitted. Those remain the responsibility of
M6-G1R.

## Authentication and live-read accounting

The one permitted setup-readiness check used the exact installed executable,
closed stdin, an empty owner-only task directory, and the documented structured
print form. Raw stdout and stderr existed only in process memory, were reduced
to a structured-success classification, and were discarded.

| Operation | Count |
|---|---:|
| Read-only `/usage` executions | 1 |
| Retries | 0 |
| `/quota` executions | 0 |
| `/credits` executions | 0 |
| Provider prompts/tasks | 0 |
| Intentional quota spend | 0 |
| Browser login actions | 0 |

The read completed successfully without opening login. Authentication is
therefore usable for the installed CLI, while remaining entirely provider
owned. UMA and DEV accessed no password, code, identity, cookie, browser
profile, Keychain item, OAuth token, refresh token, or session material.

Credits remain **`CREDITS DEFER`**. No `/credits` command ran and no Credit
schema or value was inspected.

No exact live quota value or account data was retained in Git, task-owned
files, logs, screenshots, or this record.

## Decision

```text
M6-SETUP-G1 PASS — OFFICIAL ANTIGRAVITY CLI READY FOR SOURCE RECHECK
```

Exactly one next task is permitted:

```text
M6-G1R — repeat live Antigravity source admission against the installed CLI
```

M6-G2 and production connector work remain locked.
