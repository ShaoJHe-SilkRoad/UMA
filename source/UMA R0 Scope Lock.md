# UMA R0 Scope Lock

## Provenance

- Donor repository: `/Users/juliushe/Desktop/CodexUsageMonitor`
- Donor branch: `main`
- Donor commit: `f1da999cf518433d108867d14ea1476678911ebf`
- Reconstruction worktree: `/Users/juliushe/Developer/UMA-Reconstructed`
- Reconstruction branch: `codex/uma-source-reconstruction`
- Historical accepted binary revision: `a8c5ff23fdfb4652481b8b4d2447bcfb2d152cbd` (not recovered)

## Scope

Reconstruct the accepted UMA 0.10.1 behavior as an honest successor of the donor commit:

- shared immutable usage presentation and selected-window policy;
- main-panel and Desktop Assistant parity;
- Assistant lifecycle, Regular and Minimalist layouts, settings, persistence, and accessibility;
- remaining-usage semantics, thresholds, connection/quota independence, and last-valid behavior;
- focused/full tests, renderer evidence, privacy and ownership checks;
- deterministic 0.10.1 package helper and commit-exact local package.

## Preservation

- Donor `main` is read-only.
- `/Users/juliushe/Desktop/UMA_0.10.1.app` is a black-box reference and remains unchanged.
- Governing documents remain external to Git.
- M3, Claude Code, WorkBuddy, Manus, OneDrive, push, release, notarization, deployment, and publication remain out of scope.

## Phase roles

- Primary agent: implementer and integration owner
- `gap_inventory`: shared-presentation implementer
- `architecture_audit`: architecture/privacy examiner and Assistant implementer
- `qa_baseline`: QA runner and package verifier
- Primary agent: final staged-index and package auditor
