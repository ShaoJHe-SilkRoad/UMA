# UMA M5 Claude Configuration and Restore Contract

Date: 2026-07-28

## Current M5-G1R2 decision

**SETUP REQUIRED — AUTHENTICATED CLI STATUS-LINE EVENT NOT OBSERVED**

M5-G1R2 exercised the absence-state branch of this contract. The original
user settings file and `statusLine` were absent. A temporary owner-only
settings file referenced one task-owned allowlist probe, then was removed
after the Human CLI checkpoint produced no callback evidence. Final settings
file and `statusLine` state are again absent.

No existing command required wrapping, no raw payload was written, and every
task-owned configuration, backup-marker, probe, and evidence artifact was
deleted.

## Historical M5-G1R decision

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

This contract records both the M5-G1R preservation result and the boundary for
a future authorized Claude local-source recheck. M5-G1R authorized a temporary
probe only after its trust and authentication preconditions passed.

## Official settings hierarchy

The current official precedence is:

1. managed settings;
2. command-line session overrides;
3. local project settings;
4. shared project settings;
5. user settings.

Managed settings cannot be overridden by lower scopes.

The inspected local sources were absent:

- user settings;
- shared project settings;
- local worktree settings;
- main-checkout local settings;
- file-based macOS managed settings;
- macOS managed-preferences file;
- user preferences file for the managed domain.

Allowlisted local key-presence checks found no:

- `statusLine`;
- `disableAllHooks`;
- `allowManagedHooksOnly`;
- `apiKeyHelper`;
- API-key, bearer-token, or setup-token route name.

Server-managed settings are unverified because the trusted CLI is logged out.

## Current preservation and restore result

- Existing local status line: absent
- Existing status-line command read: no
- Settings file modified: no
- Settings backup created: no
- Probe installed: no
- Restore operation required: no
- Local absence state after inspection: unchanged
- Temporary trust artifacts retained: no

This is not a live restore PASS. It is proof that no configuration mutation
occurred and that the original absence state did not require restoration.

## Future preconditions before any temporary probe

A later specifically authorized task must establish all of the following
before writing a settings file:

1. reverify the trusted CLI identity already established by M5-G1R;
2. establish provider-managed subscription authentication without reading
   credentials;
3. every loaded settings source, including server-managed policy;
4. effective `statusLine`, `disableAllHooks`, and relevant policy state;
5. workspace trust required for a local command;
6. exact preservation feasibility for any existing status-line behavior;
7. an owner-approved Human checkpoint if one normal provider response is the
   only missing source condition.

If any effective status-line command already exists and its behavior cannot be
preserved exactly, probing is prohibited.

`disableAllHooks: true` is an explicit status-line blocker. The presence of
`allowManagedHooksOnly` requires policy review, but the official documentation
does not by itself prove that this key disables `statusLine`.

## Backup contract

If a future task is authorized to change exactly one settings file:

1. identify the effective source before writing;
2. record original existence, owner, mode, byte count, and SHA-256 without
   printing content;
3. create one task-owned byte-exact backup outside Git;
4. set the backup to owner-only mode `0600`;
5. never print or commit the existing status-line command;
6. never back up credential files or unrelated settings sources;
7. stop if the source changes concurrently.

If the settings file did not exist, restoration means exact removal of the
task-created file and proof that the original absence is restored.

## Temporary allowlist probe contract

A future authorized probe must:

- accept standard input only from Claude Code;
- impose a bounded input size;
- never log or copy raw standard input;
- never open any path named by the payload;
- parse only the two rate-limit windows and optional version;
- reject all unknown, private, malformed, nonfinite, and out-of-range fields;
- record only field presence, type validity, and bounded sanitized evidence;
- avoid a refresh timer unless explicitly required;
- never invoke `claude`;
- never submit a prompt or provider task;
- prevent direct, symlinked, and shell-wrapped recursion;
- avoid network access;
- preserve existing status-line stdout and failure behavior when preservation
  is proven feasible.

The single official `statusLine` object has no documented chaining contract.
A later implementation must not claim preservation by merely replacing an
existing command.

## Restore contract

Restoration must occur after success, failure, interruption, cancellation, or
task stop:

1. stop the task-owned probe;
2. restore the exact original bytes atomically;
3. restore original owner and mode;
4. verify SHA-256, byte count, owner, mode, and existence state;
5. verify the effective settings source again;
6. delete temporary sanitized output;
7. delete the backup only after restoration proof;
8. retain no raw provider payload.

A restore hash, metadata, or effective-source mismatch is a blocker. No
production work may continue after a restore failure.

## Fixture-test boundary

M5-G1R tests exercise only synthetic settings bytes in task-owned temporary
directories. They prove the contract logic can preserve exact bytes,
formatting, unknown keys, and final newlines. They do not represent a live
Claude settings mutation or restoration.

## Next task

M5-G2 remains locked.

Exactly one next task is permitted:

**M5-SETUP-G1**

## M5-SETUP-G1 completion addendum

M5-SETUP-G1 did not inspect or modify Claude status-line configuration.
The user Claude settings file remained absent, so no `statusLine` was created
and no Claude-settings backup or restoration was required.

The separate shell-launcher repair followed the official native installer
instruction:

- original user Zsh configuration: absent;
- task-owned absence backup: owner-only;
- final configuration: one standard
  `export PATH="$HOME/.local/bin:$PATH"` line;
- fresh-shell launcher resolution: PASS;
- fresh-shell Claude Code version: 2.1.220;
- fresh-shell `claude doctor`: PASS with no installation issues;
- task-owned backup after verification: removed.

Provider-managed `claude.ai` authentication is active, while API-key,
copied-token, setup-token, Bedrock, Vertex, and Foundry routes are inactive.
No credential value or account identity was accessed.

The temporary status-line probe remains prohibited in this setup task. M5-G2
remains locked. Exactly one next task is:

**M5-G1R2**

## M5-G1R2 exercised restore record

Pre-mutation state:

- user settings file: absent;
- user `statusLine`: absent;
- local `disableAllHooks`: absent;
- local managed-settings file: absent;
- local managed-preferences files: absent;
- existing status-line output and exit behavior: not applicable;
- exact absence-state restoration: feasible.

Temporary mutation:

- affected settings source: user settings only;
- file permissions: owner-only;
- status-line type: command;
- command content: not retained in this record;
- input limit: 64 KiB;
- network access: none;
- payload-supplied path access: none;
- raw input logging or persistence: none;
- evidence projection: generic allowlisted validity states only.

The original file did not exist, so byte-hash equality is not applicable to
the restore target. Its exact backup state was recorded as absence in an
owner-only marker. The temporary settings file was verified against its
task-owned source hash before removal.

Post-checkpoint restoration:

- temporary settings file: removed;
- final user settings file: absent;
- final `statusLine`: absent;
- absence marker: deleted;
- probe: deleted;
- sanitized evidence location: deleted;
- raw provider payload: never written;
- persistent Claude configuration change: none.

The Human completed one normal response in the installed CLI. The probe was
not invoked, so this contract records no quota-field capability claim.

M5-G2 remains locked. Exactly one next task is:

**M5-SETUP-G1**

This next-task label means a separately authorized status-line activation
setup revision only. The prior launcher and subscription-authentication setup
remains closed and must not be repeated.
