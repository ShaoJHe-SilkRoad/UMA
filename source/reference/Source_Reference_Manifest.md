# UMA DEV 4 Source Reference Manifest

**Version:** 1.0  
**Date:** 2026-07-28  
**Purpose:** Define the current local source/reference set for ChatGPT DEV 4 and Codex DEV  
**Canonical repository:** `ShaoJHe-SilkRoad/UMA`  
**Recommended repository location:** `source/reference/`  
**Current milestone:** M4 — Manus Official API v2 Integration

---

## 0. Current authority

Read in this order:

```text
Current Founder instruction
→ current live origin/main
→ latest accepted DEV report
→ Scroll_2.0.md
→ UMA_Logic_1.4.md
→ Provider_Status_Matrix.md
→ active M4_Plan.md
→ one selected task from M4_Goal.md
→ UMA_0.11_closeout.md
→ Goal Mode 2.0
→ historical source records
```

The DEV 3 shift report remains the main historical handoff.

Its pre-merge GitHub status is superseded by the current merged main state.

---

## 1. Current files

| File | Role | Active status |
|---|---|---|
| `Scroll_2.0.md` | Master roadmap and progress ledger | Governing |
| `UMA_Logic_1.4.md` | Product, data, source, UI, privacy, and implementation contract | Governing |
| `UMA_0.11_closeout.md` | Immutable 0.11 closeout and provenance | Historical-current closeout |
| `Provider_Status_Matrix.md` | Current provider/source/admission matrix | Governing |
| `M4_Plan.md` | Manus integration plan | Active |
| `M4_Goal.md` | Copy-ready M4 execution tasks | Active; send one task at a time |
| `Source_Reference_Manifest.md` | This source precedence and installation record | Governing index |

Supporting execution aid:

```text
Codex_DEV4_Source_Install_and_Manus_Start.md
```

---

## 2. Current baseline

```text
Repository:
ShaoJHe-SilkRoad/UMA

Canonical remote branch:
main

Known current main:
469be4d6cf411a89401c2341807a57aef176d852

Qualified 0.11 development commit:
459ea1321817e391ba80fe79f19edb0352fc76cb

Main integration commit:
ff6553943280836fb0d3db5289f85b163c41c1a3

Installed application:
/Users/juliushe/Desktop/UMA_0.11.app

Version/build:
0.11 / 202607270003

Current production providers:
Codex
WorkBuddy

Next program:
M4 Manus
```

A newer legitimate `origin/main` may supersede the known hash.

Codex must inspect and record the newer state, not reset to the known hash.

---

## 3. Historical source files

Retain, but do not treat as current authority:

```text
shift_report_Dev3.md
Scroll 1.2 and earlier Scroll files
UMA Logic 1.3.1 and earlier
M3_Plan.md
M3_Goal.md
M2W_Plan.md
M2W_Goals.md
M2W WorkBuddy research
Monitor Mechanism historical reference
older scope locks
older QA ledgers
older package closures
```

Historical files preserve development evidence.

Do not delete them for cleanliness.

---

## 4. Replacement map

| Historical active claim | Current replacement |
|---|---|
| `Founder PR not merged` | PR #3 merged; main `469be4d...` |
| `M3 Claude next` | Claude deferred |
| `WorkBuddy queued/manual only` | WorkBuddy live-qualified Account Web Sync |
| `UMA 0.10.1 baseline` | UMA 0.11 / build `202607270003` |
| `Codex-only main panel` | Equal Codex + WorkBuddy multi-Agent panel |
| `M4 pre-release readiness` | Founder-selected M4 Manus integration |
| `Manus source unknown` | Official API v2 source candidate; admission still required |

---

## 5. Installation contract

Recommended repository structure:

```text
source/
├── reference/
│   ├── Scroll_2.0.md
│   ├── UMA_Logic_1.4.md
│   ├── UMA_0.11_closeout.md
│   ├── Provider_Status_Matrix.md
│   ├── M4_Plan.md
│   ├── M4_Goal.md
│   └── Source_Reference_Manifest.md
└── historical execution records...
```

M4-B0 installs the files.

Do not move all historical source records into `reference/`.

The folder is for current governing material only.

---

## 6. Codex read rule

At the beginning of an M4 task, Codex should read:

```text
source/reference/Source_Reference_Manifest.md
source/reference/Scroll_2.0.md
source/reference/UMA_Logic_1.4.md
source/reference/Provider_Status_Matrix.md
source/reference/M4_Plan.md
the selected section of source/reference/M4_Goal.md
```

Read `UMA_0.11_closeout.md` when the task needs historical provenance or inherited verification.

Do not load every historical QA ledger unless the active task requires it.

---

## 7. M4 start rule

The first task is:

```text
M4-B0
```

After M4-B0 PASS:

```text
M4-G1
```

M4-G1 performs source admission and secret-boundary design.

Do not start M4-G2 until M4-G1 returns GO or CONDITIONAL GO.

Do not request the Manus API key in Codex.

---

## 8. Official Manus documentation skill

Official install command:

```bash
npx skills add https://open.manus.ai/docs --skill manus-api --agent codex --global --yes
```

This installs documentation guidance.

It does not contain or configure an API key.

Current live official documentation outranks the static source snapshot.

---

## 9. Update protocol

After each accepted major milestone:

1. update only current-state fields that changed;
2. preserve immutable closeouts;
3. mark planned versus shipped behavior;
4. record exact branch/commit/package;
5. update Provider Status Matrix;
6. update Scroll current milestone;
7. update Logic only when the product contract changes;
8. do not silently rewrite historical evidence;
9. stage exact files;
10. create a docs commit;
11. stop before the next milestone.

---

## 10. Secret boundary

The source/reference folder must never contain:

- API keys;
- tokens;
- cookies;
- auth databases;
- Keychain exports;
- raw provider payloads;
- real account identity;
- raw task/conversation content;
- real private balance fixtures;
- full process environment;
- screenshots containing sensitive data.

---

## 11. Completion state

```text
Source pack generation:
COMPLETE

Local repository installation:
PENDING M4-B0

Manus source admission:
PENDING M4-G1

Manus implementation:
NOT STARTED
```
