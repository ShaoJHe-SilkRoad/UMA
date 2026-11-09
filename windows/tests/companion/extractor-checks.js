// The shared extractor against the Mac's saved Usage page fixtures (Tests/Fixtures/ClaudeUsage), with the same
// expectations as Tests/CodexUsageUITests/ClaudeUsageExtractorFixtureTests.swift, and the vendored copies of the
// shared scripts compared with the Mac originals (D16). The extractor carries the approved Chinese rules (plan §18), so
// both its Mac original and its Windows copy are pinned; the other three must equal the Mac originals. Line endings are
// ignored, because git may check either file out with CRLF. Times are local, as the page shows them.
(function (root) {
  "use strict";
  const shared = ["provider-ownership-v2.js", "owned-provider-tab-v2-reducer.js", "content-script.js"];
  const pinnedExtractor = Object.freeze({
    mac: "def5975b4b22c118fde912871ba9501a1df78d5129d24e99414b0fb740eb8291",
    windows: "16478bc934801b2c0b0d6cd20e137f3572c6d503649ac1ed04084ce16d1b20d5",
  });
  const usage = { protocol: "https:", origin: "https://claude.ai", pathname: "/new", search: "", hash: "#settings/usage" };
  const local = (month, day, hour, minute = 0) => new Date(2026, month - 1, day, hour, minute);
  const iso = (date) => date ? date.toISOString() : null;
  const pageNow = local(10, 27, 15);
  const sessionReset = iso(local(10, 27, 18, 40));
  const weeklyReset = iso(local(10, 31, 9));

  async function text(path) {
    const response = await fetch(path, { cache: "no-store" });
    if (!response.ok) throw new Error("missing " + path);
    return await response.text();
  }
  async function digest(path) {
    const raw = new Uint8Array(await (await fetch(path, { cache: "no-store" })).arrayBuffer());
    const bytes = raw.filter((b) => b !== 13);
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    return [...hash].map((b) => b.toString(16).padStart(2, "0")).join("");
  }
  async function extract(fixture, location = usage, now = pageNow) {
    const html = await text(fixture.startsWith("zh-") ? `/windows/tests/companion/fixtures/${fixture}.html` : `/Tests/Fixtures/ClaudeUsage/${fixture}.html`);
    const documentLike = new DOMParser().parseFromString(html, "text/html");
    const r = UMAClaudeUsageExtractor.extractResult(documentLike, location, now);
    const o = r.observation || {};
    return {
      status: r.status,
      fiveHour: o.fiveHour ? o.fiveHour.usedPercentage : null,
      weekly: o.weeklyAllModels ? o.weeklyAllModels.usedPercentage : null,
      fiveHourReset: o.fiveHour ? o.fiveHour.resetAt : null,
      weeklyReset: o.weeklyAllModels ? o.weeklyAllModels.resetAt : null,
    };
  }
  function same(actual, expected) {
    return Object.keys(expected).every((key) => actual[key] === expected[key]);
  }

  async function run() {
    const results = [];
    const check = async (name, body) => {
      try { const detail = await body(); results.push({ name, pass: detail === true, detail: detail === true ? "" : JSON.stringify(detail) }); }
      catch (error) { results.push({ name, pass: false, detail: String(error) }); }
    };
    for (const file of shared) {
      await check(`vendored ${file} matches the Mac original`, async () =>
        (await digest(`/windows/browser-extension/Shared/${file}`)) === (await digest(`/BrowserExtension/Shared/${file}`)) || "differs");
    }
    await check("Mac extractor is the version the Windows copy was made from", async () =>
      (await digest("/BrowserExtension/Shared/claude-usage-extractor.js")) === pinnedExtractor.mac || "the Mac extractor changed: sync the Windows copy deliberately");
    await check("Windows extractor is the reviewed copy with Chinese rules", async () =>
      (await digest("/windows/browser-extension/Shared/claude-usage-extractor.js")) === pinnedExtractor.windows || "the Windows extractor changed: review and re-pin");
    const expect = (fixture, expected, location, now) => check(`extractor: ${fixture}${now ? " at 9 AM" : ""}${location ? " other route" : ""}`, async () => {
      const actual = await extract(fixture, location, now);
      return same(actual, expected) || actual;
    });
    await expect("redesign-2026-10", { status: "success", fiveHour: 8, weekly: 14, fiveHourReset: sessionReset, weeklyReset });
    await expect("redesign-2026-10", { status: "success", fiveHour: 8, weekly: 14, fiveHourReset: null, weeklyReset }, undefined, local(10, 27, 9));
    await expect("redesign-2026-10-equal-values", { status: "success", fiveHour: 14, weekly: 14, fiveHourReset: sessionReset, weeklyReset });
    await expect("redesign-2026-10-model-rows", { status: "success", fiveHour: 8, weekly: 14, fiveHourReset: sessionReset, weeklyReset });
    await expect("legacy-2026-08", { status: "success", fiveHour: 44, weekly: 61, fiveHourReset: "2026-08-01T16:00:00.000Z", weeklyReset: "2026-08-05T09:00:00.000Z" });
    await expect("negative-two-weekly-rows", { status: "success", fiveHour: 8, weekly: null });
    await expect("negative-shared-row", { status: "success", fiveHour: null, weekly: 14 });
    await expect("negative-remaining-share", { status: "usageUnavailable", fiveHour: null, weekly: null });
    await expect("negative-login", { status: "signInRequired" });
    await expect("redesign-2026-10", { status: "routeRejected" }, { ...usage, hash: "#settings/account" });
    const wordings = [
      ["Resets at 6:40 PM", local(10, 27, 18, 40)], ["Resets 4 PM", local(10, 27, 16)], ["Resets at 2:00 PM", local(10, 28, 14)],
      ["Resets at 18:40", local(10, 27, 18, 40)], ["Resets Saturday 9:00 AM", local(10, 31, 9)], ["Resets Sat 9:00 AM", local(10, 31, 9)],
      ["Resets on Saturday at 9:00 AM", local(10, 31, 9)], ["Resets Tuesday 2:00 PM", local(11, 3, 14)], ["Resets tomorrow at 9:00 AM", local(10, 28, 9)],
      ["Resets Nov 2, 9:00 AM", local(11, 2, 9)], ["Resets in 2 hr 5 min", null], ["Resets in 45 min", null], ["Resets soon", null],
      ["Resets Aug 5", null], ["Resets at 13:00 PM", null],
    ];
    for (const [wording, expected] of wordings) {
      await check(`reset wording: ${wording}`, async () => {
        const read = iso(UMAClaudeUsageExtractor.textResetDate(wording, pageNow));
        return read === iso(expected) || { read, expected: iso(expected) };
      });
    }
    // zh-Hans (plan §18). pageNow is Tuesday 27 October 2026, 15:00 local.
    await expect("zh-2026-11", { status: "success", fiveHour: 8, weekly: 14, fiveHourReset: sessionReset, weeklyReset });
    await expect("zh-2026-11", { status: "success", fiveHour: 8, weekly: 14, fiveHourReset: null, weeklyReset }, undefined, local(10, 27, 9));
    await expect("zh-2026-11-equal-values", { status: "success", fiveHour: 14, weekly: 14, fiveHourReset: sessionReset, weeklyReset });
    await expect("zh-2026-11-model-rows", { status: "success", fiveHour: 8, weekly: 14, fiveHourReset: sessionReset, weeklyReset });
    await expect("zh-negative-two-weekly-rows", { status: "success", fiveHour: 8, weekly: null });
    await expect("zh-negative-remaining-share", { status: "usageUnavailable", fiveHour: null, weekly: null });
    await expect("zh-negative-login", { status: "signInRequired" });
    const zhWordings = [
      ["18:40 重置", local(10, 27, 18, 40)], ["今天18:40 重置", local(10, 27, 18, 40)], ["今天 14:00 重置", local(10, 28, 14)],
      ["明天09:00 重置", local(10, 28, 9)], ["周六09:00 重置", local(10, 31, 9)], ["星期六09:00 重置", local(10, 31, 9)],
      ["星期六 09:00 重置", local(10, 31, 9)], ["星期天09:00 重置", local(11, 1, 9)], ["周日09:00 重置", local(11, 1, 9)],
      ["周二14:00 重置", local(11, 3, 14)], ["周二18:40 重置", local(10, 27, 18, 40)], ["11月2日09:00 重置", local(11, 2, 9)],
      ["2 小时后重置", null], ["即将重置", null], ["周八09:00 重置", null], ["25:00 重置", null], ["13月2日09:00 重置", null],
      ["2月30日09:00 重置", null], ["星期六上午9:00 重置", null], ["限额重置", null],
    ];
    for (const [wording, expected] of zhWordings) {
      await check(`reset wording (zh-Hans): ${wording}`, async () => {
        const read = iso(UMAClaudeUsageExtractor.textResetDateZh(wording, pageNow));
        return read === iso(expected) || { read, expected: iso(expected) };
      });
    }
    for (const [share, expected] of [["已使用 15%", 15], ["已使用15%", 15], ["已使用 100%", 100], ["剩余 15%", null], ["已使用 101%", null], ["已用 15%", null]]) {
      await check(`share (zh-Hans): ${share}`, async () => UMAClaudeUsageExtractor.finitePercentage(share) === expected || UMAClaudeUsageExtractor.finitePercentage(share));
    }
    return results;
  }
  root.AUVExtractorChecks = Object.freeze({ run });
})(globalThis);
