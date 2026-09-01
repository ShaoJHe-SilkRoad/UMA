# UMA 0.14 application foundation contract

## Preference persistence and migration

- Production constructs `ApplicationPreferences.production`, which wraps the
  existing standard application domain. No persisted key is renamed.
- Tests construct `ApplicationPreferences.inMemory()` or an explicitly named
  isolated suite. A missing test store is never interpreted as permission to
  use the production domain.
- The typed catalog preserves the 0.13 language, Desktop Assistant, provider,
  display, consent, and automatic-refresh encodings. Unknown keys are left
  untouched.
- First 0.14 launch reads existing 0.13 values in place. New keys use explicit
  defaults and are written only when the corresponding feature changes them.
- Provider preference migration remains non-destructive: legacy display keys
  are read, the v1 envelope is added only when useful legacy values exist, and
  unreadable/future envelopes block replacement.
- Rollback does not require or perform a schema reset. UMA 0.13 can continue to
  read its original keys; it ignores additive 0.14 keys.

## Version authority

`Configuration/UMAProductVersion.plist` is the structured authority for the
active 0.14 development identity, the frozen 0.13 release reference, and the
Safari Host/Companion compatibility version. The strict reader accepts only a
closed key allowlist. Active 0.14 development packaging consumes the authority;
existing build/root environment overrides remain supported.

This foundation does not authorize signing, notarization, release packaging,
or changes to the frozen 0.13 product.
