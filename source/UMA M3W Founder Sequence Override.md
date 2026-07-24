# UMA M3W Founder Sequence Override

Date: 2026-07-24

## Decision

The Founder has changed the M3 execution sequence without rewriting historical
milestone records.

Accepted state:

- M3-B0: closed.
- M3-G1: closed as a completed source-admission goal whose environmental
  decision was `NO-GO — NOT INSTALLED`.
- Claude Code program: deferred, not closed; paid access is not currently
  available.
- M3-G2, M3-G3, M3DBG, M3A, and M3ADBG: held.
- M3W-G1: active as the next source-admission goal.
- WorkBuddy production implementation: unstarted.
- Manus and later providers: paused.

## Current sequence

The current implementation sequence is:

`Codex → WorkBuddy source admission → conditional WorkBuddy implementation → later return to Claude`

If WorkBuddy is admitted and implemented before Claude, the temporary visible
provider order may be:

`Codex → WorkBuddy`

The intended future order after Claude is admitted remains:

`Codex → Claude Code → WorkBuddy`

unless the Founder changes it again.

## Constraints

- M3W-G1 does not update runtime provider order.
- M3W-G1 does not implement or authorize the WorkBuddy connector.
- Claude Code must not be installed, resumed, or re-inspected in this goal.
- The prior M3-G1 records retain their historical result.
- External governing documents remain historically intact pending the
  WorkBuddy admission outcome.
- M3W-G2 must not begin automatically.
