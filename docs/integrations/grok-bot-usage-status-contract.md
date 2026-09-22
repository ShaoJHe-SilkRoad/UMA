# Grok Bot → UMA local usage meter contract

**Status:** Integration gate for UMA (Codex-shaped path)  
**Audience:** Grok Bot / xAI (or Sand host) owners who can emit a local file  
**UMA repo:** ShaoJHe-SilkRoad/UMA  
**Date:** 2026-09-22  

## Why this exists

UMA’s best-working provider path is **Codex-shaped**:
1. Official app installed on device  
2. Existing signed-in session (UMA does not collect passwords/tokens)  
3. A **structured local** usage read (app-server RPC and/or an on-device meter file)  
4. Fail closed if the read is missing, stale, or malformed  

Grok Bot today exposes presence (`desktop-status.json` → `signedIn`) and cloud usage (`GetSandUsageStatus`), but **no on-device usage meter**. Until a local meter (or local usage RPC) exists, UMA will **not** show Grok on the main usage panel.

## Requested artifact

Whenever Grok Bot learns account usage (same moment it would refresh UI from `GetSandUsageStatus` / equivalent), write or atomically replace:

```text
~/Library/Application Support/Grok Bot/usage-status.json
```

Fallback also acceptable:

```text
~/.grokbot/usage-status.json
```

UMA will prefer Application Support, then `~/.grokbot`.

### Schema (v1)

```json
{
  "schemaVersion": 1,
  "capturedAt": "2026-09-22T15:04:05.000Z",
  "signedIn": true,
  "planLabel": "Grok Pro",
  "usagePercentUsed": 37.5,
  "remainingPercent": 62.5,
  "nextResetAt": "2026-09-29T00:00:00.000Z",
  "isUnlimited": false,
  "isTeamSeat": false,
  "onDemandEnabled": false,
  "windows": [
    {
      "id": "primary",
      "label": "Primary",
      "usedPercent": 37.5,
      "remainingPercent": 62.5,
      "resetsAt": "2026-09-29T00:00:00.000Z",
      "unlimited": false
    }
  ],
  "source": "GetSandUsageStatus"
}
```

### Field rules

| Field | Required | Notes |
|---|---|---|
| `schemaVersion` | yes | Integer `1` for this contract |
| `capturedAt` | yes | ISO-8601 UTC; UMA rejects samples older than **20 minutes** (same ballpark as Claude Desktop plan cache) |
| `signedIn` | yes | If `false`, UMA hides Grok (not authenticated) |
| `planLabel` | no | Display only; no account emails/ids |
| `usagePercentUsed` | one of used/remaining | 0…100 finite number |
| `remainingPercent` | one of used/remaining | 0…100; if both set, they must sum to ~100 (±0.6) |
| `nextResetAt` | no | ISO-8601 UTC |
| `isUnlimited` | no | If true, remaining semantics are unlimited grant |
| `windows` | no | Optional multi-window detail; same percent rules per window |
| `source` | no | Provenance label only |

### Privacy allowlist (must)

**Allowed:** plan label, percentages, reset timestamps, boolean flags, schema/source metadata.  

**Forbidden in this file:** access tokens, refresh tokens, cookies, account email, user id, raw API payloads, conversation content, gateway credentials.

Write with user-only permissions (`0600`). Prefer write-temp + rename for atomic replace.

### Refresh expectations

- Update on sign-in, on usage UI refresh, and when backend usage status changes.  
- If signed out, write `signedIn: false` (or delete the file).  
- Do not leave a stale signed-in meter after logout.

## Optional longer-term (Codex parity)

A local stdio/socket method mirroring Codex:

- `account/read` (presence only)  
- `account/rateLimits/read`  
- `account/usage/read`  

The JSON file is enough for UMA v1.

## UMA behavior once the file exists

1. Detect Grok Bot.app + `desktop-status.json` signed in  
2. Read `usage-status.json` with bounded size + strict schema  
3. Admit only with current structured local read + provider-reported (or explicitly estimated) provenance  
4. Show remaining % / windows on the main panel like Codex  

Until then: diagnostics may report “Grok Bot detected / signed in / meter missing”; **main panel stays empty for Grok**.

## Acceptance test for Grok Bot owners

1. Sign in to Grok Bot.  
2. Confirm `usage-status.json` appears within one usage refresh.  
3. Confirm percentages move after real usage (or after backend refresh).  
4. Sign out → file deleted or `signedIn: false`.  
5. File contains no tokens or account identifiers.
