# UMA M5-G1R2 Scope Lock

Date: 2026-07-28

## Current decision

**SETUP REQUIRED — AUTHENTICATED CLI STATUS-LINE EVENT NOT OBSERVED**

M5-G1R2 remains documentation/test-only. No production relay, connector,
model, UI, package configuration, installed application, or account-web path
is authorized or changed.

## Historical M5-G1R decision

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

## Repository baseline

- Branch: `codex/uma-m5-claude`
- Starting HEAD: `6ac7e955cf6bf17aa32c948c2b6e7939e56f194f`
- Starting tree: `c80d882b8f07a84cce7839b50d5599669f8cf037`
- Starting worktree: clean
- Starting index: empty
- M4: closed
- Manus: unsupported
- Production Manus API-key path: absent

## Governing source

The active governing files are:

- `source/reference/UMA_Logic_1.5.md`
- `source/reference/Scroll_2.1.md`
- `source/reference/M5_Plan.md`
- `source/reference/M5_Goal.md`

Their approved SHA-256 values remained unchanged at task start.

## Exact tracked scope

Only these files may change:

- `source/UMA M5 Claude Local Source Dossier.md`
- `source/UMA M5 Claude Admission Decision.md`
- `source/UMA M5 Claude Configuration and Restore Contract.md`
- `source/UMA M5 Scope Lock.md`
- `source/UMA M5 Claude QA Issue Ledger.md`
- `Tests/CodexUsageUITests/M5G1ClaudeSourceAdmissionTests.swift`

No production runtime source, package configuration, connector, relay,
provider registry, main-panel UI, Desktop Assistant UI, or application bundle
may change.

## Installed-source boundary

Permitted evidence was limited to:

- normal command resolution;
- standard official installation candidates;
- version, architecture, file identity, signature, and trust only if an
  executable existed;
- safe public help and authentication status only if the CLI existed;
- presence/type checks for only the settings keys required by M5-G1R;
- current official Anthropic documentation.

Resolved result:

- Claude Code CLI: trusted Desktop-managed 2.1.219 arm64 component present;
- normal shell launcher: absent;
- executable identity and trust: strict signature and Gatekeeper PASS;
- authentication: logged out; method none; first-party provider;
- local status line: absent;
- global effective settings/policy: unverified;
- temporary probe: blocked before mutation and not used.

## Privacy boundary

No M5-G1R artifact may contain:

- raw status-line JSON;
- real quota values;
- a settings backup;
- an existing status-line command;
- credentials, tokens, cookies, Keychain data, or auth state;
- account identity;
- session or prompt identifiers;
- transcript, prompt, response, task, tool, source, or conversation content;
- private workspace or repository paths;
- screenshots or logs.

Synthetic fixtures must be explicitly synthetic and remain test-local.

## Provider-operation boundary

M5-G1R performed only bounded read-only CLI version, doctor, and
authentication-status invocations. It performed no:

- interactive Claude session;
- login or login-page opening;
- prompt submission;
- synthetic provider task;
- provider response;
- Credit-consuming operation;
- account-web access;
- settings mutation;
- Desktop application operation.

## Verification scope

Required:

- focused M5-G1R source-admission tests;
- allowlist and forbidden-field rejection tests;
- malformed and missing-window tests;
- settings and byte-exact restore fixture tests;
- affected provider-neutral tests;
- M4 retirement regression;
- secret and private-data scans;
- raw-payload and generated-artifact scan;
- production source/package-configuration unchanged audit;
- `git diff --check`;
- exact staged-index audit;
- independent Examiner decision.

## Delivery boundary

After verification, stage only the six exact files above and create one local
commit:

`docs(m5): admit installed Claude local source`

Do not amend or push.

## Next task and Completion Lock

M5-G2 remains locked.

Exactly one next task is permitted:

**M5-SETUP-G1**

Stop after the M5-G1R report and local commit. Do not start M5-SETUP-G1
automatically.

## M5-G1R2 execution lock

Accepted starting state:

- branch: `codex/uma-m5-claude`;
- HEAD: `8b825d181205fd8d484364405044005a53bbd6ba`;
- tree: `0057ae69495cd32ed68454aba545cd5fead0b795`;
- worktree: clean;
- index: empty.

The exact tracked scope remains the same six paths listed above. Temporary
Claude configuration and probe artifacts were permitted only outside Git and
were deleted after exact absence-state restoration.

The Human-controlled response did not produce a status-line callback. This
locks the result to SETUP REQUIRED and forbids inferring a quota window,
running another provider task, inspecting Human task content, activating
account-web fallback, or beginning production implementation.

Delivery is limited to exact staging of the six authorized files,
independent cached-diff review, and one local commit:

`docs(m5): admit authenticated Claude local source`

Do not amend or push.

M5-G2 remains locked. Exactly one next task is:

**M5-SETUP-G1**

This denotes a separately authorized status-line activation setup revision.
The completed launcher-installation and subscription-authentication setup
remains closed and cannot be repeated under this lock.
