# UMA M3W WorkBuddy Source Dossier

Date: 2026-07-24

## Decision

**Admission decision: `NO-GO`.**

Current official documentation proves that WorkBuddy has an account-level
Credits quota and displays subscription, used Credits, and available Credits
on its signed-in personal usage page. It does not document a privacy-safe,
machine-readable WorkBuddy usage source that UMA can consume without browser
or UI automation, private-data access, undocumented IPC, or quota inference.

No WorkBuddy connector, registry entry, transport, UI, package integration, or
compiled test was implemented. M3W-G2 remains unstarted.

## Repository and governing provenance

- Workspace: `/Users/juliushe/Developer/UMA-M3`
- Branch: `codex/uma-m3`
- Starting HEAD: `4d9ddc02c34b3006031f7b6cc7ed058ee7ee02d8`
- Starting tree: `ca760cbb352447040a4cf0d2d512279e8b324e80`
- Starting worktree: clean
- Starting index: empty
- Governing sources:
  - `Scroll.md` 1.3
  - `M3_Plan.md` 1.1
  - `M3_Goal.md` 1.1
  - `UMA_Logic_1.3.md` 1.3
  - `Goal_Mode_2.0.md` 2.0
  - `Dev_Default_2.1.md` 2.1

The Founder sequence override is recorded separately. Claude Code remained
deferred and was not installed or re-inspected.

## Investigation method and accounting

The investigation used:

- current official Tencent Cloud, WorkBuddy, and CodeBuddy documentation;
- public metadata from standard installed-product locations;
- normal-shell resolution of officially documented command names;
- static repository/package inspection needed to assess future feasibility.

It did not launch WorkBuddy or CodeBuddy, inspect login state, use browser or UI
automation, access private application storage, inspect task content, probe a
port or IPC route, capture traffic, read credentials, or invoke a quota source.

| Measure | Result |
|---|---|
| Official usage/status operations | 0 of 10 |
| Live investigation duration | 0 minutes |
| Provider state changes | 0 |
| Login requests | 0 |
| Raw provider payloads created | 0 |
| Sanitized provider payloads staged | 0 |

No owner login action was justified: login cannot turn the documented visual
usage page into an admitted structured protocol.

## Installed product inventory

| Candidate | Result | Public evidence | Classification |
|---|---|---|---|
| `/Applications/WorkBuddy.app` | Present; real path unchanged | Bundle `com.workbuddy.workbuddy`; version/build `5.2.6`; executable `Electron`; URL scheme `workbuddy` | `INSTALLED` |
| WorkBuddy executable | Present | arm64; SHA-256 `7ee8e0ff01f76f6ab4d4b2963815f18fbc4398b9af585db15b1fddab044b1af8` | Public provenance only |
| WorkBuddy signature | Strict deep verification failed | Team ID `FN2V63AD2J`; hardened runtime and stapled ticket present; signature reported invalid | Package trust blocker |
| WorkBuddy public entitlements | Entitlements blob reported invalid | Operating system will ignore the invalid blob | Not usable as capability evidence |
| WorkBuddy public helper/CLI | None identified | No public helper at standard bundle locations; official documentation names no externally invocable WorkBuddy usage CLI | Unavailable |
| `/Applications/CodeBuddy.app` | Absent | Standard application candidate checked | `NOT INSTALLED` |
| `$HOME/Applications/WorkBuddy.app` and `$HOME/Applications/CodeBuddy.app` | Absent | Standard user-local candidates checked | No conflicting installation |
| `codebuddy` / `cbc` | Not resolved | Official CodeBuddy Code command names absent in the normal login shell and standard command locations | `NOT INSTALLED` |
| WorkBuddy login state | Not inspected | Login inspection was unnecessary after protocol rejection | `UNVERIFIED` |

The WorkBuddy bundle is an installed GUI application, but its failed strict
signature verification means it cannot independently provide trusted package
provenance. More importantly, no supported usage interface is documented for
that bundle.

## Official evidence registry

All sources were retrieved on 2026-07-24. “Admit” means admission-grade for the
specific proposition named, not admission of a UMA quota protocol.

| Evidence ID | Official publisher and title | URL | Capability established | Grade |
|---|---|---|---|---|
| WB-E01 | Tencent Cloud — WorkBuddy product page | <https://cloud.tencent.cn/product/workbuddy> | Tencent identifies WorkBuddy as its AI workbench product | Admit: ownership and product identity |
| WB-E02 | Tencent WorkBuddy — Overview | <https://www.workbuddy.cn/docs/workbuddy/Overview> | Official WorkBuddy documentation surface and product scope | Admit: product identity |
| WB-E03 | Tencent WorkBuddy — Service Agreement | <https://www.workbuddy.ai/document/term> | Tencent contracting relationship for the international WorkBuddy service | Admit: international ownership boundary |
| WB-E04 | Tencent WorkBuddy — Release Notes | <https://www.workbuddy.cn/docs/workbuddy/Changelog> | Version `5.2.6` released 2026-07-12; quota and credit messaging exist in the product | Admit: version and feature evidence |
| WB-E05 | Tencent WorkBuddy — View Credit Usage | <https://www.workbuddy.cn/docs/workbuddy/Usage> | Signed-in personal profile shows subscription, available Credits, and used Credits | Admit: product-quota semantics; reject as protocol |
| WB-E06 | Tencent WorkBuddy — Credits | <https://www.workbuddy.cn/docs/workbuddy/Credits> | WorkBuddy requests consume Credits; resource packages can differ by issuance, expiry, and use | Admit: unit and multi-bucket semantics |
| WB-E07 | Tencent WorkBuddy — Plan Management | <https://www.workbuddy.cn/docs/workbuddy/Plan> | Plans and resource packages have account-specific limits, issue/reset behavior, and upgrades | Admit: plan/window semantics |
| WB-E08 | Tencent WorkBuddy — Pricing | <https://www.workbuddy.cn/pricing/> | Published plan tiers and bundled Credit amounts | Admit: marketing definitions only |
| WB-E09 | Tencent WorkBuddy — Model Configuration | <https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/Model> | Custom model providers, including Token Plan, are external to native WorkBuddy Credits | Admit: scope separation |
| WB-E10 | Tencent WorkBuddy — Connectors | <https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/Connector> | MCP/CLI and Skill/CLI connect WorkBuddy to external services; no balance export is defined | Admit: extension capability; reject for quota |
| WB-E11 | Tencent WorkBuddy — Enterprise Agent | <https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/CloudAgent> | Agent/session APIs run tasks and may consume Credits; no account-quota read endpoint is defined | Admit: runtime capability; reject for quota |
| WB-E12 | Tencent CodeBuddy — CLI Reference | <https://www.workbuddy.ai/docs/cli/reference> | Official `codebuddy` and `cbc` commands exist for CodeBuddy Code; no usage/quota/Credits command is documented | Admit for CodeBuddy Code only; reject for WorkBuddy |
| WB-E13 | Tencent CodeBuddy — HTTP API Beta | <https://www.workbuddy.ai/docs/cli/http-api> | CodeBuddy exposes session/activity/cost endpoints; no account-Credits endpoint is listed | Admit for CodeBuddy runtime only; reject for WorkBuddy |
| WB-E14 | Tencent CodeBuddy — IAM | <https://www.workbuddy.ai/docs/cli/iam> | CodeBuddy CLI authentication can use OAuth, API keys, or third-party model credentials | Admit for CodeBuddy only; does not prove WorkBuddy session scope |
| WB-E15 | Tencent Cloud — Configure WorkBuddy with TokenHub | <https://cloud.tencent.cn/document/product/1823/131902> | TokenHub is an optional custom model provider configured by endpoint and API key | Admit: separate-provider relationship |
| WB-E16 | Tencent Cloud — Token Plan Enterprise Operations | <https://cloud.tencent.cn/document/product/1823/130661> | TokenHub packages, keys, units, models, and reset cycles can vary independently | Admit: TokenHub scope semantics |
| WB-E17 | Tencent Cloud — Token Plan Personal FAQ | <https://cloud.tencent.cn/document/product/1823/130076> | Token Plan is a separate subscription with its own keys and monthly quota behavior | Admit: TokenHub independence |
| WB-E18 | Tencent Cloud — Token Plan API | <https://cloud.tencent.com/document/api/1823/132289> | Structured TokenHub control-plane APIs exist | Conditional admit for a separate TokenHub provider only |

The domestic WorkBuddy/CodeBuddy documentation can establish a shared domestic
account or Credits relationship where it says so. That relationship must not
be generalized to international `workbuddy.ai` accounts or used to substitute
CodeBuddy session telemetry for WorkBuddy account quota.

## Candidate source decisions

| Candidate | Authentication and transport | Fields, units, and direction | Scope, reset, and cadence | Version/support and privacy | Decision |
|---|---|---|---|---|---|
| WorkBuddy personal Plan & Usage page | Provider-owned signed-in web UI | Subscription plus visual available and used Credits | Exact WorkBuddy account UI; package/reset details are visual; no machine cadence | Current official documentation; authenticated UI reading would require prohibited browser/UI/OCR/scraping | **REJECT** |
| WorkBuddy CLI or status command | No official command or authentication path documented | No structured WorkBuddy usage fields or units | Product/account/window/reset/cadence absent | No schema or version contract; inventing a command is unsupported | **REJECT** |
| WorkBuddy local IPC or service | No supported service, socket, port, route, or IPC documented | No public fields, units, or direction | Scope/reset/cadence absent | No schema/version contract; probing would be undocumented | **REJECT** |
| WorkBuddy hook, plugin, connector, or status payload | WorkBuddy invokes extensions for external tools/tasks | No native account balance or usage event documented | Task/extension scope, not product quota; no reset/cadence | Supported as an extension feature, not as usage; payloads can include private task/provider data | **REJECT** |
| WorkBuddy structured export | No usage-export flow documented | Document/artifact output, not Credits quota | Content scope, not account quota | No quota format or version; private content risk | **REJECT** |
| WorkBuddy webhook or notification | Provider task messaging/agent integration | Task messages/results, not balance fields | Task scope; no quota reset/cadence | Supported task feature, wrong scope and content-bearing | **REJECT** |
| WorkBuddy local metadata/cache | Would inherit an undocumented installed-app session | Unknown/private schema | Scope/reset/cadence unproven | Unsupported and update-fragile; private storage and credentials prohibited | **REJECT** |
| CodeBuddy Code CLI/status line/ACP/HTTP API | Separate CodeBuddy OAuth/API-key/runtime session over CLI/stdin/local HTTP/ACP | Session activity, tokens, cost, or incremental Credits consumption; no aggregate WorkBuddy balance | CodeBuddy runtime/session, not proven WorkBuddy account pool; event/session cadence | Official CodeBuddy contracts; can expose session/workspace/log data; CLI absent locally | **REJECT** |
| Official WorkBuddy account usage API | No public read-only endpoint or authentication contract found | No documented WorkBuddy Credits payload | Exact target scope would be suitable, but reset/cadence are undefined | No schema, source version, failure, or privacy contract | **REJECT — NOT DOCUMENTED** |
| TokenHub / Token Plan API | Separate Tencent Cloud authorization over public control-plane API | Package/key/model token or Credit quota, usage, and balance | Token Plan package/key/model scope with separate monthly or package reset; not native WorkBuddy Credits | Official structured TokenHub API; some responses include identifiers or key material | **REJECT FOR WORKBUDDY** |

Required TokenHub result:

**`TOKENHUB SCOPE UNPROVEN — REJECT`**

TokenHub can be configured as a custom provider used by WorkBuddy, but its
balance belongs to a Token Plan package, API key, model, and Tencent Cloud
scope. Official documentation does not prove that this is the same balance as
native WorkBuddy Credits, nor that one user cannot hold divergent WorkBuddy and
TokenHub balances. TokenHub may be evaluated later only as a separate provider
under separate authority.

## Field and semantic classification

| Requested field | Official meaning and scope | Current evidence | Final classification |
|---|---|---|---|
| Provider/product | WorkBuddy | Official ownership and installed bundle agree | Present and supported as static identity only |
| Installed version | Desktop bundle version `5.2.6` | Observed from public `Info.plist`; signature verification fails | Present, but package provenance malformed |
| Plan name/tier | WorkBuddy account subscription plan | Named by the UI documentation; account value not observed | Documented but unobserved |
| Total quota | Credits issued by one scoped plan/resource package | Semantics documented; account value not observed | Documented but unobserved |
| Used quota | Credits consumed within one scoped package/window | Semantics documented; account value not observed | Documented but unobserved |
| Remaining quota | Available Credits within one scoped package | Semantics documented; account value not observed | Documented but unobserved |
| Remaining percentage | No stable direct structured WorkBuddy field found | Not observed; no valid pair for derivation | Absent |
| Credit balance | Native WorkBuddy Credits within a specific package | Semantics documented; account value not observed | Documented but unobserved |
| Token balance | TokenHub or third-party model-provider metric | Separate product/provider scope | Ambiguous scope — reject |
| Request balance | No equivalence to WorkBuddy Credits documented | Not observed | Undocumented — reject |
| Reset timestamp | Subscription/resource-package expiry or renewal event | General semantics only; account event not observed | Optional/account-dependent and unobserved |
| Reset interval | Monthly issuance or package-specific expiry | General semantics only | Documented but unobserved |
| Quota window | One plan/resource-package validity window | Multiple possible buckets; exact account window not observed | Documented but unobserved |
| Per-model quota | No native WorkBuddy per-model quota contract found | Different models may consume Credits at different rates | Undocumented — reject |
| TokenHub quota | Token Plan package/key/model balance | Officially documented for TokenHub, not native WorkBuddy | Ambiguous scope — reject |
| Current-session usage | CodeBuddy runtime/session activity | Official for the separate CodeBuddy surface only | Wrong product scope — reject |
| Task count | Activity or plan feature, not a quota pair | No official equivalence to remaining Credits | Ambiguous scope — reject |
| Cost | CodeBuddy session/model-provider cost | Not native WorkBuddy product quota | Wrong product scope — reject |
| Last-update timestamp | No structured WorkBuddy source timestamp documented | Not observed | Absent |
| Connection/account state | Desktop login not inspected | No admitted source justified inspection | Unverified |

“Missing” must remain unavailable, never zero. “Exhausted” is valid only when
an official scope-matched source reports zero remaining. “Unlimited” is valid
only through an explicit official marker.

## Deterministic normalization decision

UMA could calculate remaining percentage only from one official,
scope-matched pair:

`100 × remaining / total`

or:

`100 × (1 − used / limit)`.

Both values must share provider, product/account scope, plan, quota identifier,
unit, window, reset boundary, and source version. WorkBuddy can issue multiple
base, bonus, or add-on Credit buckets with different expiries. Values must not
be summed or mixed unless an official source defines that aggregate.

No admitted source supplies a valid pair. Remaining-percentage normalization is
therefore **not feasible**. UMA must not infer quota from task count, token
estimates, price, model cost, duration, or historical usage.

## Privacy contract

If an official structured source becomes available, allow only:

- constant nonidentifying provider ID and formal product name;
- plan tier and exact quota metric/unit;
- total, used, remaining, or official remaining percentage;
- exact quota/reset window and reset timestamp;
- per-model quota only when explicitly scoped;
- safe source version, receipt/freshness timestamp, and bounded source state.

Reject and discard:

- email, account, organization, billing, phone, device, or stable identity;
- credentials, tokens, cookies, QR/code material, Keychain, or auth databases;
- prompts, responses, tasks, projects, conversations, source code, or private
  filesystem paths;
- private databases, caches, process memory, network capture, raw responses,
  logs, rejected subtrees, or response excerpts;
- browser/UI automation, OCR, screenshots, and visible-text scraping;
- undocumented commands, IPC, ports, sockets, routes, or APIs;
- quota inferred from activity, estimates, prices, costs, or another product.

Raw input may exist only transiently in bounded process memory after admission.
If identity-bearing and allowed fields cannot be separated safely, reject the
whole response.

## Authentication, setup, and restoration boundary

| Question | Current answer |
|---|---|
| Does a WorkBuddy CLI inherit the installed app login? | Not documented; no official WorkBuddy usage CLI exists |
| Does a supported local service reuse a provider-owned session? | Not documented |
| Does an official WorkBuddy usage API require user credentials? | No such API/authentication contract was found |
| Can UMA use the installed session without reading secrets? | Unproven; private session storage and undocumented IPC are prohibited |
| Does logout/account change affect the source? | Expected to invalidate quota, but no structured source behavior is documented |
| Can account identity be excluded? | Unproven because no source/schema is admitted |
| Was setup performed? | No |
| Was restoration required? | No; application, login, configuration, and provider state were unchanged |

TokenHub requires separate Tencent Cloud authorization and therefore cannot
inherit WorkBuddy identity by assumption. CodeBuddy CLI authentication likewise
does not prove the native WorkBuddy account quota scope.

## Failure, recovery, and refresh requirements

A future admitted source must independently represent:

- not installed;
- logged out or account changed;
- source unavailable or permission denied;
- malformed response or unknown source version;
- missing optional field;
- exhausted, unlimited, and stale states;
- app closed, supported helper stopped, or network unavailable.

Last-valid quota may be retained only with explicit stale state and age.
Logout/account transition must invalidate prior quota to prevent cross-account
leakage without retaining an account identifier. Malformed or unknown-version
data must not overwrite last-valid data. Recovery must occur on the next
bounded scheduled or manual read, without aggressive retry, render-driven
polling, or reads multiplied by multiple UMA surfaces.

These are future admission conditions, not implemented behavior.

## Package and runtime feasibility

Current package feasibility is **not credible**:

1. no official structured WorkBuddy usage interface is admitted;
2. no installed public WorkBuddy usage helper exists;
3. the separate CodeBuddy CLI is absent and has no aggregate WorkBuddy quota
   contract;
4. depending on private WorkBuddy storage or session state is prohibited and
   fragile;
5. the installed WorkBuddy bundle fails strict deep signature verification;
6. UMA cannot prove authentication, freshness, recovery, or exact account
   scope without an official interface.

A packaged UMA app's current signature or sandbox model cannot convert a
private WorkBuddy session into a supported source. No global privacy permission
is justified. Launch-at-login does not help because there is no source to
read. WorkBuddy updates could change private internals and the installed bundle
already fails strict signature verification, so private coupling would be both
unsupported and package-fragile.

A later official API would need documented read-only authentication that UMA
can invoke without reading or retaining credentials. A later official CLI
would need installed-version compatibility, stable schema/versioning,
privacy-safe output, bounded latency, and deterministic recovery.

## Claim-to-evidence map

| Claim ID | Claim | Supporting evidence |
|---|---|---|
| WB-C01 | Tencent owns and publishes WorkBuddy | WB-E01, WB-E02, WB-E03 |
| WB-C02 | WorkBuddy uses Credits and exposes account usage visually | WB-E05, WB-E06, WB-E07 |
| WB-C03 | No reviewed official WorkBuddy machine-readable quota protocol is documented | Bounded official inventory WB-E02 through WB-E14 |
| WB-C04 | CodeBuddy runtime telemetry is not an aggregate WorkBuddy quota source | WB-E12, WB-E13, WB-E14 |
| WB-C05 | TokenHub is an optional separate custom-model provider with independently scoped quota | WB-E09, WB-E15, WB-E16, WB-E17, WB-E18 |
| WB-C06 | Normalization cannot be performed safely from current evidence | WB-E05, WB-E06, WB-E07 and field matrix |
| WB-C07 | Installed WorkBuddy exists but its package trust check fails | Public bundle inventory recorded above |
| WB-C08 | A production WorkBuddy connector is not currently feasible within the privacy contract | WB-C03 through WB-C07 |

Negative protocol findings are bounded to the official documentation reviewed
on 2026-07-24. An undocumented internal mechanism is intentionally not an
admission candidate.

## Re-entry condition

Reconsider M3W-G2 only after Tencent publishes or directly authorizes a
read-only, machine-readable WorkBuddy usage source that:

1. is explicitly scoped to native WorkBuddy Credits and the current WorkBuddy
   account/subscription;
2. documents fields, units, windows, reset semantics, versioning, freshness,
   and failure behavior;
3. can be used without UI scraping, private storage, undocumented IPC, or
   credential access;
4. supports safe allowlist-only sanitation and bounded reversible reads;
5. provides a scope-matched percentage or total/used/remaining pair;
6. passes installed-package, privacy, recovery, and independent QA gates.

Until then the admission verdict remains **`NO-GO`**.

## Completion Lock

No WorkBuddy implementation is authorized by this dossier. Do not begin
M3W-G2, resume Claude Code, inspect Manus or another provider, access OneDrive,
or push, tag, release, notarize, deploy, or publish.
