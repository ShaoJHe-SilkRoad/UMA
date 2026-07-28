# UMA M4 Manus Admission Decision

Status: M4 CLI-only source decision — current authority
Date: 2026-07-28
Decision: **NO-GO**

## Decision statement

**NO-GO — NO OFFICIAL LOCAL MANUS CLI CREDIT CONTRACT EXISTS.**

Founder direction admits only:

```text
Official Manus CLI
  → documented read-only structured Credits output
  → current total available Credits
  → UMA connector
```

The installed Manus 1.6.8 arm64 bundle supplies no public CLI command on PATH.
Its additional `sidecar` executable is undocumented as a public CLI, and both
the enclosing application and `sidecar` fail strict signature verification.
Current official Manus documentation contains no CLI installation,
authentication-reuse, status, usage, Credits, JSON, schema, or local freshness
contract for a Manus command.

No documented CLI command was run because no documented CLI exists. No
structured Credit field was available, no authentication boundary was
crossed, and no task or Credit-consuming operation occurred.

## Admission failure basis

- no official Manus CLI installation or executable contract is documented;
- no documented `status`, `usage`, or `credits` command exists;
- no documented JSON or other machine-readable Credit schema exists;
- no command directly returns current total available Credits;
- the undocumented bundled `sidecar` is not an admissible public interface;
- the installed bundle's failed trust checks forbid treating its executables
  as a stable source;
- human-readable scraping, private-state inspection, API keys, OAuth, browser
  sessions, manual entry, estimation, and task-generating probes are forbidden.

## API-key route retirement

The former M4-G1 **CONDITIONAL GO** for the API-key endpoint is revoked. The
M4-G2 API-key implementation is not admitted for production, packaging, live
validation, deployment, or release. Manus remains unsupported and hidden.

M4-N removes the M4-G2 API-key implementation from the product and final
package while preserving the original M4-G2 commit as historical Git
evidence. No production connector, Settings entrance, credential store,
scheduler, endpoint request, or presentation path remains.

## Authentication and consumption boundary

No API key, OAuth token, cookie, session, Keychain item, auth database, account
identity, or private application state was accessed. No Manus application
task, agent, project, file, browser, or network operation was invoked. The
official Desktop Credit documentation states that merely opening or running
the Desktop app does not consume Credits; Credits are deducted during active
agent task processing. This recheck did not launch such processing.

## Re-admission lock

A future Manus source may be reconsidered only after Founder instruction and
only if official documentation proves a local CLI that directly returns
current total available Credits through a stable read-only structured schema,
without credential disclosure, private-data access, or Credit consumption.

Do not search hidden or reverse-engineered alternatives, do not fall back to
manual Credit entry, and do not move to another source class without a new
Founder instruction.
