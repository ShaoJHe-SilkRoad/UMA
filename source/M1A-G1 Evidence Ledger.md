# M1A-G1 Evidence Ledger

## Implementation contract

- The bundled official Codex CLI app-server is invoked only as `app-server --stdio`. Stdio uses bounded JSON-line JSON-RPC framing with a 2 MiB maximum message body; no raw transcript is retained.
- Provider reads are account-first and schema-constrained: `account/read` with `{}`, then `account/rateLimits/read` and `account/usage/read` with `params: null`. No thread/activity endpoint is active.
- `account/read` treats the presence of the returned account object as the authenticated signal. The installed server reports `requiresOpenaiAuth: true` for the authenticated managed session; that field is a service capability, not an absence signal.
- The local channel accepts only regular, non-symlink `.jsonl` files beneath the two declared session roots. It decodes a restricted metadata tail (maximum 1 MiB), never materializes prompts, messages, tool payloads, credentials, cookies, keychain records, or account identity.
- Per-session cost accounting uses monotonic high-water checkpoints and an atomic backup. The account channel and the local channel have separate availability, freshness, scope, and capture metadata.
- Cancellation/revocation invalidates the active epoch before disconnecting the monitor-owned child. A completed detached local scan must pass the epoch-and-consent gate before it can retain local data or start an account/usage request.

## Regression and repair evidence

- Final exact-staged regression: **26 tests across 4 suites passed**; focused M1A-G1 connector regression: **15 tests across 2 suites passed**. It includes the first-provider-failure fallback: independently valid This-Mac activity remains visible and attributable when the provider has no prior snapshot.
- Earlier broader dirty-worktree validation: **65 tests across 9 suites passed** before frozen visual and renderer WIP was excluded from this commit.
- The focused tests also cover both held-local-reader cases and overlapping-refresh coalescing: disconnect/revoke cannot restart `account/read` or `account/usage/read`, cannot retain the scan result after consent is forgotten, and cannot create a second provider request while one refresh is active.
- Local-cost regression now also proves parent/child inherited-baseline subtraction, durable baseline reuse after the parent tail is unavailable, and conservative skip when a child baseline cannot be reconstructed.
- Protocol coverage includes JSON-line framing, initialize/account/rate/usage wire shapes, schema-required usage summary, notification handling, unexpected-response rejection, and the opt-in redacted live-store test.
- All compiler runs used explicit bounded workspace-local home, temporary, Clang-module-cache, SwiftPM-module-cache, and scratch paths; no real-user compiler cache was used.

## Real provider evidence (redacted)

- One direct official-app-server probe completed `initialize`, `initialized`, `account/read`, `account/rateLimits/read`, and `account/usage/read` against the existing managed session. It recorded only availability/schema booleans, aggregate window metadata, and token-presence/count fields; it retained no account identity or raw payload.
- Accepted Gate A stability evidence ran for **1,200 seconds** with **3** live read cycles and **21** samples. It retained one owned `app-server` child throughout, proved account/rate-limit/account-usage response categories, and completed controlled child termination without retaining private response material.
- The production `UsageStore` opt-in test then completed four non-fixture states: initial account-first connect, two explicit refreshes, and an explicit disconnect/reconnect boundary. At every state, both the provider and local channels were `ready`/fresh; the exact `UsagePanelView` rendered from that production store.
- The live evidence shows a legitimate explicit refresh boundary. The observed notification was only a non-data remote-control status notification; no account/rate update notification is claimed as validated.

## Package, layout, and privacy evidence

- Final exact-staged local-only package: `/private/tmp/codexusage-m1a-g1-package/final-20260716215630/CodexUsageMonitor.app`.
- Bundle ID: `com.kevinchen.CodexUsageMonitor.m1a-g1.evidence.20260716215630`; build: `20260716215630`. `Info.plist` is valid and `codesign --verify --deep --strict` passed. This package is ad-hoc signed only; it was not installed, notarized, released, staged, committed, or pushed.
- The package script now changes to its own repository root before building, so its binary cannot inherit the caller's dirty worktree.
- The exact-staged package exposed one `AXMenuExtra`; native `AXPress` opened its package-owned 370 × 330 panel.
- Fresh Chinese and English ready-fixture renders are each **740 × 1552 px** at `/private/tmp/codexusage-m1a-g1-evidence/m1a-g1-panel-{zh,en}-20260716215630.png`. Visual inspection confirms a continuous outer panel border and fully visible source footer; no style/layout change was made during this continuation.
- Accepted Gate B live-flow evidence used the earlier unique package's native `AXUIElement` status-item control. The target process exposed one `AXMenuExtra`; `AXPress` opened the package-owned panel, confirmed by target-process Accessibility and CoreGraphics window evidence.
- The target-only packaged-panel captures show only approved aggregate rate/usage, reset/freshness, plan-label, and generic local-session presentation. No account identity, conversation title, prompt, raw JSON, credential, or unrelated window was retained.
- Two bounded interactions with the actual visible Refresh control completed and advanced the panel's fresh-capture state. The package stayed responsive, and its visible aggregate data changed only through the real local source.
- After terminating the one package-owned `app-server` child, the same package process remained alive and honestly displayed an earlier-data/retry state. Its native Retry control created one replacement owned child and returned the panel to fresh live data without a package relaunch or child multiplication.
- Two close/reopen cycles through the native status item each observed exactly one attributable status item and a single panel window when open. The post-recovery process inspection observed no more than one owned active `app-server` child.
- Static privacy and fixture-activation audits passed: no active browser, cookie, keychain, URL, `thread/list`, or `account/logout` invocation was found in the production path, and the production application entry has no preview/fixture activation switch. The sole `account/logout` text is a comment explicitly saying it is never called.

## Remaining evidence boundary

- M1A-G1 is complete. The retained evidence is deliberately limited to sanitized aggregate package-panel captures and local structural/process records; it does not prove a release, notarization, deployment, browser-login flow, or any work beyond this milestone.

## Native menu-bar continuation evidence

- The accepted package /private/tmp/codexusage-m1a-g1-package/final-20260716182530/CodexUsageMonitor.app was controlled through its own AXMenuBarItem rather than an ordinary application window. Its Accessibility role was AXMenuBarItem; AXPress succeeded and opened one package-owned 370 × 836 panel.
- The package-only AX classifier confirmed that the opened panel exposed sanitized aggregate usage, percentage, and reset/freshness signals. It emitted no UI text, account identity, raw response, prompt, conversation, credential, or screenshot.
- Two actual packaged Refresh actions each reported an AX transient state, completion state, changed visible aggregate state, and a restored percentage/reset/freshness/usage summary state.
- The sole owned app-server child was terminated in a controlled test. The package PID remained alive, the panel changed to its honest Retry state, and the actual Retry control restored fresh sanitized values without relaunch. The replacement was exactly one direct app-server child.
- Native System Events could not address this accessory package through an ordinary window (-1719); Method 1 had already opened the status item, so Methods 2–4 were not needed for status-item acceptance. No new screenshot or recording was retained.
- Before final uniqueness measurement, one accidental duplicate temporary-package process created by the continuation launch was closed. Final native process accounting recorded one package process, one attributable status item, one connector process, and one owned active app-server child.

## Bounded manual-connect repair evidence — 2026-07-17

- **Root cause**: the accepted Connect action began by awaiting the optional local-session metadata scan. On a real session tree that scan could outlast the UI transition, so the account-first provider read never began and the panel returned to a non-progressing reconnect state.
- **Repair**: the store now owns the confirmed connection task and starts the bounded account-first provider path immediately. The independent local metadata scan runs separately, merges only when its state epoch and consent still match, and cannot overwrite a later connection result.
- **Quota presentation repair**: standard provider windows are reduced to one most-restrictive five-hour and one most-restrictive seven-day window. When a validated weekly record authoritatively omits the five-hour record, the upper five-hour row is retained as the documented unlimited credit state: its bar remains visible and its status is `♾️`, not a fabricated percentage.
- **Current source validation**: all **72 tests across 9 suites** passed using bounded compiler paths. The focused M1A-G1 connector suite included 16 tests covering accepted/rejected confirmation, connection before a held local scan, state cancellation, restrictive weekly selection, and both explicit/unreported unlimited-five-hour forms.
- **Candidate package validation**: temporary package `/private/tmp/codexusage-m1a-g1-package/m1a-g1-authoritative-unlimited-20260717004100/CodexUsageMonitor.app` (ad-hoc signed; valid plist and strict deep code-sign check) accepted native Connect/Allow. Sanitized AX evidence then showed exactly one visible seven-day row, an infinity status, and no raw account data. Two actual Refresh actions both observed a transient state and returned to a valid percentage/reset/freshness/usage panel; one completion classifier remained inconclusive because its post-refresh text did not change.
- This repair evidence is prepared for the bounded repair commit. Commit-exact Gate B remains the final acceptance condition; this record does not claim a release, account mutation, browser login, or credential access.
