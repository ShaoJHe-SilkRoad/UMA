# UMA 0.11-DBG Handoff

Date: 2026-07-27

## Accepted G2 result

G2 delivers compact equal provider cards, one contour owner per component,
medium public-macOS glass, header-only Settings backing, attached expanded
details, a de-emphasized nonselected or unlimited Codex five-hour row,
fail-closed zero-priced Token Cost handling plus large-value layout protection,
centralized serif-led labels, tabular exact values, native CJK fallback,
natural Settings sizing, and unchanged Assistant geometry.

The tracked handoff cannot contain the SHA of the one commit that contains
itself. Resolve the exact final commit and tree from the clean G2 worktree:

```bash
git -C /Users/juliushe/Developer/UMA-0.11-MultiAgent rev-parse HEAD
git -C /Users/juliushe/Developer/UMA-0.11-MultiAgent rev-parse HEAD^{tree}
```

The accepted predecessor is:

- G1 commit: `4b78d38d194a86db4dee7e4bbe35009a2224ff60`
- G1 tree: `6043ef12aa63f2bfa8967a06e80085c4c1245cae`

The G2 commit subject must be:

`style(uma): compact multi-agent glass and typography`

## Font decision

Exact `Anthropic Serif` is unavailable through any registered, licensed,
package-safe source. G2 uses the public macOS system-serif design and its native
CJK cascade. Exact numeric values remain system tabular sans; technical text
uses the system monospaced design. No font asset was copied or packaged, and
UMA has no Claude application dependency.

## Frozen visual contracts

- Panel width remains 370 pt and maximum height remains 776 pt.
- Natural minimum height is 125 pt.
- Collapsed provider cards are equal at 74 pt with 8 pt inter-card spacing.
- Settings has one scroll owner and no provider-material tree behind it.
- Production outer contour belongs to the native material host; renderer
  fallback contour is inset.
- Expanded provider content has no second complete card shell.
- Regular Assistant remains 210 by 60 pt.
- Minimalist Assistant remains 58.333333 by 30 pt, with zero selected-window
  width and 13 pt tabular value typography.
- Provider behavior, selected-window policy, WorkBuddy all-pool calculation,
  Auto Refresh, Auto Search, settings persistence, and value formatting remain
  unchanged.

## Verification baseline

- Focused UMA 0.11 matrix: 39/39 PASS across 4 suites.
- Full suite: 304/304 PASS across 37 suites.
- Debug, Release, and strict-concurrency warnings-as-errors Release: PASS.
- The deterministic matrix contains 61 images across provider/state,
  appearance, language, Settings, and Assistant variants.
- Physical synthetic review proves bounded disclosure/Settings scrolling,
  native material hosting, transient keyboard focus, visible VoiceOver focus,
  and exact restoration of both accessibility features to off.
- The review renderer creates its default output parent, catches every
  startup/render failure at its nonthrowing async entry point, emits only a
  bounded diagnostic, and keeps interactive review windows in `NSApp.run()`.

## Required DBG matrix

DBG must revalidate the commit-exact package over live production states:
provider admission/removal, long localized copy, keyboard and VoiceOver focus,
system Light/Dark changes, Reduce Transparency, Increase Contrast, Reduce
Motion, larger text, dense scrolling, repeated Show All/Hide All and
Details/Settings transitions, stale/recovery behavior, Assistant placement and
resource bounds. DBG must not infer live provider correctness from synthetic
visual evidence.

## Completion boundary

G2 does not authorize DBG implementation, Desktop replacement, installation,
push, tag, release, notarization, deployment, or publication.
