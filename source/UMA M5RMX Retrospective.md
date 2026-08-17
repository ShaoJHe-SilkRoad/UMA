# UMA M5RMX Retrospective

**Version:** 1.0

**Date:** 2026-08-17

**Task:** `M5RMX-B0`

**Starting commit:** `01b190260da857f55fa5fa9b14da9715cafbc221`

**Starting tree:** `49f2af499c86b9b8757da0e9406a0d9e5c24495b`

## 1. Result carried into M5RMX

M5RMX begins from the accepted M8 closeout lineage without reconstructing
Claude from zero. The parent and new worktree both resolve to the exact HEAD and
tree above. The accepted predecessor baseline is `683/683 PASS`; focused M8 is
`32/32 PASS`. B0 separately reproduced a fresh `6/6` focused contract and a
deterministic serial `689/689` full suite (`671` UI plus `18` bridge). Parallel
diagnostic runs exposed unrelated historical lifecycle-test timing instability;
each reported test passed in isolation and the required `--no-parallel` suite
passed. Debug, Release, and strict-concurrency Release with warnings as errors
all passed.

Current providers:

```text
Codex → Claude Code → WorkBuddy → Google Antigravity
```

Cursor and Kimi are unsupported/hidden. M7 closed Cursor because Free-plan
dashboard remaining was not a reliable enforcement predictor and paid-plan
pools were not live qualified. M8 closed Kimi because the authenticated bounded
browser observation repeatedly failed closed on an unsupported Shared
Membership layout; no production Kimi runtime was added. Those decisions remain
closed controls, not M5RMX work.

M6 established four-provider Main Panel/Assistant parity and the safe
process-inspection contract. Its accepted package was local verification
evidence, not a Desktop replacement or public release.

## 2. Current Claude architecture

The current quota path is:

```text
provider-controlled Safari session
→ UMA Safari Browser Companion
→ exact Claude Usage route gate
→ bounded semantic extraction
→ versioned sanitized observation
→ Safari native handler / ClaudeBrowserNativeHost
→ owner-only file handoff
→ ClaudeCodeUsageConnector
→ shared UsageStore presentation
→ Main Panel + Desktop Assistant
```

Automatic Browser Sync owns one completion-relative five-minute scheduler, one
in-flight read, manual/scheduled coalescing, and at most one extension-owned
inactive Usage tab. Safari launch remains a separate explicit preference.
Authentication/permission/route/ownership uncertainty fails closed. Cached and
stale states never manufacture a current read.

The local activity/cost path is separate:

```text
allowlisted local Claude JSONL usage fields
→ ClaudeLocalActivityReader
→ this-Mac token/activity and API-equivalent cost estimate
→ expanded Claude presentation
```

It is not billing truth and never contributes an account quota window.

Claude Browser Sync is current through Safari and the status-line quota route is
retired. The packaged Chromium manual-companion resources have no current live
acceptance and remain unverified; they are not the current Browser Sync owner.
Historical status-line records and the self-contained historical admission test
harness remain as history; there is no active production target or package
route, and the package helper rejects reintroduction.

## 3. Accepted Claude claim-to-code map

Status vocabulary:

- `ACCEPTED CURRENT`: current production owner and deterministic/current-live
  evidence exist.
- `ACCEPTED BUT NEEDS M5RMX COMPLETION`: accepted behavior exists, but final
  0.12 distribution, onboarding, or supportability is incomplete.
- `HISTORICAL / RETIRED`: evidence is retained but the route is not production.
- `UNPROVEN / FUTURE`: must not be represented as shipped.

| Accepted claim | Current source owner | Deterministic tests | Current live evidence | Packaged owner | Latest modifying commit | Status / known risk |
|---|---|---|---|---|---|---|
| Safari Browser Sync is the Claude account-quota source | `ClaudeCodeUsageConnector.swift`; `ClaudeBrowserProductionIntegration.swift` | `M5G2ClaudeConnectorSettingsTests`; `M5ADBGG1BrowserSyncClosureTests`; `M5G3ClaudeLiveAcceptanceTests` | M5-AUTO-R1 accepted first read plus two completion-relative Safari refreshes | main executable plus embedded Safari companion/native host | connector `9fda8875…`; integration `c6245f9c…` | `ACCEPTED CURRENT`; Chromium is unverified and final distribution support remains incomplete |
| Only the official Usage page is inspected | `claude-usage-extractor.js`; `content-script.js`; protocol constants | `M5G3ClaudeLiveAcceptanceTests`; `M5AUTOG1ClaudeAutomaticRefreshTests` | accepted Safari Usage-page validation | appex and Chromium manual companion shared extractor | `365a42f5…` | `ACCEPTED CURRENT`; exact route must continue to precede every DOM query |
| Browser output is sanitized before native handoff | `ClaudeBrowserBridgeProtocol.swift`; extractor validator; `ClaudeBrowserMessageDecoder.swift` | live-acceptance decoder/extractor tests; bridge tests | accepted Browser Sync privacy audits | bridge protocol linked into host and appex | protocol `c6245f9c…`; decoder `365a42f5…` | `ACCEPTED CURRENT`; schema drift fails closed |
| Native handoff is bounded and owner-only | `SafariWebExtensionHandler.swift`; `ClaudeBrowserNativeHost/main.swift`; `ClaudeBrowserFileHandoff.swift` | M5ADBG listener/cache/symlink tests; native framing tests | accepted native handoff and teardown evidence | `Contents/Helpers/ClaudeBrowserNativeHost` and Safari appex | handoff `365a42f5…`; Safari entitlement origin `9c885fa6…` | `ACCEPTED CURRENT`; temporary file exception needs Apple adjudication |
| One scheduler and one in-flight extraction | `ClaudeCodeUsageConnector.swift` | AUTO scheduler, collision, timeout, relaunch, idle tests | accepted 5-minute completion-relative live cadence | main executable | `9fda8875…` | `ACCEPTED CURRENT`; no retry/catch-up bursts |
| At most one extension-owned inactive Usage tab; user tabs remain untouched | `background-core.js`; `content-script.js`; production integration close command | AUTO ownership/proof/collision/close tests; G3 Safari ownership test | accepted automatic Browser Sync live observations | Safari appex background resources | `365a42f5…` | `ACCEPTED CURRENT`; ownership uncertainty suspends automation |
| Fresh, Cached, Stale, expired, and unavailable are honest | connector; `ClaudeBrowserSanitizedCacheStore.swift`; shared presentation | G2 retention/cache tests; M5ADBG exact boundary tests; Assistant state tests | accepted live source transition evidence | main executable, owner-only cache at runtime | cache `cf339597…`; connector `9fda8875…` | `ACCEPTED CURRENT`; cached/stale is never a new decrement sample |
| Settings owns consent, source transparency, repair, Sync Now, automation, Safari launch, and disconnect | `ClaudeBrowserSettingsModel.swift`; `UsageSettingsCard.swift`; `AppLanguage+Claude.swift` | G2 Settings tests; AUTO disclosure/action tests; M5ADBG localization tests | accepted Browser Sync setup/repair and automation validation | main executable/localized UI | settings model `365a42f5…` | `ACCEPTED BUT NEEDS M5RMX COMPLETION`; final extension onboarding/support UX remains a program target |
| Five-hour and weekly/7-day used values normalize to remaining once | protocol quota windows; extractor; connector snapshot builder; shared presentation | G2 independent-window tests; G3 semantics tests; Assistant parity/window tests | accepted Claude Usage-page observations without durable exact values | main executable and extension | connector `9fda8875…`; shared presentation `ebc79d77…` | `ACCEPTED CURRENT`; missing/malformed windows remain unavailable |
| Main Panel shows current Claude shared truth | `UsageStore.swift`; `SharedUsagePresentation.swift`; `UsagePanelView.swift` | M5G2; M5DBG; M6 combined parity regressions | accepted M5/M6 physical matrices | main executable | shared presentation `ebc79d77…`; panel `532c705c…` | `ACCEPTED CURRENT`; later M6 edits preserved Claude semantics |
| Desktop Assistant adapts shared truth and owns no transport/selection | `SharedUsagePresentation.swift`; `DesktopAssistantView.swift`; status-bar/panel controllers | `M5AG1ClaudeAssistantTests`; M6 Assistant/combined tests | accepted M5A/M6 Main/Assistant parity | main executable | Assistant `9535fc02…`; shared presentation `ebc79d77…` | `ACCEPTED CURRENT` |
| Stable provider registration/order is Codex, Claude Code, WorkBuddy, Antigravity | `AgentConnectorRegistry.swift`; application/status-bar assembly; shared policy | M5A provider-order tests; M6 four-provider tests; M7/M8 hidden-provider tests | accepted M6 four-provider closeout | main executable | later M6 lineage | `ACCEPTED CURRENT`; Cursor/Kimi remain unregistered/hidden |
| Local Claude activity/cost is a separate this-Mac estimate | `ClaudeLocalActivityReader.swift`; connector merge/local channel | `M5LAG1ClaudeLocalActivityTests` | accepted local fixture/privacy evidence; no provider call | main executable only | `9fda8875…` | `ACCEPTED CURRENT`; estimates are not bills or quota |
| English/zh-CN Claude source/freshness/action/accessibility copy is centralized | `AppLanguage+Claude.swift`; panel/Settings/Assistant views | M5A language/accessibility; M5ADBG localization; M6 matrices | accepted Light/Dark/EN/zh-CN/accessibility matrices | main executable | current lineage | `ACCEPTED CURRENT`; physical VoiceOver was deferred in M6 |
| Package embeds and audits the app, native host, Safari appex, Chromium companion, and provenance | `script/package_uma_m5_g2.sh`; `Package.swift`; manifests/Info/entitlements | M5G3 package acceptance; AUTO package-phase test; package audits | accepted M5/M6 local packages | package helper file allowlist | `c6245f9c…` for helper; Package.swift `2e9cfdf9…` | `ACCEPTED BUT NEEDS M5RMX COMPLETION`; helper still declares 0.11 and final 0.12 notarization is not proven |
| Status-line quota integration is not an active product source | no status-line Package target/source directory; packaging guard; Browser Sync source transparency | M5-SLR guards; M5G3 forbidden-route test; historical harness retained only as history | M5-SLR machine/repository removal evidence | absent from package by allowlist/forbidden scan | `2e9cfdf9…` | `HISTORICAL / RETIRED` |
| Notarized final 0.12 and signed distribution extension acceptance | no accepted final artifact yet | future SAFARI/H1/RC gates | Apple smoke backend anomaly only | future M5RMX package | future | `UNPROVEN / FUTURE` |

No row is upgraded from plan text alone. Exact historical live values, identity,
credentials, cookies, tokens, raw DOM, and browser state are not retained here.

## 4. Claude file-ownership inventory

| Classification | Current paths | Rule |
|---|---|---|
| Claude Safari Extension source | `BrowserExtension/Shared/**`, `BrowserExtension/Safari/background-loader.js`, `BrowserExtension/Chromium/**` | Claude-only; exact-route and permission review required |
| containing-app / extension metadata | `BrowserExtension/Safari/Native/Info.plist`, `ClaudeBrowserCompanion.entitlements` | Claude distribution boundary; no speculative entitlement broadening |
| native bridge/protocol | `Sources/ClaudeBrowserBridgeProtocol/**`, `Sources/ClaudeBrowserNativeHost/**`, `Sources/ClaudeBrowserNativeHostCore/**` | closed schema, bounded frame, owner-only handoff |
| Browser Sync coordinator/cache/connector | `ClaudeCodeUsageConnector.swift`, `ClaudeBrowserProductionIntegration.swift`, `ClaudeBrowserSanitizedCacheStore.swift` | one scheduler/read, fail closed, sanitized cache only |
| local activity/cost | `ClaudeLocalActivityReader.swift` plus connector local-channel mapping | local estimate only; no account-quota claim |
| Settings/localization/UI | `ClaudeBrowserSettingsModel.swift`, `AppLanguage+Claude.swift`, Claude sections of Settings/panel/Assistant | source transparency and safe actions only |
| shared provider-neutral runtime/UI | registry/runtime/snapshot store, `UsageStore`, `SharedUsagePresentation`, `UsagePanelView`, `DesktopAssistantView`, app/status-bar controllers | additive-only; protected-provider regression required |
| package/signing/notarization tooling | `Package.swift`, `script/package_uma_m5_g2.sh`, native manifests, extension manifests | exact inventory/provenance; later Release/Live Action gates own external actions |
| Claude tests/fixtures | `Tests/CodexUsageUITests/M5*.swift` and bounded fixture helpers | deterministic, sanitized; historical status-line harness is not runtime |
| current governance/historical evidence | M5 current records, M5RMX records, retained historical M5 files | add current truth; do not erase stage history |
| generated/private evidence | build roots, browser state, owner-only runtime handoff/cache, live exact values | never source-controlled or packaged |
| protected unrelated provider | Codex, WorkBuddy, Antigravity production source/tests | no source/auth/cadence/semantic change |

## 5. Extension, native host, and package inventory

| Item | Current evidence | Classification |
|---|---|---|
| Safari extension bundle | `Contents/PlugIns/ClaudeBrowserCompanion.appex`; ID `com.silkrd.uma.ClaudeBrowserCompanion`; extension point `com.apple.Safari.web-extension` | real embedded Safari Web Extension target assembled by package helper |
| Safari manifest | MV2, version `1.2.3`; permissions `nativeMessaging`, `storage`, `https://claude.ai/new*`; persistent background; no static content scripts/host_permissions key | accepted automatic source contract; exact hash route still checked in code |
| Safari entitlements | sandbox true; one exact home-relative R/W temporary exception; no network client | accepted current development behavior; final Apple entitlement acceptance unproven |
| Chromium companion | MV3, version `1.0.1`; `activeTab`, `nativeMessaging`, `scripting`; no host permissions/static content scripts | packaged manual companion; `UNPROVEN / FUTURE`, not the current Safari source owner |
| native host | product `ClaudeBrowserNativeHost`; host name `com.silkrd.uma.claude_browser`; allowed Chromium origin pinned to stable ID | bounded bridge executable, no credential transport |
| bridge protocol | schema/source/route/browser/window/automation types; maximum message 4096 bytes | closed sanitized contract |
| file handoff | exact owner-only directory, lock, pending file, no symlink traversal, atomic bounded read/remove | app/native process bridge |
| package contents | app executable, helper, appex, manifests/scripts, app icon, Chromium resources/host manifest, provenance | exact allowlist; no fixtures/logs/screenshots/backups/sockets/docs |
| signing modes | ad-hoc default; real identity enables Hardened Runtime and secure timestamp; optional profile enables notary/staple/assessment | Developer ID infrastructure ready; final notary remains blocked/unproven |
| package identity | bundle `com.silkrd.uma`; helper marketing version `0.11`; default build `202608010001` | 0.12 update is required later; B0 does not repair it |
| development assumptions | Safari development/live tests historically used Human-enabled unsigned-extension mode; final distribution cannot depend on that mode | `ACCEPTED BUT NEEDS M5RMX COMPLETION` |

## 6. Apple handoff — record only

Apple Team `C6TUZVJ6SJ`, Developer ID Application/private-key infrastructure,
Hardened Runtime, secure timestamp, `notarytool`, and the `UMA-notary` profile
are accepted. Historical smoke submission
`bced6fed-8c8b-469e-924b-9b8a98395b6d` entered an Apple backend anomaly and is
currently `APPLE-G1 BLOCKED — APPLE NOTARY BACKEND / SUPPORT INVESTIGATION`.
Feedback `FB24386147` and support case `20000140194585` track it. The exact smoke
`.app` and `.zip` remain protected under
`/private/tmp/uma-apple-g1-smoke-01b1902/`. Bounded local verification, without
an Apple query, found the retained app and an isolated archive extraction both
currently fail strict signature verification as code modified, while their
executables have matching SHA-256 values. The scratch extraction was removed;
neither protected artifact was mutated. Current evidence therefore supersedes
the historical signature-valid claim. This infrastructure evidence does not
prove the current UMA package or Safari extension is signed for distribution,
notarized, stapled, or Gatekeeper-accepted.

B0 performed no Apple query, submission, repair, re-signing, stapling,
credential/profile access, or protected-artifact mutation. This preserved-state
discrepancy remains in the parallel external Apple workstream and does not block
the local B0 baseline.

## 7. Desktop and remote inventory

| Path | Current classification |
|---|---|
| `/Users/juliushe/Desktop/UMA_0.11.app` | protected rollback; `com.kevinchen.CodexUsageMonitor`; 0.11 / 202607270003; executable SHA-256 `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` |
| `/Users/juliushe/Desktop/UMA_0.12.app` | pre-existing non-M5RMX-final app; `com.silkrd.uma`; 0.12 / 202608170001; source revision `67520d5a…`; executable SHA-256 `e95e2dac12383016f179564de2cc7e0db2fcccd3d7758a95129f18aa8e8145df`; preserved unchanged |
| `/Users/juliushe/Desktop/CodexUsageMonitor` | separate dirty Human checkout, branch `main`, HEAD `f1da999c…`, behind origin by five; not safe for automatic delivery/update |
| `/Users/juliushe/Desktop/UMA_GitHub_Upload` | non-Git historical upload snapshot; not the M5RMX repository or automatic delivery target |

Live repository remotes are `origin = https://github.com/ShaoJHe-SilkRoad/UMA.git`
and `upstream = https://github.com/ower93/CodexUsageMonitor.git`. `origin/main`
is `469be4d6cf411a89401c2341807a57aef176d852`; the B0 starting HEAD is 43 ahead
and 0 behind. The Founder plan's target string
`https://github.com/ShaoJHe-SilkRoad/CodexUsageMonitor` differs from live origin.
That is a future M5RMX-SYNC-G1 identity gate, not permission to rewrite a remote.

## 8. Lessons and remaining work

1. Accepted Browser Sync should be preserved and completed, not replaced merely
   because another architecture appears cleaner.
2. Exact route and ownership proof matter more than broad page/browser access.
3. Sanitization belongs before the native boundary.
4. Credential existence is not the problem; credential crossing into UMA is
   the problem.
5. Account quota, local activity/cost, freshness, and continuation state are
   distinct semantics and must remain distinct.
6. Apple signing readiness is not notarization acceptance; an external notary
   anomaly must not be reported as product PASS or silently retried.
7. A pre-existing Desktop `UMA_0.12.app` is not the future M5RMX deliverable;
   commit-exact provenance and later delivery gates remain mandatory.
8. The current package helper's 0.11 identity, temporary Safari entitlement,
   final extension onboarding, live supportability, and 0.12 delivery remain
   M5RMX completion work.

B0 performs no production/provider/Apple/Desktop actions. After B0 PASS, the
sole next task is `M5RMX-G1`.
