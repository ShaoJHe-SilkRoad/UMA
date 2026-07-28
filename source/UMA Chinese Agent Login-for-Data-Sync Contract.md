# UMA Chinese Agent Login-for-Data-Sync Contract

Version: 1.0
Date: 2026-07-25
Authority: UMA Logic 1.3 and Founder M2WADBG-R3 override

## Eligibility

`Login for Data Sync` is optional assistance, not a provider card. It appears
in Settings only when all conditions are true:

1. the integration is explicitly registered as a Chinese Agent;
2. an official or separately admitted structured local usage source exists;
3. that source is known to require provider authentication;
4. the provider supplies an official application-owned login flow;
5. authentication is the sole remaining admission condition.

It is absent for unsupported, untrusted, manual-only, website/OCR/private-data,
or schema-unproven sources. Existing-session-only providers expose no login
action. WorkBuddy exposes no login action because no real-time local source is
admitted.

## Human-controlled workflow

```text
Settings
→ Chinese Agent integration
→ Login for Data Sync
→ open the provider's official desktop application
→ Human completes provider-owned login
→ return to UMA
→ Check Again
→ one coalesced eligibility scan
→ display only after a successful validated local structured read
```

Opening the official application and completing login do not mutate the
previous admission result and do not display the provider. Failed Check Again
keeps it hidden. Successful Check Again publishes it to the main panel and
Assistant from the same admission set.

## Credential and ownership boundary

UMA provides no custom login form and never automates or inspects login. It
never receives passwords, SMS codes, QR contents, cookies, access or refresh
tokens, Keychain values, auth-database contents, browser storage, or account
identity beyond an unavoidable nonidentifying authenticated-state result.
UMA does not inspect a vendor-owned browser flow.

If authentication expires or the current read fails, the provider disappears
from both surfaces. Safe setup preferences remain, and Settings may offer
another explicit login attempt only when the eligibility rules still hold.

## Capability

The provider-neutral declaration is:

```swift
enum ProviderLoginAssistance {
    case none
    case existingSessionOnly
    case userInitiatedOfficialChineseAppLogin
}
```

No current provider implementation is added by this contract.
