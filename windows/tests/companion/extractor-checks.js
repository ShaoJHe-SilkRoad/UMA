// The shared extractor against the Mac's saved Usage page fixtures (Tests/Fixtures/ClaudeUsage), with the same
// expectations as Tests/CodexUsageUITests/ClaudeUsageExtractorFixtureTests.swift, and the vendored copies of the
// shared scripts compared byte for byte with the Mac originals (D16). Times are local, as the page shows them.
(function (root) {
  "use strict";
  const shared = ["claude-usage-extractor.js", "provider-ownership-v2.js", "owned-provider-tab-v2-reducer.js", "content-script.js"];
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
    const bytes = new Uint8Array(await (await fetch(path, { cache: "no-store" })).arrayBuffer());
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    return [...hash].map((b) => b.toString(16).padStart(2, "0")).join("");
  }
  async function extract(fixture, location = usage, now = pageNow) {
    const html = await text(`/Tests/Fixtures/ClaudeUsage/${fixture}.html`);
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
    return results;
  }
  root.AUVExtractorChecks = Object.freeze({ run });
})(globalThis);
