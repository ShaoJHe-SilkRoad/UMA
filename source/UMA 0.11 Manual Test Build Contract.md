# UMA 0.11 Manual Test Build Contract

## Purpose

Promote the accepted UMA STAB-G1 implementation to a local Founder manual-test
build without changing product behavior.

## Accepted baseline

- Branch: `codex/uma-stability`
- Commit: `7d5ee4e890cb9ec8ef2c381a323253ffa3c3a179`
- Tree: `e78b75cab42beb2dce93316ed091fe7415f29dea`
- Verdict: `UMASTAB-G1 PASS WITH RISKS — STABILITY CLOSED, CLAUDE TYPOGRAPHY FALLBACK USED`
- The accepted native typography fallback remains unchanged.

## Version contract

- Marketing version: `0.11`
- Internal build: `202607270002`
- Bundle identifier: `com.kevinchen.CodexUsageMonitor`
- Minimum macOS: `14.0`
- Architecture: `arm64`
- Manual-test application: `/Users/juliushe/Desktop/UMA_0.11.app`
- Historical application preserved: `/Users/juliushe/Desktop/UMA_0.10.1.app`

## Scope

Only version metadata, commit-exact package configuration, focused contract
tests, and this durable record may change. Codex and WorkBuddy semantics,
typography, glass and border ownership, panel and Assistant geometry, Settings
layout, provider ordering, persistence, and refresh behavior remain the
accepted STAB-G1 implementation.

The package is a local manual-test build. It is not a public release and does
not authorize push, tag, release, notarization, deployment, or publication.
