# UMA M5RMX Certified Debug Baseline

**Version:** 1.0
**Certified:** 2026-08-19
**Status:** `UMA CERTIFIED DEBUG BASELINE — PASS`

## Historical-scope notice

This file certifies only the frozen 0.12 combined-app bytes named below. It is
not the current 0.13 release architecture, manifest inventory, or installation
procedure. Current UMA separates the mutable app from an immutable Safari Host,
and its Companion uses the exact `https://claude.ai/new*` Safari Manifest V2
site entry plus a static top-frame `document_start` ownership/content script for
Human-requested one-shot Accuracy Sync. The current manifest has no `storage`
permission and no `activeTab`/`scripting` permission. All extraction remains
gated to the exact Usage hash route, and the current normative boundary is
`UMA M5RMX Claude Privacy Contract.md`.

Nothing in this notice changes, rewrites, or requalifies the immutable 0.12
notarization evidence below.

## Certified immutable artifacts

The certified source baseline is commit
`cdb93ffce73f05905bda415247f38d6cf4396c01`, tree
`d7327372ee53432320a8123975ec8712f410b972`.

The exact accepted application is:

`/Users/juliushe/Developer/UMA-Packages/uma-m5rmx-safari-preflight-cdb93ffce73f05905bda415247f38d6cf4396c01/UMA.app`

Its identity is `com.silkrd.uma`, version `0.12`, build `202608180001`.
The embedded Safari extension is
`com.silkrd.uma.ClaudeBrowserCompanion`, version `1.3.0`, build `8`, at
`Contents/PlugIns/ClaudeBrowserCompanion.appex`. The native helper is
`Contents/Helpers/ClaudeBrowserNativeHost`.

The frozen original upload archive is:

`/private/tmp/uma-m5rmx-safari-notary-cdb93ffc/UMA-m5rmx-safari-cdb93ffc.zip`

Its SHA-256 is
`454df7becf927362d9fd9496dd764e03cd35f628302defce8e49eecfc6a1cb46`.

These app and archive bytes are immutable evidence. Never rebuild in place,
re-sign, strip, repack, replace, staple again, or remove the staple.

## Apple distribution identity

- Apple Team ID: `C6TUZVJ6SJ`
- Signing identity class: `Developer ID Application`
- Local notary profile name: `UMA-notary`
- Accepted submission: `12f73c32-dc4d-45a9-86d3-7c3b89f04f88`
- Apple result: `Accepted`
- Submitted timestamp: `2026-08-18T17:24:07.877Z`
- Child-first Hardened Runtime signing: PASS
- Secure timestamp: PASS
- Strict deep signature verification: PASS
- Stapler validation: PASS
- Gatekeeper: PASS — `Notarized Developer ID`
- Architectures: arm64 application, extension, and native helper

No credential value or notary-profile content is recorded here.

## Normal Safari acceptance

Safari accepted the signed and notarized extension in normal mode with
`Allow unsigned extensions` OFF. The extension permission surface is exactly:

- `nativeMessaging`
- `storage`
- `https://claude.ai/new*`

There are no static content scripts, no separate persistent host-permission
array, and no broader site grant. The normal registration procedure is:

1. Verify the exact frozen application, nested extension, and helper.
2. Register the containing app with LaunchServices and its exact embedded
   extension with PlugInKit.
3. Launch that exact containing app.
4. In Safari Settings, enable `UMA Browser Companion for Claude 1.3.0` and
   allow only `claude.ai`.
5. Keep Safari unsigned-extension mode OFF.

The Desktop `UMA_0.12.app` carries an older extension version `1.2.3` under
the same extension identifier. That duplicate registration can cause Safari
to select or expose the wrong build. For a bounded test, record the old
registration and disabled state, unregister only that exact old registration,
register the certified `1.3.0` candidate, test, then disable and unregister the
candidate and restore the exact old registration and its disabled state. Do
not modify either app bundle.

## Certified live chain

The certified candidate completed this chain in normal Safari:

`provider-controlled Claude session → exact Usage route → bounded browser extraction → sanitizer → usage-only native packet → native helper → UMA Browser Sync`

The current signed Browser Sync observation passed. One completion-relative
automatic refresh also passed without another toolbar action. The observations
carried normalized usage fields only; exact private values were not retained.
There was one scheduler, one read in flight, no retry burst, no user-tab
corruption, zero Claude prompts or tasks, zero intentional spend, and zero
account mutations.

## Privacy and cleanup contract

Claude and Safari may internally own the authenticated session. UMA must never
receive or retain passwords, API keys, access or refresh tokens, cookies,
browser profiles, Keychain credential contents, account identity, raw DOM,
raw HTML, chats, projects, billing, or payment history. The browser layer must
reduce the page to the closed, bounded usage observation before native handoff.

At closeout the candidate was disconnected, its sanitized cache was absent,
the handoff directory was empty, task-owned app/helper processes were absent,
the candidate extension was disabled and unregistered, and the old Desktop
`1.2.3` registration was restored to its original inactive/disabled effective
state. Safari unsigned-extension mode remained OFF.

## Future-build rule

This record certifies only the exact frozen bytes above as a debug baseline.
Any source, resource, entitlement, helper, extension, or application change
changes the signed product. A changed build must receive its own child-first
Developer ID signing, strict verification, notarization, staple, Gatekeeper,
normal-Safari, protocol, privacy, and cleanup acceptance before release.
Ordinary development builds must not submit to Apple automatically.

`M5RMX-SAFARI-G1 — PASS`
