# UMA M6 Closeout and Cursor Handoff

**Milestone:** M6 — Google Antigravity Support
**Status:** `M6 CLOSED — GOOGLE ANTIGRAVITY SUPPORTED — M7 SOURCE ADMISSION NEXT`
**Accepted code commit:** `e72bd92c476e05152b95ccb9ba95c22be78efef1`
**Accepted tree:** `c1358c5b4176383021e87605afc45ca3e347ab89`
**Only next task:** `M7 — Cursor Source Admission`

This additive current-truth record closes M6. It does not rewrite retained
historical evidence or checksum-locked material, start Cursor, alter a provider
mechanism, install an application or perform a remote delivery action.

## 1. Current provider matrix

| Order | Provider | Product status | Accepted source | Main Panel | Desktop Assistant |
|---:|---|---|---|---|---|
| 1 | Codex | `SUPPORTED` | Existing local app-server mechanism | Supported | Supported |
| 2 | Claude Code | `SUPPORTED` | Browser Sync quota plus separate local activity/cost estimate | Supported | Supported |
| 3 | WorkBuddy | `SUPPORTED` | Provider-owned account-web exact Credits mechanism | Supported | Supported |
| 4 | Google Antigravity | `SUPPORTED — LIVE ACCEPTED` | Official provider-owned structured read-only CLI | Supported | Supported |
| 5 | Cursor | `NOT YET SUPPORTED` | No source admitted | Hidden | Hidden |

Stable provider IDs remain `codex.local`, `claude.browserSync`,
`workbuddy.accountWebCredits` and `antigravity.cli`. Existing Codex, Claude Code
and WorkBuddy mechanisms were not changed by this closeout.

## 2. Antigravity source and quota contract

The M6-admitted current-device executable was
`/Users/juliushe/.local/bin/agy`, version `1.1.11`. Production resolves the
exact current-user location `$HOME/.local/bin/agy`, verifies the admitted
capability and executable identity, and invokes it directly without a shell:

```text
agy --output-format json -p /usage
```

The strict quota projection is `command.data.groups[].buckets[]`.
`bucket.id` is the stable provider-owned identity. Each quota pool remains
independent; UMA does not sum, split or infer model-pool identity. The value is
`remaining_fraction × 100` exactly once and always means `REMAINING`; it is not
double-inverted. `reset_time` is optional, bucket-scoped ISO-8601 data. Missing
or malformed fields fail closed rather than becoming zero.

Antigravity Credits are not admitted: `CREDITS DEFER`. `/credits` is not a
product source. Live evidence proved only an existing provider-owned
authenticated session producing the admitted schema; it did not classify the
account as individual or enterprise. Enterprise and every other unclassified
account mode remain unqualified and must fail closed.

## 3. Authentication and privacy

Authentication remains provider-controlled through the existing Antigravity
session. UMA credential access is `NONE`. M6 uses no API key, copied OAuth
token, Keychain credential read, cookie or browser-profile import, manual
quota, private Google endpoint, prompt or provider task. Refresh requires no
intentional provider work, and no attributable quota consumption was observed
within provider granularity.

Only normalized quota fields enter product state. Raw provider payload,
stdout/stderr, account identity, exact live quota values, bucket labels/IDs and
reset timestamps are not retained in closeout evidence.

## 4. Refresh ownership

Antigravity owns one scheduler and at most one in-flight read/process. Normal
cadence is five minutes after the preceding cycle completes, with the admitted
minimum-interval contract preserved. Manual and scheduled reads coalesce.
There is no catch-up burst, retry storm or rendering-owned provider read.
Authentication, trust, version, schema and identity uncertainty fail closed.

Codex retains its local app-server lifecycle. Claude Code retains Browser Sync
quota plus separate local activity/cost estimation. WorkBuddy retains its
provider-owned account-web exact Credits mechanism and existing one-minute
cadence.

## 5. Shared presentation and density

Main Panel and Desktop Assistant consume the same immutable shared provider
presentation. The Assistant owns no CLI process, decoder, scheduler, cache,
observation, quota selection or Maximum Decrement calculation.

Four visible providers permit Regular mode. Automatic forced Minimalist begins
only when `visible provider count > 4`. Cursor, if separately admitted as
provider five, must verify the first real automatic four-to-five transition;
M6-CLOSE does not implement it.

## 6. Final M6 evidence

| Evidence | Accepted result |
|---|---|
| Code commit | `e72bd92c476e05152b95ccb9ba95c22be78efef1` |
| Tree | `c1358c5b4176383021e87605afc45ca3e347ab89` |
| Local package | `$HOME/Developer/UMA-Packages/uma-m6adbg-final-e72bd92c476e05152b95ccb9ba95c22be78efef1/UMA.app` |
| Source archive SHA-256 | `18046642208106125d2a69120bd2a88931c5af6d7a4dd55620fa9306d3828e97` |
| Bundle ID | `com.silkrd.uma` |
| Version / build | `0.11 / 202608090106` |
| Architecture | `arm64` |
| Signature | Strict deep verification PASS; local ad-hoc, no Team ID |
| Accepted M6ADBG predecessor full deterministic suite | `588/588 PASS` |
| M6-CLOSE focused contract | `6/6 PASS` |
| M6-CLOSE affected M6 regression | `109/109 PASS` across 11 suites |
| Builds | Debug PASS; Release PASS; strict-concurrency Release with warnings-as-errors PASS |
| Combined acceptance | Four-provider matrix, Main/Assistant parity, refresh ownership, Light/Dark, EN/zh-CN, Regular/Minimalist, lifecycle, resource soak, privacy and safe process inspection PASS |
| Package acceptance | Commit-exact archive, system dependencies, privacy/fixture/secret allowlists and strict deep signature PASS |
| Provider operations in M6-CLOSE | `/usage` 0; `/credits` 0; prompts/tasks 0; intentional spend 0 |

The package is local verification evidence. It was not installed over the
protected Desktop UMA, pushed, released, notarized, deployed or publicly
distributed. The protected Desktop application remained untouched.

## 7. M5 freeze and distribution status

The accepted M5 frozen baseline remains
`c6245f9cc745b3d45f53e115843b3152e84e8c46`; its 52-file protected set is
unchanged. Bundle-identifier and future signing-readiness groundwork exists.
Current repository and package evidence does not prove an active Developer ID
identity, notarization, public distribution or acceptance of the Safari
temporary file-access entitlement. M5 remains frozen; no M5 work resumes here.

## 8. Retained history and standing QA lesson

`source/reference/**`, M5 checksum-locked files and accepted M6 plan, goal,
admission, connector, live, debug, Assistant and combined-closeout evidence are
retained. Their historical status statements are evidence of their own stage;
this record is the additive current M6 truth.

The closed M6 privacy incident establishes a standing process-inspection rule:
use only exact executable path/name, PID, required parent/child relation,
process count, bounded resource counters and exit/absence state. Broad process
command lines, unrelated argv, environment dumps and provider session metadata
are prohibited. If normalized evidence is insufficient, fail closed.

## 9. Cursor handoff

The sole next program is `M7 — Cursor Source Admission`. It begins with a
source dossier, not connector implementation. M7 must prefer an official
structured/provider-owned source and require source admission before provider
visibility. It must not default to a user-entered API key, copied OAuth/access/
refresh token, Keychain credential read, browser cookie/profile import, private
or internal endpoint without a new explicit Founder decision, manual quota, or
an activity/token/cost estimate recast as account remaining quota.

Cursor feasibility is not assumed. No Cursor runtime, live credential
investigation, connector, card or package work occurred in M6-CLOSE.

## 10. Remaining accepted limitations

- Antigravity Credits remain deferred.
- Enterprise-account coverage is unqualified.
- Antigravity CLI identity/version/schema drift must continue to fail closed.
- CLI trust retains the Founder-accepted official manifest/archive/hash basis;
  local Developer ID/Gatekeeper validation was not the admission basis.
- Distribution signing and notarization remain unproven.
- Physical VoiceOver remained deferred by the accepted M6ADBG scope.

**Final decision:** `M6 CLOSED — GOOGLE ANTIGRAVITY SUPPORTED — M7 SOURCE ADMISSION NEXT`
