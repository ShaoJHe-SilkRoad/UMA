# UMA M3 Claude Configuration and Restore Contract

Date: 2026-07-24

## Current configuration result

Claude Code is not installed. The bounded configuration inventory found:

- `CLAUDE_CONFIG_DIR` unset in the task process and GUI-session environment;
- `$HOME/.claude/settings.json` absent;
- `<M3>/.claude/settings.json` absent;
- `<M3>/.claude/settings.local.json` absent;
- no macOS managed-preference `statusLine`;
- no system `managed-settings.json` or `managed-settings.d/`;
- server-managed settings unobservable without an installed, signed-in CLI.

Current local classification:
**`NO EXISTING STATUS LINE`**.

Current global effective classification:
**`UNVERIFIED`**.

No settings file, wrapper, script, or Claude process was created or modified.
No backup was needed because there was no temporary write.

## Official precedence contract

Use this order when resolving the effective setting:

1. managed settings, including server-managed, macOS MDM, and system files;
2. command-line session overrides;
3. local project settings;
4. shared project settings;
5. user settings.

Managed settings are authoritative and must never be modified by UMA. Before a
future probe, run Claude Code `/status` and record only the redacted setting
source classes. If a managed source supplies `statusLine`, stop before writing
a lower-precedence file unless the exact coexistence behavior is independently
proven and permitted.

## Future pre-mutation inventory

Immediately before any authorized future probe:

1. Re-resolve the executable and record path, symlink chain, version, SHA-256,
   and architecture.
2. Recheck `CLAUDE_CONFIG_DIR` in both the task process and GUI-session
   environment.
3. Use `/status` to confirm loaded settings sources.
4. Resolve only the exact effective `statusLine` value and exact referenced
   script, if any.
5. Record whether each candidate file and referenced script exists.
6. Inspect only the status-line structure and the minimum command behavior
   needed for preservation; do not retain unrelated settings.
7. Stop if the target changed during inspection or a managed source prevents a
   safe temporary override.

## Backup contract

For every exact file or referenced script that will be modified:

1. Create one timestamped task root under
   `/private/tmp/uma-m3-g1-config-backup-*`.
2. Record original existence, SHA-256, byte length, owner, group, POSIX mode,
   ACL, flags, and extended-attribute names and values needed for exact
   restoration.
3. Copy the original bytes to a mode-`0600` backup inside that task root.
4. Verify the backup SHA-256 equals the original SHA-256 before mutation.
5. Record the expected task-owned modified SHA-256.
6. Keep the backup and metadata outside Git and out of normal logs.

If the original file did not exist, record exact absence. Restoration then
removes only the exact task-created file and only when its current SHA-256
still matches the task-owned modified hash.

## Mutation contract

- Change only the exact `statusLine` entry and exact task-owned wrapper.
- Preserve every unrelated setting.
- Validate the complete JSON before activation.
- Write a same-directory temporary file with the required metadata, then use
  atomic replacement.
- Never edit a managed settings layer.
- Never write credentials, identity, raw payloads, or source paths.
- The wrapper must read standard input once, sanitize in memory, emit only
  allowlisted evidence under `/private/tmp`, and perform no network request.
- The wrapper must preserve the prior command’s exact invocation, quoting,
  environment, standard output, standard error, exit/failure behavior, and
  latency expectations.

## Recursion and fail-open contract

Before wrapping an existing command:

- resolve direct, symlinked, and shell-wrapped references;
- reject any chain that invokes the proposed wrapper;
- set a task-specific re-entry sentinel;
- permit no more than one prior-command child;
- do not feed sanitizer output back into the status-line command;
- keep relay diagnostics out of the user-visible output.

On sanitizer, evidence-write, or timing failure, the previous command must
still run normally. If preservation cannot be proven, classify
`UNSAFE TO WRAP` and stop.

## Deterministic rollback

Rollback must run on success, failure, interruption, or task stop:

1. Stop the task-owned Claude process and wrapper child, if any.
2. Re-hash each current target.
3. Restore only when the current target still matches the task-owned modified
   hash; otherwise stop to avoid overwriting a concurrent user change.
4. Atomically restore original bytes.
5. Restore owner, group, mode, ACL, flags, and extended attributes.
6. If originally absent, remove only the exact task-created artifact.
7. Verify the restored SHA-256 or exact original absence.
8. Recheck the effective `statusLine` through `/status`.
9. Verify no wrapper reference or task-owned process remains.
10. Verify no task evidence exists outside the declared `/private/tmp` root.

Any restoration mismatch blocks staging until repaired.

## Current restoration proof

Because no mutation occurred, restoration is an absence invariant:

| Target | Before | After | Result |
|---|---|---|---|
| User settings | Absent | Absent | Exact |
| Project settings | Absent | Absent | Exact |
| Local settings | Absent | Absent | Exact |
| System managed settings | Absent | Absent | Exact |
| macOS managed `statusLine` | Absent | Absent | Exact |
| Task wrapper/probe | Absent | Absent | Exact |
| Task-owned Claude process | Absent | Absent | Exact |

No original bytes, permissions, ownership, status-line command, or script were
changed. Server-managed configuration remains unverified, not restored or
altered.

## Preservation decision

Local result:
**`NO EXISTING STATUS LINE`**.

Production wrapper feasibility:
**unproven** until the CLI is installed, `/status` confirms all effective
sources, a live official payload is observed, and prior-command/recursion/
latency tests pass.

This contract is documentation only. It does not authorize installation,
configuration mutation, a permanent wrapper, or M3-G2.
