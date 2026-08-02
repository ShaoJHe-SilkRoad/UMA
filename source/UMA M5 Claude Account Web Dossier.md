# UMA M5 Claude Account Web Dossier

> **Historical NO-GO evidence.** The embedded WKWebView/account-web route stays
> rejected. M5-BROWSER-G1 is a distinct system-browser WebExtension design and
> does not revive, reuse, or authorize embedded login or browser-session import.

Date: 2026-07-31
Goal: M5-WEB-G1
Source class evaluated: `isolatedAccountWeb`

## Decision

**NO-GO — SAFE ACCOUNT-WEB AUTHENTICATION NOT AVAILABLE**

The official Claude sign-in page loaded in one task-owned, nonpersistent
`WKWebView`. The Human-controlled Google sign-in path then failed because the
identity provider rejected the embedded user agent. The Founder accepted this
as an embedded-auth compatibility failure and prohibited retries, alternate
verification paths, or bypasses. No authenticated Usage page or live usage
value was observed.

Fixture-only parser and route checks cannot replace the required authenticated
observation. The account-web source is therefore not admitted.

## Official documentation findings

- Claude's official web sign-in origin is `https://claude.ai`.
- The official Claude Help Center documents Google and email sign-in for the
  Claude web application.
- Claude plan limits are described as a five-hour current session and weekly
  limits. The official Usage settings page is the user-facing source for used
  amounts and reset information.
- Anthropic's third-party-tool guidance prefers API-key or supported-cloud
  authentication. It does not publish an OAuth client, callback URI, scope, or
  contract that grants a third-party macOS application access to the Claude
  account Usage page.
- The exact authenticated Usage route was not observed and is not admitted.

References:

- <https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account>
- <https://support.claude.com/en/articles/9797557-usage-limit-best-practices>
- <https://support.claude.com/en/articles/8325606-what-is-the-pro-plan>

## Prototype identity and lifecycle

The isolated research bundle used identifier
`com.kevinchen.uma.m5web.research`. It was an arm64, ad-hoc-signed local
prototype with no entitlements and no App Sandbox. It was never added to the
product, packaged, or installed.

The prototype used:

- one `WKWebView`;
- `WKWebsiteDataStore.nonPersistent()`;
- public WebKit APIs;
- HTTPS top-level navigation;
- exact top-level host checks for the provider and provider-required Google
  sign-in hosts;
- a task-owned root at `/private/tmp/uma-m5-web-g1-prototype` with mode `0700`;
- a bounded sanitized result file with mode `0600`.

The Founder security steer ended the login attempt. `Disconnect & Clear`
invalidated both timers, stopped navigation, removed every website-data type
from the nonpersistent store, verified zero retained data records, tore down
the WebView, closed the window, and terminated the process. The exact
task-owned root was then deleted. Bundle-specific Containers, WebKit, Caches,
HTTPStorages, Saved Application State, Preferences, Cookies, and crash-report
paths were absent after cleanup.

No provider screenshot was saved or retained. No account identity value was
copied into Git, documentation, tests, logs, screenshots, or temporary
evidence.

## Source-level security audit

| Boundary | Finding |
|---|---|
| App Sandbox | Disabled. The ad-hoc prototype had no `com.apple.security.app-sandbox` entitlement. |
| Entitlements | None. No network, file, Keychain group, Apple Events, Accessibility, Screen Recording, camera, microphone, Bluetooth, or location entitlement was present. |
| Filesystem capability | Because the host was unsandboxed, native code had ambient user-process filesystem capability. The reviewed source accessed only its exact task-owned temporary root. |
| Temporary access | Three exact task-owned paths were used inside the root: source/build artifacts, a bounded result, and a clear signal. All were deleted. |
| User-selected files | No open panel, security-scoped bookmark, or user-selected-file API. |
| Desktop/Documents/Downloads | No source reference or access. |
| Network | The WebView used outbound HTTPS. No listener or server was created. With App Sandbox disabled, network entitlement declarations did not constrain the process. |
| Keychain | No Keychain API, access group, credential read, or credential write. |
| Apple Events and privacy-sensitive devices | No API use, entitlement, or Info.plist usage-description key. |
| Website data store | Nonpersistent only. No shared browser cookie store or session import. |
| Cookies and web storage | No cookie, `localStorage`, or `sessionStorage` read/export. All website-data types were cleared; retained record count was zero. |
| Script message handlers | None registered. |
| JavaScript evaluation | Present. A two-second timer called `evaluateJavaScript`. This is a security defect for the proposed privacy contract. |
| Login-page DOM | The script ran before a verified Usage route and enumerated bounded heading, label, span, div, and paragraph `textContent` to classify login/usage landmarks. It did not query input values or credential fields, but the generic JavaScript capability could have done so. |
| Origin and navigation | Main-frame navigation required HTTPS and an exact host allowlist. Top-level `file://`, custom schemes, HTTP, and unrelated hosts were rejected. Subframes were not independently origin-locked. |
| File schemes | Rejected for top-level navigation; no local file URL was loaded. |
| Uploads/downloads | No upload, file-picker, navigation-download, or download-delegate handler. |
| Request/response interception | None. No URL protocol, proxy, response body, header, or private API inspection. |
| Console/WebKit logging | No console message handler or WebKit debug logging. Only fixed local status strings and the bounded classification object existed. |
| Diagnostics | No task-owned crash report was present. No raw HTML, DOM, URL query, identity, credential, or live value was written. |

## Required security verdicts

### A. Provider page route to local files

**No route was present in the reviewed design.** Top-level `file://` and custom
schemes were rejected, and there was no upload/download handler. This is a
source-level result, not a claim that an unsandboxed process has no ambient
filesystem capability.

### B. Prototype access outside task-owned paths

**Capability: yes. Observed source behavior: no.** App Sandbox was disabled,
so native prototype code was not technically confined to the task root. The
reviewed code used only the exact task-owned temporary paths. This capability
gap is unacceptable for production admission.

### C. Login-page DOM or credential-field inspection

**Login-page DOM: yes. Credential values: no.** The periodic JavaScript read
bounded text landmarks on the login page. It did not select input elements or
read credential values. However, `evaluateJavaScript` provided a technical
ability to inspect them. The privacy boundary therefore fails even without a
proven credential exposure.

### D. Persistence

**No cookies, storage, credentials, identity, raw page data, or screenshot was
persisted.** The only file was a bounded boolean/classification result. Any
identity that may have been transiently rendered by the provider was not
copied or retained.

### E. Disconnect & Clear

**PASS for the terminated prototype.** The nonpersistent store returned zero
records after deletion, exact bundle-owned persistence locations were absent,
the process exited, and the exact task-owned root was removed.

### F. M5-WEB privacy contract

**FAIL.** The prototype avoided persistence and credential extraction, but it
was unsandboxed and ran DOM inspection before an authenticated official Usage
route had been established. These are admission failures, so no production
account-web implementation is permitted.

## ASWebAuthenticationSession capability decision

Apple documents `ASWebAuthenticationSession` as a system-mediated browser
authentication flow that requires a provider authentication URL and a known
callback. On macOS it uses the default browser or Safari. The provider returns
a callback URL to the requesting application. An ephemeral browser session can
be requested, but this does not create a provider contract or Usage-page
authorization.

No official Claude documentation was found that supplies UMA with an OAuth
client, supported callback, scope, token-handling contract, or official method
to read account Usage through this mechanism. Implementing it would therefore
require inventing or replaying a private flow. It was not implemented.

Apple reference:
<https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession>

## Metric capability table

| Field | Result |
|---|---|
| Five-hour used percentage | Not observed; unavailable |
| Five-hour reset | Not observed; unavailable |
| Five-hour remaining conversion | Not performed on live data |
| Weekly all-model used percentage | Not observed; unavailable |
| Weekly all-model reset | Not observed; unavailable |
| Optional model-specific weekly scope | Not observed; unavailable |
| Exact authenticated Usage route | Not observed; unverified |
| Live account-web source | Rejected |

The semantic rule remains `remainingPercent = 100 - usedPercentage`, applied
exactly once only to a finite provider value in `0...100`. It was exercised
only with synthetic fixtures in this Goal.

## Completion boundary

- No production runtime was modified.
- No persistent Claude login was activated.
- No browser session was imported or copied.
- No commit, package, installation, push, or release was created.
- The preserved M5-LIVE-R1 product diff remains unstaged.
- After NO-GO, the only next task is a Founder decision about retaining the
  optional terminal CLI integration, marking Claude Desktop usage unsupported,
  or closing M5 without Claude production support.
