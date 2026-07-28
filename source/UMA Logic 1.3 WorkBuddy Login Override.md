# UMA Logic 1.3 WorkBuddy Login Override

Version: 1.0
Goal: M2WLOGIN-G1

This WorkBuddy-only override permits official-app login assistance without
admitting a WorkBuddy data source.

## Override

- Settings may expose Login for Data Sync under WorkBuddy.
- UMA may use public Launch Services and `NSWorkspace` APIs to locate, open,
  activate, and observe the official WorkBuddy app.
- The expected identity is `com.workbuddy.workbuddy`.
- A failed or unverifiable signature does not authorize modification or
  bypass. It permits opening only after the exact warning and explicit
  official-vendor-install confirmation are shown. That confirmation applies
  only to the exact reviewed installation and is cleared when it changes.
- A running app is activated only when its exact bundle URL matches the
  reviewed installation; bundle identifier alone is insufficient.
- Personal and Enterprise are instruction modes only.
- Check Again is one user-triggered eligibility check, not an automatic
  refresh trigger.
- A successful flow ends with an unsupported-source result until a separate
  official structured Credits contract is admitted.

## Non-overrides

- WorkBuddy manual Credits remain manual-only and hidden from product surfaces.
- Application launch, lifecycle notification, wake, Settings open, and flow
  completion do not trigger provider admission.
- No WorkBuddy connector, Hook, browser reader, OCR path, private data reader,
  or network client is created.
- No real login is automated or required for acceptance.
