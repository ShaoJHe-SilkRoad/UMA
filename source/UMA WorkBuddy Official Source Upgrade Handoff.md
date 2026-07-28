# UMA WorkBuddy Official Source Upgrade Handoff

Version: 1.0
Goal: M2WLOGIN-G1

## Current decision

WorkBuddy automatic Credits synchronization remains **NO-GO**. Login
assistance does not change that decision.

UMA can currently:

- find and validate the public identity of the installed WorkBuddy app;
- ask for explicit privacy and, where needed, official-install confirmation;
- bind any unverified-install confirmation to the exact reviewed installation;
- open or activate only the exact reviewed official app bundle;
- provide Personal or Enterprise instructions;
- record safe flow milestones;
- perform one explicit, coalesced eligibility check;
- report that no supported local Credits source exists.

UMA cannot currently:

- machine-verify WorkBuddy authentication;
- read or synchronize WorkBuddy Credits;
- infer authentication from process state, windows, browser/WeChat completion,
  or a manual Credit record;
- surface-admit WorkBuddy as an automatic provider.

## Upgrade admission criteria

A later goal may consider an official source only after WorkBuddy publicly
ships or documents all of:

1. a supported third-party integration mechanism;
2. a structured Credits or account-availability schema;
3. a stable event, getter, or read contract;
4. explicit authentication and lifecycle semantics;
5. a privacy boundary that requires no credentials, browser scraping, OCR,
   private files, databases, process memory, or network interception.

Admission requires a new Founder-authorized goal, focused connector tests,
privacy review, package validation, and explicit provider-surface acceptance.
This handoff is not authorization to resume Hook research or M2W-LIVE.
