# Chinese (zh-Hans) rules for the Claude Usage page reader — note for the Mac

AUV for Windows added these rules to its copy of `BrowserExtension/Shared/claude-usage-extractor.js` (plan §18, approved 2026-11-08). The Mac original was not changed: on a claude.ai account whose interface is Chinese, the Mac companion reads nothing (`TARGET_DATA_TIMEOUT`). To give the Mac the same support, apply this diff to the Mac original. After that, the two copies can be identical again (D16).

Fixtures with the observed Chinese structure: `windows/tests/companion/fixtures/zh-*.html`. Checks: `windows/tests/companion/extractor-checks.js` (zh-Hans section).

```diff
--- BrowserExtension/Shared/claude-usage-extractor.js
+++ windows/browser-extension/Shared/claude-usage-extractor.js
@@ -5,6 +5,11 @@
  * the exact official personal Usage route and emits a small normalized quota
  * object. Page source, broad page text, URL data, private identity fields, and spending data never
  * leave this function.
+ *
+ * AUV for Windows copy: identical to the Mac original (BrowserExtension/Shared)
+ * except for additive Chinese (zh-Hans) rules, marked "zh-Hans" below: row
+ * labels, the "已使用 N%" used share, and "<day>HH:MM 重置" resets. Every English
+ * rule is unchanged. See windows/docs/chrome-extension-plan.md §18.
  */
 (function (root) {
   "use strict";
@@ -45,15 +50,23 @@
   });
 
   const HEADING_PATTERNS = Object.freeze({
-    fiveHour: [/^current session$/i, /^5[- ]hour limit$/i, /^five[- ]hour limit$/i],
-    weeklyAllModels: [/^all models$/i, /^weekly limit(?:s)?$/i, /^7[- ]day limit$/i, /^this week$/i],
+    fiveHour: [/^current session$/i, /^5[- ]hour limit$/i, /^five[- ]hour limit$/i,
+      // zh-Hans
+      /^当前会话$/, /^5\s?小时限额$/],
+    weeklyAllModels: [/^all models$/i, /^weekly limit(?:s)?$/i, /^7[- ]day limit$/i, /^this week$/i,
+      // zh-Hans
+      /^本周$/, /^所有模型$/, /^每周限额$/],
   });
 
   // Labels that mark a different quota row. They are never read as quota; they
   // only bound a row so a neighbouring row's percentage cannot be claimed.
   const BOUNDARY_PATTERNS = Object.freeze({
-    modelSpecific: [/^(?:sonnet|opus|haiku)(?: only)?$/i],
-    extraUsage: [/^extra usage$/i],
+    modelSpecific: [/^(?:sonnet|opus|haiku)(?: only)?$/i,
+      // zh-Hans
+      /^(?:sonnet|opus|haiku)\s?(?:专用|模型)$/i],
+    extraUsage: [/^extra usage$/i,
+      // zh-Hans
+      /^额外用量$/],
   });
 
   const MAXIMUM_ROW_DEPTH = 8;
@@ -211,7 +224,9 @@
     if (typeof raw !== "string" || raw.length > 16) return null;
     // "8%" and "8% used" are the used share. Anything else, including
     // "8% left", is not read, so a remaining share is never taken as used.
-    const match = raw.trim().match(/^(100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s*(?:%(?:\s+used)?)?$/i);
+    // zh-Hans: "已使用 8%" is the used share too; "剩余 8%" is not read.
+    const match = raw.trim().match(/^(100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s*(?:%(?:\s+used)?)?$/i)
+      || raw.trim().match(/^已使用\s?(100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s?%$/);
     if (!match) return null;
     const parsed = Number(match[1]);
     return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
@@ -330,6 +345,37 @@
     return atClock(now, ahead, time);
   }
 
+  // zh-Hans: the Chinese page writes "周一00:30 重置", "星期六06:00 重置",
+  // "今天18:40 重置", "明天09:00 重置", "11月2日09:00 重置" or "18:40 重置", in
+  // 24-hour local time. Only these shapes are read. A countdown such as
+  // "2 小时后重置", or any other wording, leaves the reset unknown.
+  const ZH_WEEKDAYS = "日一二三四五六";
+  const ZH_RESET = /^(?:(今天|明天)|(?:周|星期)([一二三四五六日天])|(\d{1,2})月(\d{1,2})日)?(\d{1,2}):(\d{2})重置$/;
+  function textResetDateZh(text, now) {
+    const parts = text.replace(/\s+/g, "").match(ZH_RESET);
+    if (!parts) return null;
+    const [, relativeDay, weekdayChar, monthText, dayText, hourText, minuteText] = parts;
+    const time = { hours: Number(hourText), minutes: Number(minuteText) };
+    if (time.hours > 23 || time.minutes > 59) return null;
+    if (monthText) {
+      const month = Number(monthText) - 1;
+      const date = new Date(now.getFullYear(), month, Number(dayText), time.hours, time.minutes);
+      if (month < 0 || month > 11 || date.getMonth() !== month || date.getDate() !== Number(dayText)) return null;
+      if (date.getTime() < now.getTime() - 86400000) date.setFullYear(date.getFullYear() + 1);
+      return date;
+    }
+    if (!relativeDay && !weekdayChar || relativeDay === "今天") {
+      const today = atClock(now, 0, time);
+      return today.getTime() > now.getTime() - 60000 ? today : atClock(now, 1, time);
+    }
+    if (relativeDay === "明天") return atClock(now, 1, time);
+    const weekday = weekdayChar === "天" ? 0 : ZH_WEEKDAYS.indexOf(weekdayChar);
+    if (weekday < 0) return null;
+    let ahead = (weekday - now.getDay() + 7) % 7;
+    if (ahead === 0 && atClock(now, 0, time).getTime() <= now.getTime()) ahead = 7;
+    return atClock(now, ahead, time);
+  }
+
   // Two different reset texts in one row cannot both be its reset, so neither
   // is reported.
   function textReset(card, horizonMinutes, now) {
@@ -339,8 +385,12 @@
     for (const candidate of candidates) {
       if (candidate.childElementCount > 0) continue;
       const text = boundedOwnText(candidate, 64);
-      if (!text || !/^resets\s/i.test(text)) continue;
-      const date = textResetDate(text, now);
+      if (!text) continue;
+      const english = /^resets\s/i.test(text);
+      // zh-Hans
+      const chinese = !english && /重置$/.test(text);
+      if (!english && !chinese) continue;
+      const date = english ? textResetDate(text, now) : textResetDateZh(text, now);
       if (!date || !Number.isFinite(date.getTime())) continue;
       const ahead = (date.getTime() - now.getTime()) / 60000;
       if (ahead < -1 || ahead > horizonMinutes) continue;
@@ -485,6 +535,7 @@
     finitePercentage,
     normalizedTimestamp,
     textResetDate,
+    textResetDateZh,
     validateObservation,
     extract,
     extractResult,
```
