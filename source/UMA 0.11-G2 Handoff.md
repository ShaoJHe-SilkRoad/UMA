# UMA 0.11-G2 Handoff

Date: 2026-07-27

## Starting condition

Goal 2 must start from the one accepted local commit whose subject is:

`feat(uma): add compact multi-agent monitor architecture`

The exact commit and tree are recorded in the G1 final report. Resolve both
from the clean G1 worktree before creating the G2 branch:

```bash
git -C /Users/juliushe/Developer/UMA-0.11-MultiAgent rev-parse HEAD
git -C /Users/juliushe/Developer/UMA-0.11-MultiAgent rev-parse HEAD^{tree}
```

This indirection is deliberate: the tracked handoff cannot contain the hash of
the commit that contains itself while also honoring G1's one-commit rule.

## Completed G1 architecture

- Neutral UMA header and global controls.
- One equal compact collapsed card shell for every admitted provider.
- Provider-ID-keyed independent Details plus Show All / Hide All.
- Explicit Show All mode remains active when a newly admitted provider appears.
- Provider-specific Agent Settings routes from cards and the Settings Agents
  list.
- Safe setup-required guidance for registered authentication-only providers,
  with all runtime/setup state suppressed while monitoring is disabled.
- Codex rate limits, tasks, cost, and reset data owned by Codex Details.
- WorkBuddy exact account Credits and safe provenance owned by WorkBuddy
  Details.
- One shared primary selected-window result across main panel, status item,
  Desktop Assistant, Tooltip, and VoiceOver.
- Seven-day preference over an unlimited/unavailable/otherwise-equal
  five-hour value without removing valid five-hour detail data.
- Versioned, bounded, provider-neutral preference persistence with inactive
  known-provider retention and no secret fields.
- First-ever manual Agent Search followed by user-controlled later-launch Auto
  Search, using only registered providers and no background discovery timer.

## Protected functional contracts

Goal 2 must not change:

- provider admission, stable order, or current-read honesty;
- Codex app-server protocol, consent, child ownership, or recovery;
- WorkBuddy Account Web Sync, all-pool Decimal aggregation, exact/Minimalist
  formatting, one-minute Auto Refresh, WebKit isolation, or disconnect scope;
- per-Agent preference schema/migration without a separately versioned
  compatibility plan;
- Auto Search first-manual and launch-count rules;
- selected-window decrement/reset/refill semantics;
- main-panel/Desktop Assistant provider membership parity;
- one host, one status item, one registry, one store, one shared presentation
  policy, one Assistant panel, and existing resource bounds.

## Goal 2 visual ownership

G2 owns only the final visual-system pass, including:

- compact-card spacing and typography polish;
- final glass/material/color treatment;
- double-border and contour audit;
- final secondary five-hour visual polish;
- dense three-to-eight-provider layout review;
- Light/Dark, Reduce Transparency, Increase Contrast, larger text, EN/zh-CN,
  keyboard, VoiceOver, clipping, and repeated-transition evidence.

It must preserve the G1 hierarchy, settings/discovery contracts, source
privacy, and selection behavior.

## Completion boundary

G1 does not authorize G2 implementation, Desktop installation, push, tag,
release, notarization, deployment, or publication.
